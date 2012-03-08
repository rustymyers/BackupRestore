#!/bin/bash

# Beta version. Needs testing. Please report bugs.
# rustymyers@gmail.com

# Script to backup home folders on volume before restoring disk image with DeployStudio
# Uses the directories in the /Users folder of the target machine to back up data, user account details, and password.
# Use accompanying ds_restore_data.sh to pur users and user folders back onto computer after re-imaging.

function help {
    cat<<EOF

    Usage: `basename $0` [ -e "guest admin shared" ] [ -v "/Volumes/Macintosh HD" ] [ -u /Users ] [ -d "/Volumes/External Drive/" ] [ -t tar ]
    Variables can be set in DeployStudio variables window when running script.
    BackupRestore Variables:
    -q Unique Identifier 
			Enter the MAC address of the backup you want to restore.
			For example, if you backup a computer and its MAC address
			was: 000000000001. You can then specify that MAC as the
			variable to restore to a different computer.
		 	Read Me has more information on its use.
	-c Remove User Cache
			Will delete the Users /Library/Cache
	 		folder before backing up the data.
    -e Users to Skip
            Must use quotes for multiple users
            Default is "guest" and "shared"
                You must specify "guest" and
                "shared" if your use the argument
    -v Target volume
            Specify full path to mount point of volume
            Default is the internal volume
            e.g. /Volumes/Macintosh HD
    -u User path on target
            Set to path of users on volume
            Default is /Users
    -d Backup destination
            Specify full path to the backup volume
            Default is /tmp/DSNetworkRepository
    -t Backup tool (tar) - Still working on this one!
            Select backup software, Default tar
            tar = Use tar with gzip to backup.
            ditto and rsync NOT WORKING, yet!
            -removed- ditto = Use ditto with gzip to backup
            -removed- rsync = Use rsync to backup

    
EOF

}

#Variables:
# Ignore these accounts or folders in /Users (use lowercase):
# Shared folder is excluded using "shared"
export EXCLUDE=( "shared" "guest" "deleted users" "rusty" "bree" )
# Unique ID for plist and common variable for scripts
export UNIQUE_ID=`echo "$DS_PRIMARY_MAC_ADDRESS"|tr -d ':'` # Add Times? UNIQUE_ID=`date "+%Y%m%d%S"`
# Should we remove users cache folder? 1 = yes, 0 = no. Set to 0 by default.
export RMCache="0"
# DS Script to backup user data with tar to Backups folder on repository.
export DS_REPOSITORY_BACKUPS="$DS_REPOSITORY_PATH/Backups/$UNIQUE_ID"
# Set Path to internal drive
export DS_INTERNAL_DRIVE=`system_profiler SPSerialATADataType|awk -F': ' '/Mount Point/ { print $2}'|head -n1`
# Alternate metod to set DS_INTERNAL_DRIVE. May work better than system_profiler for drives not connected via SATA
# This method failed when a Time Machine volume was disk0, the above command worked.
# export DS_INTERNAL_DRIVE=`mount | grep disk0 | sed -e 's/^.* on //g' | sed -e 's/ (.*$//g'|head -n1`
# Set Path to the folder with home folders
export DS_USER_PATH="/Users"
# Default backup tool
export BACKUP_TOOL="tar"
# Filevault backup ## What the fuck is this for? ## It's the filename of the backup of the Filevault keys (FilevaultKeys.tar). Not currently implemented
export FilevaultKeys="FilevaultKeys"

# Parse command line arguments
while getopts :e:q:cv:u:d:t:h opt; do
	case "$opt" in
		e) EXCLUDE="$OPTARG";;
		q) UNIQUE_ID="$OPTARG";;
		c) RMCache="1";;
		v) DS_INTERNAL_DRIVE="$OPTARG";;
		u) DS_USER_PATH="$OPTARG";;
		d) DS_REPOSITORY_BACKUPS="$OPTARG/Backups/$UNIQUE_ID";;
		t) BACKUP_TOOL="$OPTARG";;
		h) 
			help
			exit 0;;
		\?)
			echo "Usage: `basename $0` [-e Excluded Users] [-v Target Volume] [-u User Path] [-d Destination Volume] [ -t Backup Tool ]"
			echo "For more help, run: `basename $0` -h"
			exit 0;;
	esac
done
shift `expr $OPTIND - 1`

# Set variables that are dependent on getopts
# Set path to dscl
export dscl="$DS_INTERNAL_DRIVE/usr/bin/dscl"
# Internal drive's directory node
export INTERNAL_DN="$DS_INTERNAL_DRIVE/var/db/dslocal/nodes/Default"


# Prints variables in the log. Great for troubleshooting. 		
echo -e "Backup Arguments"
echo -e "Unique ID:				$UNIQUE_ID"
echo -e "Remove User Cache:			$RMCache"
echo -e "Excluded users:		${EXCLUDE[@]}"
echo -e "Target Volume:			$DS_INTERNAL_DRIVE"
echo -e "User Path on target:	$DS_USER_PATH"
echo -e "Backup Destination: 	$DS_REPOSITORY_PATH"
echo -e "Backup tool:			$BACKUP_TOOL"
echo -e "dscl path:					$dscl"
echo -e "Internal Directory:		$INTERNAL_DN"

function RUNTIME_ABORT {
# Usage:
# argument 1 is error message
# argument 2 is success message
if [ "${?}" -ne 0 ]; then
	echo "RuntimeAbortWorkflow: $1...exiting."
	exit 1
else
	echo -e "\t$2"
fi
}

echo "educ_backup_data.sh - v0.7.1 beta ("`date`")"

# Check that the backups folder is there. 
# If its missing, make it.
if [[ ! -d "$DS_REPOSITORY_PATH/Backups" ]]; then
	mkdir -p "$DS_REPOSITORY_PATH/Backups"
fi
# Check that the computer has a backup folder.
# If its missing, make it.
if [[ ! -d "$DS_REPOSITORY_PATH/Backups/$UNIQUE_ID" ]]; then
	mkdir -p "$DS_REPOSITORY_PATH/Backups/$UNIQUE_ID"
fi

# Start script...
echo "Scanning Users folder..."

# List users on the computer
for i in "$DS_INTERNAL_DRIVE""$DS_USER_PATH"/*/;
do
	echo -e ""
	# Change the account name to lowercase
    USERZ=$(basename "$i"| tr '[:upper:]' '[:lower:]');
    # Set keep variable
	keep=1;
    for x in "${EXCLUDE[@]}";
    do
        [[ $x = $USERZ ]] && keep=0;

    done;
    if (( $keep )); then
		echo "Backing up $USERZ to $DS_REPOSITORY_BACKUPS"
		# Backup user account to computer's folder
		DS_BACKUP="$DS_INTERNAL_DRIVE$DS_USER_PATH/$USERZ"
		DS_ARCHIVE="$DS_REPOSITORY_BACKUPS/$USERZ-HOME"
		
		case $BACKUP_TOOL in
			tar )
			# Remove users cache? If set to 1, then yes.
			if [[ $RMCache = 1 ]]; then
				# Remove users home folder cache
				rm -Rf "$DS_BACKUP/Library/Cache/"
			fi
			# Backup users with tar
			/usr/bin/tar -czf "$DS_ARCHIVE.tar" "$DS_BACKUP" && echo -e "\tSucess: Home successfully backed up using tar" 2>/dev/null || echo -e "RuntimeAbortWorkflow: \tError: could not back up home"
			RUNTIME_ABORT "RuntimeAbortWorkflow: \tError: could not back up home" "\tSucess: Home successfully backed up using tar"
			# Backup Output Errors:
			# tar: Removing leading '/' from member names
			# tar: getpwuid(<uid>) failed: No such file or directory
				;;
			# ditto )
			# # Backup users with ditto
			# Create sparsedisk image with options for quota? size? 
			# hdiutil create -size 1g -type SPARSE -fs HFS+ -volname "$USERZ" "$DS_ARCHIVE.ditto.dmg
			# hdiutil attach "$DS_ARCHIVE.ditto.dmg"
			# -z backups up with gzip -j flag will compress it with bzip2 and -k will use PKZip
			# /usr/bin/ditto -vXcz --keepParent "$DS_BACKUP" "$DS_ARCHIVE.cpio.gz"	 && echo -e "Home successfully backed up using ditto" || echo -e "Could not back up home"
			# 	;;
			# rsync )
			# #Backup using rsync
			# /usr/bin/rsync -av --update "$DS_BACKUP" "$DS_ARCHIVE.rsync/"
			# 	;;
			* )
			echo "RuntimeAbortWorkflow: Backup Choice: $BACKUP_TOOL. Invalid flag, no such tool...exiting." 
			help
			exit 1
				;;
		esac
		# Backup User Account
		## Old way to check for network and mobile accounts. The idea is that local accounts have a UID < 1000 and network accounts are greater than 1000. May not hold true universally.
		# UserID=`"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" uid|awk '{print $2}'`
		# if [[ "$UserID" -gt "1000" ]]; then #this is a mobile account
		## Check dscl for "OriginalNodeName" if its a mobile account. If the account doesn't exist, its a network account. 
		# if [[ `"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" dsAttrTypeStandard:OriginalNodeName|grep -E "^OriginalNodeName:"` ]]; then #this is a mobile account
		## Another Method that should work: check the Authentication Authority for ShadowHash. Only local accounts have it.
		# if [[ `"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" dsAttrTypeStandard:AuthenticationAuthority|grep -E "Shadow"` ]]; then #this is a local account
		## Check for PrimaryGroupID of 20. All local users should have the ID of 20, DS accounts will be different. Probably not the best way to check. Broken in 10.7
		# if [[ `"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" dsAttrTypeStandard:PrimaryGroupID|grep -E "20"` ]]; then #this is a local account
		## Another Method that should work: check for OriginalAuthenticationAuthority. Only directory accounts have it.
		if [[ ! `"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" |grep -E "OriginalAuthenticationAuthority"` ]]; then #this is a local account
			echo -e "\tSucess: $USERZ is a Local account"
			# User PrimaryGroupID echo. Turned off because it was just extra logging.
			# UserzPrimaryGroupID=`"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" dsAttrTypeStandard:PrimaryGroupID|grep -E "20"`
			# echo -e "The users primary group ID is: $UserzPrimaryGroupID"
			# echo -e "If the ID is 20, we treat the user as a local user. Otherwise it's a network or mobile account"
			# User data backup plist
			DS_USER_BACKUP_PLIST="$DS_REPOSITORY_BACKUPS/$USERZ-USER.plist"
			# Test for existance of user
			"$dscl" -plist -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" 1>/dev/null || echo "Error: User record does not exist"
			# Output all User Details to plist
			"$dscl" -plist -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" gid home picture realname shell uid generateduid AuthenticationAuthority HomeDirectory > "$DS_USER_BACKUP_PLIST" 2>&1 && echo -e "\tSucess: account backed up successfully"
			# Backup password hash
			GenUID=`/usr/libexec/PlistBuddy -c "print dsAttrTypeNative\:generateduid:0" "$DS_USER_BACKUP_PLIST"`
			if [[ -e "$DS_INTERNAL_DRIVE/var/db/shadow/hash/$GenUID" ]]; then
				/bin/cp "$DS_INTERNAL_DRIVE/var/db/shadow/hash/$GenUID" "$DS_REPOSITORY_BACKUPS/$USERZ.$GenUID"  && echo -e "\tSucess: password backed up successfully"
			else
				echo -e "\tError: no password for $USERZ"
			fi
			# Check if user is an admin
			if [[ -z `"$dscl" -plist -f "$INTERNAL_DN" localonly -read "/Local/Target/Groups/admin" "GroupMembership"|grep -w "$USERZ"` ]]; then
				/usr/libexec/PlistBuddy -c "add :isAdmin string no" "$DS_USER_BACKUP_PLIST"
			else
				/usr/libexec/PlistBuddy -c "add :isAdmin string yes" "$DS_USER_BACKUP_PLIST"
				echo -e "\tSucess: $USERZ is an admin"
			fi
			# User has a Filevault account, backup Filevault passwords
			if [[ `"$DS_INTERNAL_DRIVE/usr/libexec/PlistBuddy" -c "print :dsAttrTypeStandard\:HomeDirectory:0" "$DS_USER_BACKUP_PLIST"` ]]; then
				echo -e "\tSucess: $USERZ has Filevault turned on"
			else
				echo -e "\tSucess: $USERZ does not have Filevault turned on"
			fi
		else
			echo -e "\tSucess: $USERZ is a Mobile account"
			# User data backup plist
			DS_USER_BACKUP_PLIST="$DS_REPOSITORY_BACKUPS/$USERZ-NETUSER.plist"
			# Get the details for Filevault. Test for homedir on restore and use details when needed.
			if [[ `"$dscl" -plist -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" dsAttrTypeStandard:HomeDirectory|grep -E "home_dir"` ]]; then
				"$dscl" -plist -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" uid generateduid HomeDirectory NFSHomeDirectory AuthenticationAuthority > "$DS_USER_BACKUP_PLIST" 2>&1 && echo -e "\tSucess: minimum details for filevault backed up." || echo -e "\tError: filevault details can't be backed up."
			else
				echo -e "\tSucess: account excluded for mobile account"
			fi
			echo -e "\tSucess: password excluded for mobile account"
			# Check if user is an admin
			if [[ -z `"$dscl" -plist -f "$INTERNAL_DN" localonly -read "/Local/Target/Groups/admin" "GroupMembership"|grep -w "$USERZ"` ]]; then
				/usr/libexec/PlistBuddy -c "add :isAdmin string no" "$DS_USER_BACKUP_PLIST" 2>/dev/null
			else
				/usr/libexec/PlistBuddy -c "add :isAdmin string yes" "$DS_USER_BACKUP_PLIST" 2>/dev/null
				echo -e "\tSucess: $USERZ is an admin"
			fi
		fi
	else 
		echo -e "Excluding $USERZ" 
		echo -e ""
	fi 
done

# Backup Filevault Keychains
if [[ -e "$DS_INTERNAL_DRIVE/Library/Keychains/FileVaultMaster.cer" ]]; then
	echo -e "Backing up FileVault Master Keychains"
	/usr/bin/tar -czpf "$DS_REPOSITORY_BACKUPS/FilevaultKeys.tar" "$DS_INTERNAL_DRIVE/Library/Keychains/FileVaultMaster.cer" "$DS_INTERNAL_DRIVE/Library/Keychains/FileVaultMaster.keychain" && echo -e "Master Keychains successfully backed up using tar" %>/dev/null || echo -e "Could not back up master keychains"
else
	echo -e "No FileVault Master Keychains found"
fi

echo "educ_backup_data.sh - end"
exit 0

#############################################################################################

## To Do
#
# Test USB Ethernet dongle for one machine
# Plan for "Deleted Users" folder

## Changes
# 
# Wednesday, June, 22, 2011 - v0.7.1
#	- Added flag to remove user cache folder before backing up home.
# 	- Testing new DS_INTERNAL_DRIVE variable command.
# 
# Tuesday, April, 19, 2011 - v0.7
# 	- Updated code to use new user deliminator from '.' to '-'
# 
# Saturday, April, 16, 2011 - v0.6
# 	- Lots of little error fixes from midnight coding.
# 	- Tried to unify script messages
# 
# Monday, April, 14, 2011 - v0.5
#	- Change name of user plists and home backups to account for names with '.' in them.
# 
# Monday, March, 28, 2011 - v0.4.7
# 	- Moved dscl and internal directory variables outside and above for loop. 
#	- Uncommented test variables. Easier to troubleshoot the script.
# 
# Tuesday, March 22, 2011 - v0.4.6
# 	- Filevault restores done with first boot scripts
# 	- Removed extra plist created with backup tool name. If I need this, I'll use the same plist as the user details.
# 	- Added AuthenticationAuthority and HomeDirectory to plist backup
# 	- Some dscl and PlistBuddy errors show when running scripts, this is normal.
# 	- Added "deleted users" folder to exclude list
# 
# Friday, March 18, 2011 - v0.4.5
# 	- Changed test for mobile/network accounts, again. Now seems to work!
# 
# Wednesday, Febuary 09, 2011 - v0.4.4
# 	- Adding to git
# 	- Added rsync as an backup tool option
# 	- Removed Unique ID from user data, its only used for the backup folder.
# 	- Changed test for mobile/network accounts. Should work better.
# 
# Tuesday, February 01, 2011
# 	- Bug fixing the tar and ditto backups and variables
# 
# Monday, January 31, 2011
# 	- Added flag to backup using ditto or tar, check help
# 
# Thursday, January 27, 2011
# 	- Chenged the way we check for network and mobile accounts. Now looking at dscl for OriginalNodeName
# 		Thanks to hunterbj
#
# Tuesday, January 18, 2011
# 	- Adding variables that can be set within DeployStudio
#		Icluding: Users to skip, Target volume, User path on target, and Backup destination
# 
# Monday December 20, 2010 
# 	- Fixed issue with user account not showing in system preferences after restoring.
# 	- Added support for restoring admin rights for network users

# How to Backup Filevault homes
# 	Filevault accounts have GeneratedUID
# 	dscl . read /Users/file HomeDirectory | awk '{print $2}'
# 	Backup sparseimage
# 	/Users/file/file.sparsebundle
# 	- Backup keychain master passwords and cert
# 	- /Library/Keychain/FileVaultMaster.cer
# 	- /Library/Keychain/FileVaultMaster.keychain
# 	Recreate user - Wonder if its necessary to restore the accounts?
# 	/System/Library/CoreServices/ManagedClient.app/Contents/Resources/createmobileaccount -n usershortname
# 	Restore sparesimage

# Written by Rusty Myers
# 
# Credit to Pete Akins and his amazingly awesome createUser.pkg script. 
# It was instrumental in learning how to backup and create users.

