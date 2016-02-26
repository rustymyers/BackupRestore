#!/bin/bash

# OS X 10.7+ Supported. Please report bugs.
# Code that is not used for Lion is removed. Use old scripts for 10.6
# rustymyers@gmail.com

# Script to backup home folders on volume before restoring disk image with DeployStudio
# Uses the directories in the /Users folder of the target machine to back up data, user account details, and password.
# Use accompanying ds_restore_data.sh to pur users and user folders back onto computer after re-imaging.

function help {
    cat<<EOF

    Usage: `basename $0` [ -e "guest admin shared" ] [ -v "/Volumes/Macintosh HD" ] [ -u /Users ] [ -d "/Volumes/External Drive/" ] [ -t tar ] [ -n New Archive ]
    Variables can be set in DeployStudio variables window when running script.
    BackupRestore Variables:
    -q Unique Identifier 
			Enter the MAC address of the backup you want to restore.
			For example, if you backup a computer and its MAC address
			was: 000000000001. You can then specify that MAC as the
			variable to restore to a different computer.
			Use 'SKIP' to backup users without unique folder. (Can't be restored)
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
    -t Backup tool (dmg)
            Select backup software, Default tar
            dmg = Create a dmg with users data.
            tar = Use tar with gzip to backup.
            ditto = Use ditto with gzip to backup
            rsync (Disabled) = Use rsync to backup - Still working on this one!
    -n New backup
            Create a new archive each run by adding a date to end of name. (Can't be restored)
    -p Prompt for Unique ID (BETA)
            Prompt the user during backup for the unique ID to use from the hard coded lists.
EOF

}

ifError () {
# check return code passed to function
exitStatus=$?
# set a time
TIME=`date "+%Y-%m-%d-%H:%M:%S"`
if [[ $exitStatus -ne 0 ]]; then
# if rc > 0 then print error msg and quit
echo -e "$0 Time:$TIME $1 Exit: $exitStatus"
# exit $exitStatus
fi
}

#Variables:
# Ignore these accounts or folders in /Users (use lowercase):
# Shared folder is excluded using "shared"
export EXCLUDE=( "shared" "guest" "deleted users" )

# Unique ID for plist and common variable for scripts
# export UNIQUE_ID=`echo "$DS_PRIMARY_MAC_ADDRESS"|tr -d ':'` # Add Times? UNIQUE_ID=`date "+%Y%m%d%S"`

# Use Serial number for UNIQUE_ID
export UNIQUE_ID=`system_profiler SPHardwareDataType | awk -F ': ' '/Serial Number/ {print $2}'`

# Force skip for testing and Chad - enabling this causes backups to appear in root of backup folder, instead of inside per computer folders
# export UNIQUE_ID='SKIP'

# Should we remove users cache folder? 1 = yes, 0 = no. Set to 0 by default.
export RMCache="0"

# DS Script to backup user data with tar to Backups folder on repository.
if [[ $UNIQUE_ID = 'SKIP' ]]; then
	export DS_REPOSITORY_BACKUPS="$DS_REPOSITORY_PATH/Backups/"
else
	export DS_REPOSITORY_BACKUPS="$DS_REPOSITORY_PATH/Backups/$UNIQUE_ID"
fi

# Force the Scripts to prompt for Unique ID during runtime:
# PROMPT_UNIQUE="1"

# Set Path to internal drive - Not working with Fusion Drives!!
# export DS_INTERNAL_DRIVE=`system_profiler SPSerialATADataType|awk -F': ' '/Mount Point/ { print $2}'|head -n1`

# create disk array
DISKARRAY=( )
diskCounter=0
# get mounted disks
mountedDisks=$(mount | grep -i ^/dev | awk '{print $1}')
# check each disk for Internal and Mounted
for i in $mountedDisks; do
	# put each disk's info into a plist
	diskutil info -plist $i > /tmp/tmpdisk.plist
	# check each disk for internal, if true...
	if [[ $(defaults read /tmp/tmpdisk.plist Internal) == 1 ]]; then
		# get mount point
		mountPoint=$(defaults read /tmp/tmpdisk.plist MountPoint)
		# add mount point to array
		DISKARRAY[diskCounter]=$mountPoint
		let diskCounter=diskCounter+1
	fi
done

echo "Found ${#DISKARRAY[@]} disks"
echo "Disks: ${DISKARRAY[*]}"

# Set Path to the folder with home folders
export DS_USER_PATH="/Users"

# Default backup tool
export BACKUP_TOOL="tar"

# Filename of the backup of the Filevault keys (FilevaultKeys.tar). Not currently implemented
export FilevaultKeys="FilevaultKeys"

# Parse command line arguments
while getopts :e:q:cv:u:d:t:nph opt; do
	case "$opt" in
		e) EXCLUDE="$OPTARG";;
		q) 
			UNIQUE_ID="$OPTARG"
			if [[ $UNIQUE_ID = 'SKIP' ]]; then
				DS_REPOSITORY_BACKUPS="$OPTARG/Backups/"
			else
				DS_REPOSITORY_BACKUPS="$OPTARG/Backups/$UNIQUE_ID"
			fi;;
		c) RMCache="1";;
		v) DS_INTERNAL_DRIVE="$OPTARG"
			guessInternalDrive=false;;
		u) DS_USER_PATH="$OPTARG";;
		d) 
			if [[ $UNIQUE_ID = 'SKIP' ]]; then
				DS_REPOSITORY_BACKUPS="$OPTARG/Backups/"
			else
				DS_REPOSITORY_BACKUPS="$OPTARG/Backups/$UNIQUE_ID"
			fi;;
		t) BACKUP_TOOL="$OPTARG";;
		n) NEW_ARCHIVE="1";;
		p) PROMPT_UNIQUE="1";;
		h) 
			help
			exit 0;;
		\?)
			echo "Usage: `basename $0` [-e Excluded Users] [-v Target Volume] [-u User Path] [-d Destination Volume] [ -t Backup Tool ] [ -n New Archive ] [ -p Prompt for Uniqe ID ]"
			echo "For more help, run: `basename $0` -h"
			exit 0;;
	esac
done
shift `expr $OPTIND - 1`

userDiskArray=()
userDiskCounter=0
# If we don't have an internal drive passed to us, guess it
if [[ $guessInternalDrive==true ]]; then
	# Set internal drive we're going to point to
	for i in "${DISKARRAY[@]}"; do
		echo "Checking $i for $DS_USER_PATH path..."
		# if the directory for users exists
		if [[ -d "$i$DS_USER_PATH" ]]; then
			echo "Found $i$DS_USER_PATH"
			userDiskArray[userDiskCounter]=$i
		else
			echo "$i does not have $DS_USER_PATH. Not a backup source."
		fi
	done
fi
echo "Found ${#userDiskArray[@]} disks with $DS_USER_PATH on it."
echo "Disks: ${userDiskArray[*]}"

if [[  ${#userDiskArray[@]} > 1 ]]; then
	echo "We found more than one disk. Better set the default with -v"
	RUNTIME_ABORT "We found more than one disk. Better set the default with -v"
elif [[ ${#userDiskArray[@]} < 1 ]]; then
	echo "We found less than one disk. Better check your drives"
	RUNTIME_ABORT "We found less than one disk. Better check your drives"
else
	echo "Setting internal drive to ${userDiskArray[0]}"
	DS_INTERNAL_DRIVE=${userDiskArray[0]}
fi

# Set variables that are dependent on getopts
# Set path to dscl
export dscl="$DS_INTERNAL_DRIVE/usr/bin/dscl"
# Internal drive's directory node
export INTERNAL_DN="$DS_INTERNAL_DRIVE/var/db/dslocal/nodes/Default"

# if we are supposed to prompt for unique ID, do it now
if [[ "$PROMPT_UNIQUE" == "1" ]]; then
	POPUP=`dirname "$0"`/cocoaDialog.app/Contents/MacOS/cocoaDialog
	if [[ ! -e "$POPUP" ]]; then
		echo "We could not find CocoaDialog. Make sure the .app is in the same directory as this script!"
		RUNTIME_ABORT "We could not find CocoaDialog. Make sure the .app is in the same directory as this script!"
	fi
	RUNMODE="standard-dropdown"
	TITLE="Select your option:"
	TEXT="Please select your unique ID from the list"
	OTHEROPTS="--no-cancel --float --string-output"
	# Change this list to the ID's you want to use:
	ITEMS=( "BACKUP1" "BACKUP2" "BACKUP3" "BACKUP4" )
	ICON="group"
	ICONSIZE="128"

	#Do the dialog, get the result and strip the Okay button code
	RESPONSE=`$POPUP $RUNMODE $OTHEROPTS --icon $ICON --icon-size $ICONSIZE --title "${TITLE}" --text "${TEXT}" --items "${ITEMS[@]}"`
	RESPONSE=`echo $RESPONSE | sed 's/Ok //g'`
	UNIQUE_ID="$RESPONSE"
	
fi
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
echo -e "# New Archive:			$NEW_ARCHIVE"

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

echo "educ_backup_data.sh - v0.7.4 (Lion) beta ("`date`")"

# Check that the backups folder exists on repo and contains backup folder for this computer.
# If either are missing, make them.
if [[ ! -d "$DS_REPOSITORY_BACKUPS" ]]; then
	mkdir -p "$DS_REPOSITORY_BACKUPS"
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
		# Backup 
		echo "<>Backing up $USERZ to $DS_REPOSITORY_BACKUPS"
		# Moving to after user check, only create these folders if we find someone to backup.
		# Check that the backups folder is there. 
		# If its missing, make it.
		if [[ ! -d "$DS_REPOSITORY_BACKUPS" ]]; then
			mkdir -p "$DS_REPOSITORY_BACKUPS"
		fi
		# set path to user account from computers user folder
		DS_BACKUP="$DS_INTERNAL_DRIVE$DS_USER_PATH/$USERZ"
		# Append date to create a new backup
		if [[ $NEW_ARCHIVE = 1 ]]; then
			DS_ARCHIVE="$DS_REPOSITORY_BACKUPS/$USERZ-HOME-$(date "+%Y.%m.%d.%H.%M.%S")"
		else
			DS_ARCHIVE="$DS_REPOSITORY_BACKUPS/$USERZ-HOME"
		fi
		# Remove users cache? If set to 1, then yes.
		if [[ $RMCache = 1 ]]; then
			# Remove users home folder cache
			echo -e "\t-Removing user cache..."
			rm -rfd "$DS_BACKUP/Library/Cache/"
			# Empty the trash as well
			echo -e "\t-Emptying user Trash..."
			rm -rfd "$DS_BACKUP/.Trash/*"
		fi

		case $BACKUP_TOOL in
			tar )
			# Backup users with tar
			# /usr/bin/tar -czpf "$DS_ARCHIVE.tar" "$DS_BACKUP" &> /dev/null
			# testing moving into Users folder to make archive - suggested by Per Olofsson
			(cd "$DS_INTERNAL_DRIVE$DS_USER_PATH" && tar -czf "$DS_ARCHIVE.tar" "$USERZ")
			ifError "Tar failed to backup home folder?!"
			RUNTIME_ABORT "RuntimeAbortWorkflow: Error: could not back up home with tar" "\t+Sucess: Home successfully backed to $DS_ARCHIVE.tar"
				;;
			ditto ) ## Contributed by Miles Muri, Merci!
			echo -e "Backing up user home directory to $DS_ARCHIVE.zip"
			ditto -c -k --sequesterRsrc --keepParent "$DS_BACKUP" "$DS_ARCHIVE.zip" 
			RUNTIME_ABORT "RuntimeAbortWorkflow: Error: Could not back up home with ditto" "\t+Sucess: Home successfully backed up to $DS_ARCHIVE.zip"
			 	;;
			rsync )
			#Backup using rsync
			# /usr/bin/rsync -av --update "$DS_BACKUP" "$DS_ARCHIVE.rsync/"
			echo "RuntimeAbortWorkflow: Backup Choice: $BACKUP_TOOL.  Still working on this one! Got a fix?...exiting."
				;;
			dmg )
			#Backup using hdiutil
			echo -e "Backing up user home directory to $DS_ARCHIVE.dmg"
			/usr/bin/hdiutil create -srcfolder "$DS_BACKUP" "$DS_ARCHIVE/"
			RUNTIME_ABORT "RuntimeAbortWorkflow: Error: Could not back up home with hdiutil" "\t+Sucess: Home successfully backed up to $DS_ARCHIVE.dmg"
				;;
			* )
			echo "RuntimeAbortWorkflow: Backup Choice: $BACKUP_TOOL. Invalid flag, no such tool...exiting." 
			help
			exit 1
				;;
		esac
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
# Plan for "Deleted Users" folder
# Log paths to backup folders
# Backup More User Records?? 
# 	/var/db/dslocal/nodes/Default/sharepoints/User Public Folder.plist
# 	groups/com.applesharepoint.group.[12].plist
# 	Restore _lpadmin.plist access, _appserveradm.plist, _appserverusr.plist, 

## Changes
# Friday, Febuary 26, 2016 - 0.7.5
# 	- Adding CocoaDialog Support for Unique ID, requested by Steve M. Thanks Steve!
# 
# Thursday, October 22, 2015 - 0.7.4
# 	- Changing tar workflow to fix issue with restore (sub-Users Users folder)
# 	- Switch to Serial Number
# 	- Updating method to determine internal drive for Fusion Systems
# 
# Wednesday, February 25, 2015 - 0.7.3
# 	- Added dmg backup option
# 	- Added option to create unique backup
# 	- Moving backup folder root path creation to after user check, 
# 		only create these folders if we find someone to backup.
# 
# Thursday, October, 3, 2014 - v0.7.3
#   - Fixed a bug that didn't allow -q to be used without -d. Now when specifying a unique ID -d is not required. 
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
