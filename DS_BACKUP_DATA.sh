#!/bin/bash

# OS X Lion Beta version. Needs testing. Please report bugs.
# Code that is not used for Lion is removed. Use old scripts for 10.6
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
            ditto = Use ditto with gzip to backup
            rsync NOT WORKING, yet!
            -removed- rsync = Use rsync to backup
	-s Select files - New Feature (11/2013)
			This option allows you to backup only 
			select files. Pass the files as an
			argument or specify them in the script.
			This option uses an uncompressed tar.
			I have not test this at all.
EOF

}

function addFile {
	# Pass file argument and add it to a TAR named $DS_ARCHIVE
	newFile="$1"
	# Check for existing TAR
	if [[ -e "$2" ]]; then
		# Append file to TAR
		/usr/bin/tar -rpf "$2" "$1" &> /dev/null
	else
		# No TAR, create one first
		/usr/bin/tar -cpf "$2" "$1" &> /dev/null
	fi
}

#Variables:
# Ignore these accounts or folders in /Users (use lowercase):
# Shared folder is excluded using "shared"
export EXCLUDE=( "shared" "guest" "deleted users" "spider" )
# Unique ID for plist and common variable for scripts
export UNIQUE_ID=`echo "$DS_PRIMARY_MAC_ADDRESS"|tr -d ':'` # Add Times? UNIQUE_ID=`date "+%Y%m%d%S"`
# Should we remove users cache folder? 1 = yes, 0 = no. Set to 0 by default.
export RMCache="1"
# DS Script to backup user data with tar to Backups folder on repository.
export DS_REPOSITORY_BACKUPS="$DS_REPOSITORY_PATH/Backups/$UNIQUE_ID"
# Set Path to internal drive
export DS_INTERNAL_DRIVE=`system_profiler SPSerialATADataType|awk -F': ' '/Mount Point/ { print $2}'|head -n1`
# Set Path to the folder with home folders
export DS_USER_PATH="/Users"
# Default backup tool
export BACKUP_TOOL="tar"
# Filevault backup ## What the fuck is this for? ## It's the filename of the backup of the Filevault keys (FilevaultKeys.tar). Not currently implemented
export FilevaultKeys="FilevaultKeys"
# Turn on select backup of files. 1 turns it on, 0 turns it off. Only back up from the BACKUP_LIST below...
BACKUP_SELECTED="0"
# List of files to backup when backing up only select files, from the context of the Users home folder ~/.
export BACKUP_LIST="Library/Preferences/applet.plist
Library/Preferences/com.apple.Desktop.plist"

# Parse command line arguments
while getopts :e:q:cv:u:d:t:s:h opt; do
	case "$opt" in
		e) EXCLUDE="$OPTARG";;
		q) UNIQUE_ID="$OPTARG";;
		c) RMCache="1";;
		v) DS_INTERNAL_DRIVE="$OPTARG";;
		u) DS_USER_PATH="$OPTARG";;
		d) DS_REPOSITORY_BACKUPS="$OPTARG/Backups/$UNIQUE_ID";;
		t) BACKUP_TOOL="$OPTARG";;
		s) BACKUP_SELECTED="1"
			BACKUP_LIST="$OPTARG";;
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
echo -e "## Backup Arguments"
echo -e "# Unique ID:					$UNIQUE_ID"
echo -e "# Remove User Cache:			$RMCache"
echo -e "# Excluded users:				${EXCLUDE[@]}"
echo -e "# Target Volume:				$DS_INTERNAL_DRIVE"
echo -e "# User Path on target:			$DS_USER_PATH"
echo -e "# DS Repo: 					$DS_REPOSITORY_PATH"
echo -e "# Backup Path:					$DS_REPOSITORY_BACKUPS"
echo -e "# Backup tool:				$BACKUP_TOOL"
echo -e "# dscl path:					$dscl"
echo -e "# Internal Directory:			$INTERNAL_DN"
echo -e "# Backup select files:			$BACKUP_SELECTED"
echo -e "# Backup file list:			$BACKUP_LIST"

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

echo "educ_backup_data.sh - v0.7.2 (Lion) beta ("`date`")"

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
		echo "<>Backing up $USERZ to $DS_REPOSITORY_BACKUPS"
		# Backup user account to computer's folder
		DS_BACKUP="$DS_INTERNAL_DRIVE$DS_USER_PATH/$USERZ"
		DS_ARCHIVE="$DS_REPOSITORY_BACKUPS/$USERZ-HOME"
		
		# Remove users cache? If set to 1, then yes.
		# These may not work...need to check.
		if [[ $RMCache = 1 ]]; then
			# Remove users home folder cache
			echo -e "\t-Removing user cache..."
			rm -rfd "$DS_BACKUP/Library/Cache/"
			# Empty the trash as well
			echo -e "\t-Emptying user Trash..."
			rm -rfd "$DS_BACKUP/.Trash/*"
		fi
		
		# Check backup tool and backup selected option. Must use tar for backing up select files.
		if [[ $BACKUP_SELECTED = 1 && $BACKUP_TOOL != "tar" ]]; then
			echo "RuntimeAbortWorkflow: Error: Backing up selected files is only supported with the tar backup_tool"
			exit 32
		fi
		
		case $BACKUP_TOOL in
			tar )
				if [[ $BACKUP_SELECTED = 1 ]]; then
					# Backup select files
					SAVEIFS=$IFS
					IFS=$(echo -en "\n\b")
					for FilePath in $BACKUP_LIST; do
						# Backup users with uncompressed tar
						addFile "$FilePath" "$DS_ARCHIVE.tar"
						RUNTIME_ABORT "RuntimeAbortWorkflow: Error: could not back up home" "\t+Sucess: Home successfully backed up using tar"
					done
					IFS=$SAVEIFS
				else
					# Backup whole home folder
					# Backup users with compressed tar
					/usr/bin/tar -czpf "$DS_ARCHIVE.tar" "$DS_BACKUP" &> /dev/null
					RUNTIME_ABORT "RuntimeAbortWorkflow: Error: could not back up home" "\t+Sucess: Home successfully backed up using tar"
				fi
				;;
			ditto ) ## Contributed by Miles Muri, Merci!
			echo -e "Backing up user home directory to $DS_ARCHIVE.zip"
			ditto -c -k --sequesterRsrc --keepParent "$DS_BACKUP" "$DS_ARCHIVE.zip" 
			RUNTIME_ABORT "RuntimeAbortWorkflow: Error: Could not back up home" "\t+Sucess: Home successfully backed up using ditto"
			 	;;
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

		# Done backing up files...
		
		# Log which tool was used to backup user
		/usr/libexec/PlistBuddy -c "add :backuptool string $BACKUP_TOOL" "$DS_REPOSITORY_BACKUPS/$USERZ.BACKUP.plist" &>/dev/null
		
		# Backup User Account
		## Check for OriginalAuthenticationAuthority. Only directory accounts have it.
		# While I don't currently have a mobile account from a directory service, I've asked someone else to test it. It seems to work! Thanks to Nassy on IRC for testing!
		if [[ ! `"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" |grep -E "OriginalAuthenticationAuthority"` ]]; then #this is a local account
			echo -e "\t+Sucess: $USERZ is a Local account"
			# Perhaps All I need to do is backup the dslocal users plist?
			if [[ -e "${DS_INTERNAL_DRIVE}/var/db/dslocal/nodes/Default/users/$USERZ.plist" ]]; then
				cp -p "${DS_INTERNAL_DRIVE}/var/db/dslocal/nodes/Default/users/$USERZ.plist" "${DS_REPOSITORY_BACKUPS}/$USERZ.plist"
				RUNTIME_ABORT "RuntimeAbortWorkflow: Error: Could not back up user account" "\t+Sucess: User account successfully backed up"
			fi
			# User data backup plist
			DS_USER_BACKUP_PLIST="$DS_REPOSITORY_BACKUPS/$USERZ-USER.plist"
			# Check if user is an admin
			if [[ -z `"$dscl" -plist -f "$INTERNAL_DN" localonly -read "/Local/Target/Groups/admin" "GroupMembership"|grep -w "$USERZ"` ]]; then
				/usr/libexec/PlistBuddy -c "add :isAdmin string no" "$DS_USER_BACKUP_PLIST"
			else
				/usr/libexec/PlistBuddy -c "add :isAdmin string yes" "$DS_USER_BACKUP_PLIST"
				echo -e "\t+Sucess: $USERZ is an admin"
			fi

		else
			echo -e "\t+Sucess: $USERZ is a Mobile account"
			echo -e "\t+Sucess: account excluded for mobile account"
			# User data backup plist
			DS_USER_BACKUP_PLIST="$DS_REPOSITORY_BACKUPS/$USERZ-NETUSER.plist"
			# Check if user is an admin
			if [[ -z `"$dscl" -plist -f "$INTERNAL_DN" localonly -read "/Local/Target/Groups/admin" "GroupMembership"|grep -w "$USERZ"` ]]; then
				/usr/libexec/PlistBuddy -c "add :isAdmin string no" "$DS_USER_BACKUP_PLIST" 2>/dev/null
			else
				/usr/libexec/PlistBuddy -c "add :isAdmin string yes" "$DS_USER_BACKUP_PLIST" 2>/dev/null
				echo -e "\t+Sucess: $USERZ is an admin"
			fi
		fi
	else 
		echo -e "<>Excluding $USERZ" 
		echo -e ""
	fi 
done

echo "educ_backup_data.sh - end"
exit 0

#############################################################################################

## To Do
#
# Switch to Serial Number?
# Plan for "Deleted Users" folder
# Log paths to backup folders
# Backup More User Records?? 
# 	/var/db/dslocal/nodes/Default/sharepoints/User Public Folder.plist
# 	groups/com.applesharepoint.group.[12].plist
# 	Restore _lpadmin.plist access, _appserveradm.plist, _appserverusr.plist, 

## Changes
# 
# Thursday, December, 1, 2011 - v0.7.2
# 	- Removing code for Lion testing
# 	- Backing up dslocal user.plist instead of all the records individually.
# 	- Added in ditto for backing up the home. Credit to Miles Muri for the code.
#	- Miles Muri also submitted a lot of code and comments that helped prep for Lion. Thank You!
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

# ****** Rusty's musings on ditto ******
# Create sparsedisk image with options for quota? size? 
# hdiutil create -size 1g -type SPARSE -fs HFS+ -volname "$USERZ" "$DS_ARCHIVE.ditto.dmg
# hdiutil attach "$DS_ARCHIVE.ditto.dmg"
# -z backups up with gzip -j flag will compress it with bzip2 and -k will use PKZip
# /usr/bin/ditto -vXcz --keepParent "$DS_BACKUP" "$DS_ARCHIVE.cpio.gz" && echo -e "Home successfully backed up using ditto" || echo -e "Could not back up home"
# ****** Rusty's musings on ditto ******

# ****** Rusty's musings on detecting mobile and local accounts ******
## Old way to check for network and mobile accounts. The idea is that local accounts have a UID < 1000 and network accounts are greater than 1000. May not hold true universally.
# UserID=`"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" uid|awk '{print $2}'`
# if [[ "$UserID" -gt "1000" ]]; then #this is a mobile account
## Check dscl for "OriginalNodeName" if its a mobile account. If the account doesn't exist, its a network account. 
# if [[ `"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" dsAttrTypeStandard:OriginalNodeName|grep -E "^OriginalNodeName:"` ]]; then #this is a mobile account
## Another Method that should work: check the Authentication Authority for ShadowHash. Only local accounts have it.
# if [[ `"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" dsAttrTypeStandard:AuthenticationAuthority|grep -E "Shadow"` ]]; then #this is a local account
## Check for PrimaryGroupID of 20. All local users should have the ID of 20, DS accounts will be different. Probably not the best way to check. Broken in 10.7
# if [[ `"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" dsAttrTypeStandard:PrimaryGroupID|grep -E "20"` ]]; then #this is a local account
# ****** Rusty's musings on detecting mobile and local accounts ******

## local accounts don't work in 10.7 yet anyway...
## dscl doesn't work much... changed to not falsely id local accounts
## Before, this would spit out a bunch of error messages, but since it 
## wasn't equal to "OriginalAuthenticationAuthority", then it thought it 
## was local. It wasn't. :-(
## this should work if dscl worked.
## TODO - make this work with another tool to check network accounts
## id -n might work with | to sed, I'm not well enough versed...
