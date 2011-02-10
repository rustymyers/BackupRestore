#!/bin/bash

# Beta version. Needs tested. Please report bugs.
# rustymyers@gmail.com

# Script to backup home folders on volume before restoring disk image with DeployStudio
# Uses the directories in the /Users folder of the target machine to back up data, user account details, and password.
# Use accompanying ds_restore_data.sh to pur users and user folders back onto new image after restoring image.

# Easier to read
# -e Users to Skip
# 		Must use quotes for multiple users
# 		Default is guest and shared
# 			You must specify guest and
# 			shared if your use the argument
# -v Target volume
# 		Specify full path to mount point of volume
# 		Default is the internal volume
# -u User path on target
# 		Set to path of users on volume
# 		Default is /Users
# -d Backup destination
# 		Specify full path to the backup volume
# 		Default is /tmp/DSNetworkRepository
# -t Backup tool (tar) - Still working on this one!
# 		Select backup software, Default tar
# 		tar = Use tar with gzip to backup.

function printHELP {
echo -e "Usage: `basename $0` [ -e \"guest admin shared\" ] [ -v \"/Volumes/Macintosh HD\" ] [ -u /Users ] [ -d \"/Volumes/External Drive/\" ] [ -t tar ]"
echo -e "Variables can be set in DeployStudio variables window when running script."
echo -e "BackupRestore Variables:"
echo -e "-q Unique Identifier. Should be left empty."
echo -e "-e Users to Skip - Doesn't Work."
echo -e "		Must use quotes for multiple users"
echo -e "		Default is \"guest\" and \"shared\""
echo -e "			You must specify \"guest\" and"
echo -e "			\"shared\" if your use the argument"
echo -e "-v Target volume"
echo -e "		Specify full path to mount point of volume"
echo -e "		Default is the internal volume"
echo -e "		e.g. \"\"/Volumes\/Macintosh HD\""
echo -e "-u User path on target"
echo -e "		Set to path of users on volume"
echo -e "		Default is /Users"
echo -e "-d Backup destination"
echo -e "		Specify full path to the backup volume"
echo -e "		Default is /tmp/DSNetworkRepository"
echo -e "-t Backup tool (tar) - Still working on this one!"
echo -e "		Select backup software, Default tar"
echo -e "		tar = Use tar with gzip to backup."
echo -e "		ditto and rsync not working, yet!"
echo -e "		-removed- ditto = Use ditto with gzip to backup"
echo -e "		-removed- rsync = Use rsync to backup"
}

#Variables:
# Ignore these accounts or folders in /Users (use lowercase):
# Shared folder is excluded using "shared"
export EXCLUDE=( "shared" "guest" "etcadmin" "ldf11" "alumni" )
# Unique ID for plist and common variable for scripts
export UNIQUE_ID=`echo "$DS_PRIMARY_MAC_ADDRESS"|tr -d ':'` # Add Times? UNIQUE_ID=`date "+%Y%m%d%S"`
# DS Script to backup user data with tar to Backups folder on repository.
export DS_REPOSITORY_BACKUPS="$DS_REPOSITORY_PATH/Backups/$UNIQUE_ID"
# Set Path to internal drive
export DS_INTERNAL_DRIVE=`system_profiler SPSerialATADataType | awk -F': ' '/Mount Point/ { print $2}'|head -n1`
# Set Path to the folder with home folders
export DS_USER_PATH="/Users"
# Default backup tool
export BACKUP_TOOL="tar"


# Parse command line arguments
while getopts :e:v:u:d:t:h opt; do
	case "$opt" in
		# e) EXCLUDE="$OPTARG";;
		q) UNIQUE_ID="$OPTARG";;
		v) DS_INTERNAL_DRIVE="$OPTARG";;
		u) DS_USER_PATH="$OPTARG";;
		d) DS_REPOSITORY_BACKUPS="$OPTARG/Backups/$UNIQUE_ID";;
		t) BACKUP_TOOL="$OPTARG";;
		h) 
			printHELP
			exit 0;;
		\?)
			echo "Usage: `basename $0` [-e Excluded Users] [-v Target Volume] [-u User Path] [-d Destination Volume] [ -t Backup Tool ]"
			echo "For more help, run: `basename $0` -h"
			exit 0;;
	esac
done
shift `expr $OPTIND - 1`
		
echo -e "Backup Arguements"
echo -e "Unique ID:				$UNIQUE_ID"
echo -e "Excluded users:		${EXCLUDE[@]}"
echo -e "Target Volume:			$DS_INTERNAL_DRIVE"
echo -e "User Path on target:	$DS_USER_PATH"
echo -e "Backup Destination: 	$DS_REPOSITORY_PATH"
echo -e "Backup tool:			$BACKUP_TOOL"

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

echo "educ_backup_data.sh - v0.4.4 beta ("`date`")"

# Check that the backups folder is there
if [[ ! -d "$DS_REPOSITORY_PATH/Backups" ]]; then
	mkdir -p "$DS_REPOSITORY_PATH/Backups"
fi
if [[ ! -d "$DS_REPOSITORY_PATH/Backups/$UNIQUE_ID" ]]; then
	mkdir -p "$DS_REPOSITORY_PATH/Backups/$UNIQUE_ID"
fi

# Start script...
echo "Scanning Users folder..."

# List Users on the Mac
for i in "$DS_INTERNAL_DRIVE""$DS_USER_PATH"/*/;
do
	# set account name in lowercase
    USERZ=$(basename "$i"| tr '[:upper:]' '[:lower:]');
    # set keep variable
	keep=1;
    for x in "${EXCLUDE[@]}";
    do
        [[ $x = $USERZ ]] && keep=0;

    done;
    if (( $keep )); then
		echo "Backing up $USERZ to $DS_REPOSITORY_BACKUPS"
		# Backup user account to user folder
		DS_BACKUP="$DS_INTERNAL_DRIVE$DS_USER_PATH/$USERZ"
		DS_ARCHIVE="$DS_REPOSITORY_BACKUPS/$USERZ.HOME"
		DS_BACKUP_PLIST="$DS_REPOSITORY_BACKUPS/$USERZ.BACKUP.plist"
			
		case $BACKUP_TOOL in
			tar )
			# Backup users with tar
			/usr/bin/tar -czpf "$DS_ARCHIVE.tar" "$DS_BACKUP" && echo -e "Home successfully backed up using tar" %>/dev/null || echo -e "Could not back up home"
			/usr/libexec/PlistBuddy -c "add :backuptool string tar" "$DS_BACKUP_PLIST" &>/dev/null
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
			# /usr/libexec/PlistBuddy -c "add :backuptool string ditto" "$DS_BACKUP_PLIST" &>/dev/null
			# 	;;
			# rsync )
			# #Backup using rsync
			# /usr/bin/rsync -av --update "$DS_BACKUP" "$DS_ARCHIVE.rsync/"
			# /usr/libexec/PlistBuddy -c "add :backuptool string rsync" "$DS_BACKUP_PLIST" &>/dev/null
			# 	;;
			* )
			echo "RuntimeAbortWorkflow: Backup Choice: $BACKUP_TOOL. Invalid flag, no such tool...exiting." 
			printHELP
			exit 1
				;;
		esac
		# Backup User Account
		# Set path to dscl
		export dscl="$DS_INTERNAL_DRIVE/usr/bin/dscl"
		# Internal Drive directory node
		export INTERNAL_DN="$DS_INTERNAL_DRIVE/var/db/dslocal/nodes/Default"
		UserID=`"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" uid|awk '{print $2}'`
		## Old way to check for network and mobile accounts		
		# if [[ "$UserID" -gt "1000" ]]; then
		## May be new way to do this		if [[ ! "`id -Gn`" =~ localaccounts ]]; then
		# Check dscl for "OriginalNodeName" if its a mobile account. if the account doesn't exist, its a network account
		if [[ `"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" dsAttrTypeStandard:OriginalNodeName|grep -E "^OriginalNodeName:"` || ! `"$dscl" -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" dsAttrTypeStandard:OriginalNodeName` ]]; then
			# User data backup plist
			DS_USER_BACKUP_PLIST="$DS_REPOSITORY_BACKUPS/$USERZ.NETUSER.plist"
			echo -e "\taccount excluded: network account"
			echo -e "\tpassword excluded: network account"
			# Check if user is Admin
			if [[ -z `"$dscl" -plist -f "$INTERNAL_DN" localonly -read "/Local/Target/Groups/admin" "GroupMembership"|grep -w "$USERZ"` ]]; then
				/usr/libexec/PlistBuddy -c "add :isAdmin string no" "$DS_USER_BACKUP_PLIST" 2>/dev/null
			else
				/usr/libexec/PlistBuddy -c "add :isAdmin string yes" "$DS_USER_BACKUP_PLIST" 2>/dev/null
			fi
		else
			# User data backup plist
			DS_USER_BACKUP_PLIST="$DS_REPOSITORY_BACKUPS/$USERZ.USER.plist"
			# Test for existance of user
			"$dscl" -plist -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" 1>/dev/null || echo "ERROR: User record does not exist"
			# Output all User Details to plist
			"$dscl" -plist -f "$INTERNAL_DN" localonly -read "/Local/Target/Users/$USERZ" gid home picture realname shell uid generateduid RecordName HomeDirectory > "$DS_USER_BACKUP_PLIST" 2>&1 && echo -e "\taccount backed up successfully"
			# Backup password hash
			GenUID=`/usr/libexec/PlistBuddy -c "print dsAttrTypeNative\:generateduid:0" "$DS_USER_BACKUP_PLIST"`
			if [[ -e "$DS_INTERNAL_DRIVE/var/db/shadow/hash/$GenUID" ]]; then
				/bin/cp "$DS_INTERNAL_DRIVE/var/db/shadow/hash/$GenUID" "$DS_REPOSITORY_BACKUPS/$USERZ.$GenUID"  && echo -e "\tpassword backed up successfully"
			else
				echo "No password for $USERZ"
			fi
			# Check if user is Admin
			if [[ -z `"$dscl" -plist -f "$INTERNAL_DN" localonly -read "/Local/Target/Groups/admin" "GroupMembership"|grep -w "$USERZ"` ]]; then
				/usr/libexec/PlistBuddy -c "add :isAdmin string no" "$DS_USER_BACKUP_PLIST"
			else
				/usr/libexec/PlistBuddy -c "add :isAdmin string yes" "$DS_USER_BACKUP_PLIST"
			fi
		fi
	else 
		echo -e "Excluding $USERZ" 
	fi 
done

echo "educ_backup_data.sh - end"
exit 0

#############################################################################################

## To Do
# Backup Filevault homes
# 	Filevault accounts have GeneratedUID
# 	dscl . read /Users/file HomeDirectory | awk '{print $2}'
# 	Backup sparseimage
# 	/Users/file/file.sparsebundle
# 	Recreate user - Wonder if its necessary to restore the accounts?
# 	/System/Library/CoreServices/ManagedClient.app/Contents/Resources/createmobileaccount -n usershortname
# 	Restore sparesimage
# Test USB Ethernet dongle for one machine

## Changes
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

# Written by Rusty Myers
# 
# Credit to Pete Akins and his amazingly awesome createUser.pkg script. 
# It was instrumental in learning how to backup and create users.

