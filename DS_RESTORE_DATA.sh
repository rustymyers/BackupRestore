#!/bin/bash

# OS X Lion Beta version. Needs testing. Please report bugs.
# Code that is not used for Lion is removed. Use old scripts for 10.6
# rustymyers@gmail.com

# Script to restore user accounts and user directories from the ds_backup_data.sh
# Uses the files backed up to MAC address of the machine,
# stored in the DeployStudio repository Backups folder

function help {
	
    cat<<EOF

	Usage: `basename $0` [ -e "guest admin shared" ] [ -v "/Volumes/Macintosh HD" ] [ -u /Users ] [ -d "/Volumes/External Drive/" ] [ -t tar ]
	Variables can be set in DeployStudio variables window when running script.
	BackupRestore Variables:
	-q Unique Identifier.
			Enter the MAC address of the backup you want to restore.
			For example, if you backup a computer and its MAC address
			was: 000000000001. You can then specify that MAC as the
			variable to restore to a different computer.
	-v Target volume
			Specify full path to mount point of volume
			Default is the \$DS_LAST_RESTORED_VOLUME volume
			e.g. "/Volumes/Macintosh HD"
	-u User path on target
			Set to path of users on volume
			Default is /Users
	-r Backup Repository Path
			Set to path of the backup volume
			Default is the DS Repository
			e.g. "/Volumes/NFSDrive/Backups"
	-p Prompt for Unique ID (BETA)
			Prompt the user during restore for the unique ID to use from the hard coded lists.
	

EOF

}


# Default is set to the Last Restored Volume variable from DS
# If you want to restore the user without restoring an image,
# set the destination to the volume you wish to target

# if there was no recenlty restored volume
if [[ -z $DS_LAST_RESTORED_VOLUME ]]; then
	# Set Path to internal drive - Not working with Fusion Drives!
	# export DS_INTERNAL_DRIVE=`system_profiler SPSerialATADataType | awk -F': ' '/Mount Point/ { print $2}'|head -n1`
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
	
	# Set the script to guess the internal drive when there is no last restored volume
	guessInternalDrive=true
else
	# Set Path to last restored volume
	export DS_LAST_RESTORED_VOLUME="/Volumes/$DS_LAST_RESTORED_VOLUME"
fi

# Force the Scripts to prompt for Unique ID during runtime:
# PROMPT_UNIQUE="1"

# Unique ID for plist and common variable for scripts
# export UNIQUE_ID=`echo "$DS_PRIMARY_MAC_ADDRESS"|tr -d ':'` # Add Times? UNIQUE_ID=`date "+%Y%m%d%S"`
# Use Serial number for UNIQUE_ID
export UNIQUE_ID=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/ {print $(NF-1)}')

# Set Path to the folder with home folders
export DS_USER_PATH="/Users"

while getopts :v:q:r:u:ph opt; do
	case "$opt" in
		# e) EXCLUDE="$OPTARG";;
		v) DS_LAST_RESTORED_VOLUME="$OPTARG"
			guessInternalDrive=false;;
		q) UNIQUE_ID="$OPTARG";;
		r) DS_REPOSITORY_PATH="$OPTARG";;
		u) DS_USER_PATH="$OPTARG";;
		p) PROMPT_UNIQUE="1";;
		h) 
			help
			exit 0;;
		\?)
			echo "Usage: `basename $0` [-v Target Volume ] [-q MAC Address of target machine] [-r Backup Repository ] [ -p Prompt for Uniqe ID ]"
			echo "For more help, run: `basename $0` -h"
			exit 0;;
	esac
done
shift `expr $OPTIND - 1`

userDiskArray=()
userDiskCounter=0
# If we don't have an internal drive passed to us from paramters or DS_LAST_RESTORED_VOLUME, guess it
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
	DS_LAST_RESTORED_VOLUME=${userDiskArray[0]}
fi


# DS Script to backup user data with tar to Backups folder on repository.
export DS_REPOSITORY_BACKUPS="$DS_REPOSITORY_PATH/Backups/$UNIQUE_ID"

if [[ -e "$DS_REPOSITORY_BACKUPS" ]]; then
	# Set backup count to number of tar files in backup repository - Contributed by Rhon Fitzwater
	# Updated grep contributed by Alan McSeveney <alan@themill.com>
	# export DS_BACKUP_COUNT=`/bin/ls -l "$DS_REPOSITORY_BACKUPS" | grep -E '\.(tar|zip)$' | wc -l`
	export DS_BACKUP_COUNT=`/bin/ls -l "$DS_REPOSITORY_BACKUPS" | grep -E '.*\.tar|.*\.zip' | wc -l`
else
	echo "Could not find $DS_REPOSITORY_BACKUPS"
fi

# Set Variables that are dependent on getopts
# Set path to dscl
export dscl="$DS_LAST_RESTORED_VOLUME/usr/bin/dscl"
# Internal Drive directory node
export INTERNAL_DN="$DS_LAST_RESTORED_VOLUME/var/db/dslocal/nodes/Default"

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

# Uncomment this section when you want to see the variables in the log. Great for troubleshooting. 
echo -e "# Restore Arguments"
echo -e "# Last Restored Volume:			$DS_LAST_RESTORED_VOLUME"
echo -e "# Unique ID:					$UNIQUE_ID"
echo -e "# User Path on target:			$DS_USER_PATH"
echo -e "# Restore Repository: 			$DS_REPOSITORY_PATH"
echo -e "# Backups Repository: 			$DS_REPOSITORY_BACKUPS"
echo -e "# Internal Drive:				$DS_INTERNAL_DRIVE"
echo -e "# Backup Count:			$DS_BACKUP_COUNT"
echo -e "# dscl path:					$dscl"
echo -e "# Internal Directory:				$INTERNAL_DN"

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

echo "educ_restore_data.sh - v0.7.6 (High Sierra) beta ("`date`")"

# Check if any backups exist for this computer.  If not, exit cleanly. - Contributed by Rhon Fitzwater
if [ $DS_BACKUP_COUNT -lt 1 ] 
then
	echo -e "RuntimeAbortWorkflow: No backups for this computer exist";
	echo "educ_restore_data.sh - end";
	exit 0;
fi

# Scan computer's folder for users to restore
for i in "$DS_REPOSITORY_BACKUPS/"*USER.plist; do
	# Restore User Account - adding quote to $i for ryan_butler@epiconline.org. Better escapes directories with spaces & special chars.
	USERZ=`echo $(basename "$i")|awk -F'-' '{print $1}'`

	echo -e "<>Restoring $USERZ"
	
	if [[ "$i" =~ "NETUSER" ]]; then
		# Backup plist variable
		DS_BACKUP_PLIST="$DS_REPOSITORY_BACKUPS/$USERZ-NETUSER.plist"
		echo -e "\t >Network User:"
		# Network accounts don't have their passwords backed up, skipping.
		echo -e "\t -password skipped"
		# Check if user is Admin, Restore admin rights
		if [[ `"$DS_LAST_RESTORED_VOLUME/usr/libexec/PlistBuddy" -c "print :isAdmin" "DS_BACKUP_PLIST"` = "yes" ]]; then
			"$dscl" -f "$INTERNAL_DN" localonly -merge "/Local/Target/Groups/admin" "GroupMembership" "$USERZ"
			RUNTIME_ABORT "\t -admin rights failed restore" "\t +admin rights restored"
		fi
	else
		echo -e "\t >Local User:"
		# Perhaps All I need to do is backup the dslocal users plist?
		if [[ -e "${DS_REPOSITORY_BACKUPS}/$USERZ.plist" ]]; then
			cp -p "${DS_REPOSITORY_BACKUPS}/$USERZ.plist" "${DS_LAST_RESTORED_VOLUME}/var/db/dslocal/nodes/Default/users/$USERZ.plist"
			RUNTIME_ABORT "RuntimeAbortWorkflow: Could not create $USERZ...exiting." "\t +account created successfully"
		fi
		# Backup plist variable
		DS_BACKUP_PLIST="$DS_REPOSITORY_BACKUPS/$USERZ-USER.plist"
		# Add user to admin
		# Check if user is Admin
		if [[ `"$DS_LAST_RESTORED_VOLUME/usr/libexec/PlistBuddy" -c "print :isAdmin" "$DS_BACKUP_PLIST"` = "yes" ]]; then
			"$dscl" -f "$INTERNAL_DN" localonly -merge "/Local/Target/Groups/admin" "GroupMembers" "$GenUID"
			"$dscl" -f "$INTERNAL_DN" localonly -merge "/Local/Target/Groups/admin" "GroupMembership" "$USERZ"
			RUNTIME_ABORT "\t -admin rights failed to restore" "\t +admin rights restored"
		fi
	fi
done

# Restore user data from Backups folder on repository.
# Get backup tool
RESTORE_TOOL=`"$DS_LAST_RESTORED_VOLUME/usr/libexec/PlistBuddy" -c "print :backuptool" "$DS_REPOSITORY_BACKUPS/$USERZ.BACKUP.plist"`
echo " >Restoring $USERZ user directory with $RESTORE_TOOL"
case $RESTORE_TOOL in
	tar )
		for i in "$DS_REPOSITORY_BACKUPS"/*HOME.tar; do
			USERZ=`echo $(basename $i)|awk -F'_' '{print $1}'`
			echo " >>Restore From: $i Restore To: $DS_LAST_RESTORED_VOLUME$DS_USER_PATH/"
			# /usr/bin/tar -xf "$i" -C "$DS_LAST_RESTORED_VOLUME$DS_USER_PATH/" --strip-components=3 --keep-newer-files
			# testing moving into Users folder to make archive - suggested by Per Olofsson
			(cd "$DS_LAST_RESTORED_VOLUME$DS_USER_PATH/" && tar xpvf "$i")
			RUNTIME_ABORT "RuntimeAbortWorkflow: Could not restore home folder for $USERZ using tar...exiting." "\t +home restored successfully"
		done
		;;
	ditto )
		for i in "$DS_REPOSITORY_BACKUPS"/*cpio.gz; do
			USERZ=`echo $(basename $i)|awk -F'.' '{print $1}'`
			echo " >>Restore From: $i Restore To: $DS_LAST_RESTORED_VOLUME$DS_USER_PATH/"
			/usr/bin/ditto -x "$i" "$DS_LAST_RESTORED_VOLUME$DS_USER_PATH/"
			RUNTIME_ABORT "RuntimeAbortWorkflow: Could not restore home folder for $USERZ using ditto...exiting." "\t +home restored successfully"
		done
# 		;;
# 	rsync )
# 		for i in "$DS_REPOSITORY_BACKUPS"/*rsync; do
# 			USERZ=`echo $(basename $i)|awk -F'.' '{print $1}'`
# 			echo "Restoring $USERZ user directory with rsync"
# 			/usr/bin/rsync -av --update "$i/$USERZ" "$DS_LAST_RESTORED_VOLUME$DS_USER_PATH"
# 			RUNTIME_ABORT "RuntimeAbortWorkflow: Could not restore home folder for $USERZ using rsync...exiting." "\thome restored successfully"
# 		done
# 		;;
esac

echo "educ_restore_data.sh - end"
exit 0

## ToDo
# 
# Add Follow Symbolic Links to Tar? -L
# Check for UID's when restoring? 
#	"$DS_LAST_RESTORED_VOLUME/usr/bin/dscl" -f "$DS_LAST_RESTORED_VOLUME/var/db/dslocal/nodes/Default" localonly -change "/Local/Target/Users/student" "UniqueID" "502" "505"


## Changes
# Wednesday, January 31, 2018 - 0.7.6
# 	- Updating UNIQUE_ID to use ioreg instead of system_profiler due to its removal on High Sierra NetBoot Images.
# 
# Friday, Febuary 26, 2016 - 0.7.5
# 	- Adding CocoaDialog Support for Unique ID, requested by Steve M. Thanks Steve!
# 
# Thursday, October 22, 2015 - 0.7.4
# 	- Changing tar workflow to fix issue with restore (sub-Users Users folder)
# 	- Switch to Serial Number
# 	- Updating method to determine internal drive for Fusion Systems
# 
# Tuesday, September, 11, 2012 - v0.7.3
# 	- Updating Grep for DS_BACKUP_COUNT to support 10.8
#
# Thursday, December, 1, 2011 - v0.7.2
# 	- Adding ditto as a restore tool thanks to Miles Muri!
# 	- Modified DS_BACKUP_COUNT for ditto backups that create .zip files - by Miles Muri
# 	- Adding --keep-newer-files to tar
# 
# Wednesday, June, 22, 2011 - v0.7.1
# 	- Testing new DS_INTERNAL_DRIVE variable command
# 
# Tuesday, April, 19, 2011 - v0.7
# 	- Updated code to use new user deliminator from '.' to '-'
#
# Saturday, April, 28, 2011 - v0.6
# 	- Lots of little error fixes from midnight coding.
#
# Monday, March, 28, 2011 - v0.5
# 	- Moved the restore of Keychain into filevault users restore. Probably don't need it otherwise.
# 	- Better logging for skipping filevault keychain restores
#	- Changed way to check for user accounts - allows for accounts with '.' in them
# 
# Monday, March, 28, 2011 - v0.4.7
# 	- Moved dscl and internal directory variables outside and above for loop. 
#	- Uncommented test variables. Easier to troubleshoot the script.
# 
# Tuesday, March 22, 2011 - v0.4.6
# 	- Fix home restore to only restore *HOME.tar files
# 	- Only restore filevault keychains when they don't exist on target
# 	- Added restore for local accounts with filevault within script
# 	- Added restore for mobile accounts with filevault using first boot scripts
# 	- Removed ditto and rsync backup functions
# 
# Friday, March 18, 2011 - v0.4.5
# 	- Added better logging
# 	- Stabalized the script
# 
# Wednesday, Febuary 09, 2011 - v0.4.4
# 	- Adding to git
# 	- Added restore support for rsync
# 	- Removed unique id references from files
# 
# Tuesday, February 01, 2011
# 	- Added variables for
# 		Unique_ID
# 		Target Volume
# 		Backup repository path
# 	- Bug fixed ditto commands
# 	- Pass custom UNIQUE_ID for restoring homes to different computer
# 		To restore homes from different machine, use MAC of old machine as UNIQUE_ID
#
# Monday, January 31, 2011
# 	- Added flag to backup using ditto or tar, check help
# 
# Tuesday, January 28, 2011
# 	- Added p flag to tar to restore permissions
# 
# Tuesday, January 18, 2011
# 	- Added code to exit cleanly if there are no backups for the computer. - Contributed by Rhon Fitzwater
# 
# Monday, December 20, 2010 
# 	- Fixed issue with user account not showing in system preferences after restoring.
# 	- Added support for restoring admin rights for network users


# Written by Rusty Myers
# 
# Credit to Pete Akins and his amazingly awesome createUser.pkg script. 
# It was instrumental in learning how to backup and create users.
#
# Credit to Rhon Fitzwater for his code that skips the restoration process if 
# there is no backups to restore. Email: rfitzwater@rider.edu
#
# Thanks to bpenglase for tar command flags.
#
# Thanks to Data Scavanger for the mount command to determine internal drive.
