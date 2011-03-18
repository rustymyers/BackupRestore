#!/bin/bash

# Beta version. Needs tested. Please report bugs.
# rustymyers@gmail.com

# Script to restore user accounts and user directories from the ds_backup_data.sh
# Uses the files backed up to MAC address of the machine,
# stored in the DeployStudio repository Backups folder

function help {
	
    cat<<EOF

	Usage: `basename $0` [ -e \"guest admin shared\" ] [ -v \"/Volumes/Macintosh HD\" ] [ -u /Users ] [ -d \"/Volumes/External Drive/\" ] [ -t tar ]
	Variables can be set in DeployStudio variables window when running script.
	BackupRestore Variables:"
	-q Unique Identifier."
			Enter the MAC address of the backup you want to restore."
			For example, if you backup a computer and its MAC address"
			was: 000000000001. You can then specify that MAC as the"
			variable to restore to a different computer. Make sure"
			you specify the target volume if your not restoring an image."
	-v Target volume"
			Specify full path to mount point of volume"
			Default is the \$DS_LAST_RESTORED_VOLUME volume"
			e.g. \"/Volumes/Macintosh HD\""
	-u User path on target"
			Set to path of users on volume"
			Default is /Users"
	-r Backup Repository Path"
			Set to path of the backup volume"
			Default is the DS Repository"
			e.g. \"/Volumes/NFSDrive/Backups\""

EOF

}

# Set Path to internal drive
export DS_INTERNAL_DRIVE=`system_profiler SPSerialATADataType | awk -F': ' '/Mount Point/ { print $2}'|head -n1`
## Non-Reimage variable. If you want to restore the user without restoring an image,
# set the destination to the volume you wish to target
# Default is set to the Last Restored Volume variable from DS
# You will need to set the target volume if your not restoring an image.
export DS_LAST_RESTORED_VOLUME="/Volumes/$DS_LAST_RESTORED_VOLUME"
# Unique ID for plist and common variable for scripts
export UNIQUE_ID=`echo "$DS_PRIMARY_MAC_ADDRESS"|tr -d ':'` # Add Times? UNIQUE_ID=`date "+%Y%m%d%S"`
# DS Script to backup user data with tar to Backups folder on repository.
export DS_REPOSITORY_BACKUPS="$DS_REPOSITORY_PATH/Backups/$UNIQUE_ID"
# Set backup count to number of tar files in backup repository - Contributed by Rhon Fitzwater
export DS_BACKUP_COUNT=`/bin/ls -l "$DS_REPOSITORY_BACKUPS" | grep -E '*.tar|*.cpio.gz' | wc -l`
# Set Path to the folder with home folders
export DS_USER_PATH="/Users"


while getopts :v:q:r:u:h opt; do
	case "$opt" in
		# e) EXCLUDE="$OPTARG";;
		v) DS_LAST_RESTORED_VOLUME="$OPTARG";;
		q) UNIQUE_ID="$OPTARG";;
		r) DS_REPOSITORY_PATH="$OPTARG/Backups/$UNIQUE_ID";;
		u) DS_USER_PATH="$OPTARG";;
		h) 
			help
			exit 0;;
		\?)
			echo "Usage: `basename $0` [-v Target Volume ] [-q MAC Address of target machine] [-r Backup Repository ]"
			echo "For more help, run: `basename $0` -h"
			exit 0;;
	esac
done
shift `expr $OPTIND - 1`

echo -e "Restore Arguments"
echo -e "Last Restored Volume:		$DS_LAST_RESTORED_VOLUME"
echo -e "Unique ID:					$UNIQUE_ID"
echo -e "User Path on target:		$DS_USER_PATH"
echo -e "Restore Repository: 		$DS_REPOSITORY_PATH"
echo -e "Internal Drive:			$DS_INTERNAL_DRIVE"
echo -e "Backup Count:				$DS_BACKUP_COUNT"



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

echo "educ_restore_data.sh - v0.4.5 beta ("`date`")"

# Check if any backups exist for this computer.  If not, exit cleanly. - Contributed by Rhon Fitzwater
if [ $DS_BACKUP_COUNT -lt 1 ] 
then
	echo -e "No backups for this computer exist";
	echo "educ_restore_data.sh - end";
	exit 0;
fi

# Check for filevault backup
# Not used yet
if [[ -e "$DS_REPOSITORY_BACKUPS/FilevaultKeys.tar" ]]; then
	echo -e "Restoring Filevault Keychains"
	/usr/bin/tar -xf "$DS_REPOSITORY_BACKUPS/FilevaultKeys.tar" -C "$DS_LAST_RESTORED_VOLUME/" # --strip-components=3
fi

for i in "$DS_REPOSITORY_BACKUPS/"*USER.plist; do
	# Restore User Account
	USERZ=`echo $(basename $i)|awk -F'.' '{print $1}'`
	# Set path to dscl
	export dscl="$DS_LAST_RESTORED_VOLUME/usr/bin/dscl"
	# Internal Drive directory node
	export INTERNAL_DN="$DS_LAST_RESTORED_VOLUME/var/db/dslocal/nodes/Default"
	
	echo -e "Restoring $USERZ"
	
	if [[ "$i" =~ "NETUSER" ]]; then
		## Add user to admin
		# Check if user is Admin
		echo -e "\tNetwork User:"
		echo -e "\taccount skipped"
		echo -e "\tpassword skipped"
		if [[ `"$DS_INTERNAL_DRIVE/usr/libexec/PlistBuddy" -c "print :isAdmin" "$DS_REPOSITORY_BACKUPS/$USERZ.NETUSER.plist"` = "yes" ]]; then
			"$dscl" -f "$INTERNAL_DN" localonly -merge "/Local/Target/Groups/admin" "GroupMembership" "$USERZ"
			echo -e "	admin rights restored"
		fi
		
	else
		echo -e "\tLocal User:"
		DS_BACKUP_PLIST="$DS_REPOSITORY_BACKUPS/$USERZ.USER.plist"
		# Get all the users info
		GenUID=`"$DS_INTERNAL_DRIVE/usr/libexec/PlistBuddy" -c "print :dsAttrTypeNative\:generateduid:0" "$DS_BACKUP_PLIST"`
		HomeFolder=`"$DS_INTERNAL_DRIVE/usr/libexec/PlistBuddy" -c "print :dsAttrTypeNative\:home:0" "$DS_BACKUP_PLIST"`
		PicturePath=`"$DS_INTERNAL_DRIVE/usr/libexec/PlistBuddy" -c "print :dsAttrTypeNative\:picture:0" "$DS_BACKUP_PLIST"`
		ShellPath=`"$DS_INTERNAL_DRIVE/usr/libexec/PlistBuddy" -c "print :dsAttrTypeNative\:shell:0" "$DS_BACKUP_PLIST"`
		UserUID=`"$DS_INTERNAL_DRIVE/usr/libexec/PlistBuddy" -c "print :dsAttrTypeNative\:uid:0" "$DS_BACKUP_PLIST"`
		RName=`"$DS_INTERNAL_DRIVE/usr/libexec/PlistBuddy" -c "print :dsAttrTypeNative\:realname:0" "$DS_BACKUP_PLIST"`
		GroupID=`"$DS_INTERNAL_DRIVE/usr/libexec/PlistBuddy" -c "print :dsAttrTypeNative\:gid:0" "$DS_BACKUP_PLIST"`
	
		# Write User Details to imaged computer
		"$dscl" -f "$INTERNAL_DN" localonly -create "/Local/Target/Users/$USERZ"
		if [ "${?}" -ne 0 ]; then
			echo "RuntimeAbortWorkflow: Could not create $USERZ...exiting."
		else
			echo -e "\taccount created successfully"
		fi
		# Write remaining details	 	
		"$dscl" -f "$INTERNAL_DN" localonly -create "/Local/Target/Users/$USERZ" realname "${RName}"
		"$dscl" -f "$INTERNAL_DN" localonly -create "/Local/Target/Users/$USERZ" gid "${GroupID}"
		"$dscl" -f "$INTERNAL_DN" localonly -create "/Local/Target/Users/$USERZ" UniqueID "${UserUID}"
		"$dscl" -f "$INTERNAL_DN" localonly -create "/Local/Target/Users/$USERZ" home "${HomeFolder}"
		"$dscl" -f "$INTERNAL_DN" localonly -create "/Local/Target/Users/$USERZ" authentication_authority ";ShadowHash;"
		"$dscl" -f "$INTERNAL_DN" localonly -create "/Local/Target/Users/$USERZ" picture "${PicturePath}"
	 	"$dscl" -f "$INTERNAL_DN" localonly -create "/Local/Target/Users/$USERZ" passwd "*"
		"$dscl" -f "$INTERNAL_DN" localonly -create "/Local/Target/Users/$USERZ" shell "${ShellPath}"
		"$dscl" -f "$INTERNAL_DN" localonly -create "/Local/Target/Users/$USERZ" generateduid  "${GenUID}"

		# Restore password hash
		if [[ -e "$DS_REPOSITORY_BACKUPS/$USERZ.$GenUID" ]]; then
			if [[ ! -d "$DS_LAST_RESTORED_VOLUME/var/db/shadow/hash/" ]]; then
				/bin/mkdir -p "$DS_LAST_RESTORED_VOLUME/var/db/shadow/hash/" || echo "Could not create /var/db/shadow/hash directory"
				/usr/sbin/chown -R 0:0 "$DS_LAST_RESTORED_VOLUME/var/db/shadow"
				/bin/chmod 700 "$DS_LAST_RESTORED_VOLUME/var/db/shadow"
			fi
			/bin/cp "$DS_REPOSITORY_BACKUPS/$USERZ.$GenUID" "$DS_LAST_RESTORED_VOLUME/var/db/shadow/hash/$GenUID" && echo -e "\tpassword restored successfully"
			/bin/chmod 600 "$DS_LAST_RESTORED_VOLUME/var/db/shadow/hash/$GenUID"
		fi
			
		# Add user to admin
		# Check if user is Admin
		if [[ `"$DS_INTERNAL_DRIVE/usr/libexec/PlistBuddy" -c "print :isAdmin" "$DS_BACKUP_PLIST"` = "yes" ]]; then
			"$dscl" -f "$INTERNAL_DN" localonly -merge "/Local/Target/Groups/admin" "GroupMembership" "$USERZ"
			"$dscl" -f "$INTERNAL_DN" localonly -merge "/Local/Target/Groups/admin" "GroupMembers" "$GenUID"
			echo -e "\tadmin rights restored"
		fi
	fi
done

# Restore user data from Backups folder on repository.
# Alternate method:
# for i in "$DS_REPOSITORY_BACKUPS/"*HOME*; do
# Get backup tool

RESTORE_TOOL=`"$DS_INTERNAL_DRIVE/usr/libexec/PlistBuddy" -c "print :backuptool" "$DS_REPOSITORY_BACKUPS/$USERZ.BACKUP.plist"`

case $RESTORE_TOOL in
	tar )
		for i in "$DS_REPOSITORY_BACKUPS"/*.tar; do
			USERZ=`echo $(basename $i)|awk -F'.' '{print $1}'`
			echo "Restoring $USERZ user directory with tar"
			echo "Restore From: $i" "Restore To: $DS_LAST_RESTORED_VOLUME/Users/"
			/usr/bin/tar -xf "$i" -C "$DS_LAST_RESTORED_VOLUME$DS_USER_PATH/" --strip-components=3
			RUNTIME_ABORT "RuntimeAbortWorkflow: Could not restore home folder for $USERZ using tar...exiting." "\thome restored successfully"
		done
		;;
	ditto )
		for i in "$DS_REPOSITORY_BACKUPS"/*cpio.gz; do
			USERZ=`echo $(basename $i)|awk -F'.' '{print $1}'`
			echo "Restoring $USERZ user directory with ditto"
			/usr/bin/ditto -x "$i" "$DS_LAST_RESTORED_VOLUME$DS_USER_PATH/"
			RUNTIME_ABORT "RuntimeAbortWorkflow: Could not restore home folder for $USERZ using ditto...exiting." "\thome restored successfully"
		done
		;;
	rsync )
		for i in "$DS_REPOSITORY_BACKUPS"/*rsync; do
			USERZ=`echo $(basename $i)|awk -F'.' '{print $1}'`
			echo "Restoring $USERZ user directory with rsync"
			/usr/bin/rsync -av --update "$i/$USERZ" "$DS_LAST_RESTORED_VOLUME$DS_USER_PATH"
			RUNTIME_ABORT "RuntimeAbortWorkflow: Could not restore home folder for $USERZ using rsync...exiting." "\thome restored successfully"
		done
		;;
esac

echo "educ_restore_data.sh - end"
exit 0

## ToDo
# 
# 


## Changes
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
# Thanks to bpenglase for tar command flags