#!/bin/bash
#
# Author Name:		Nitin Madhok
# Author Email:		nmadhok@icloud.com
# Date Created:		Wednesday, March 18, 2015
# Last Modified:	Wednesday, March 19, 2015
#


############################
## User defined variables ##
############################

SOURCE="/*"							# The source directory to backup
PATH_TO_BACKUP_DIR_PARENT=/mnt/backup          			# Path to backup directory on mount
PATH_TO_BACKUP_LOGDIR_PARENT=/var/log/backup			# Path to backup log directory
WEEKLY_BACKUP_DAY=6						# Enter (1-7); where 1=Monday, 2=Tuesday, ..., 7=Sunday
DAYS_TO_KEEP_BACKUP=14						# No. of days to retain the backup for
REMOVE_OLD_BACKUP_AND_LOGS=1					# Boolean flag for removing old backups and logs files. Set this to 1 to enable this functionality


##############################
## Auto populated variables ##
##############################

DATE_TODAY=`date -I`						# Today's date in ISO-8601 format
DATE_YESTERDAY=`date -I -d "1 day ago"`				# Yesterday's date in ISO-8601 format
DATE_OF_MONTH=`date +"%d"`					# Date of the Month e.g. 27
DAY_OF_WEEK=`date +"%u"`					# Day of the week 1 is Monday


###############
## Functions ##
###############

# Check if backup directory exists. Exit if it doesn't exist
check_backup_directory_existence () {
  if [ ! -d $1 ]
  then
    echo "Backup Target Directory doesn't exist."
    echo "Exiting..."
    exit
  fi
}

# Check if backup log directory exists. Create if it doesn't exist
check_backup_logdir_existence () {
  if [ ! -d $1 ]
  then
    echo "Creating Backup Log Directory: $1"
    mkdir -p $1
fi
}

# Check if date stamped daily backup log file exists. Create file if it doesn't exist
check_backup_logfile_existence () {
  if [ ! -f $1 ]
  then
    echo "Creating Backup Log File: $1"
    touch $1
fi
}

# Set the directory path for backup and logs, set the path to log file, set the target
set_path () {
  if [ "$1" == "weekly" ]
  then
    PATH_TO_BACKUP_DIR=$PATH_TO_BACKUP_DIR_PARENT/weekly
    PATH_TO_BACKUP_LOGDIR=$PATH_TO_BACKUP_LOGDIR_PARENT/weekly
  else
    PATH_TO_BACKUP_DIR=$PATH_TO_BACKUP_DIR_PARENT/daily
    PATH_TO_BACKUP_LOGDIR=$PATH_TO_BACKUP_LOGDIR_PARENT/daily
  fi
  TARGET=$PATH_TO_BACKUP_DIR/$DATE_TODAY
  PATH_TO_BACKUP_LOGFILE=$PATH_TO_BACKUP_LOGDIR/$DATE_TODAY.log
  SCHEDULE="$(basename $PATH_TO_BACKUP_DIR)"
}

# Check if backup directory exists. Exit if it doesn't exist
# Check if dail/weekly backup log directory exists. Create directory if it doesn't exist
# Check if date stamped daily/weekly backup log file exists. Create file if it doesn't exist
pre_command_check () {
  check_backup_directory_existence $1
  check_backup_logdir_existence $2
  check_backup_logfile_existence $3
}

# Create symlink to the latest daily and weekly backup 
create_latest_symlink () {
  if [ -L $PATH_TO_BACKUP_DIR/latest ]
  then
    # Symbolic link exists. Need to remove it
    echo "Symlink $PATH_TO_BACKUP_DIR/latest exists. Deleting it."
    rm -rf $PATH_TO_BACKUP_DIR/latest
  fi
  # Create a new symbolic link pointing to the backup just created
  ln -s $1 $PATH_TO_BACKUP_DIR/latest
  echo "Creating symlink $PATH_TO_BACKUP_DIR/latest to $1"
}

# Remove all old backups and logs which are older than $DAYS_TO_KEEP_BACKUP days
remove_old_backups_and_logs () {
  output=$(find $PATH_TO_BACKUP_DIR -maxdepth 1 -mtime +$DAYS_TO_KEEP_BACKUP -type d -exec echo '{}' \;)
  if [ "$output" ]; then
    echo -e "\nDeleting following backups older than $DAYS_TO_KEEP_BACKUP days:"
    echo $output
    find $PATH_TO_BACKUP_DIR -maxdepth 1 -mtime +$DAYS_TO_KEEP_BACKUP -type d -exec rm -rf '{}' +
  fi
  output=$(find $PATH_TO_BACKUP_LOGDIR -maxdepth 1 -mtime +$DAYS_TO_KEEP_BACKUP -type f -exec echo '{}' \;)
  if [ "$output" ]; then
    echo -e "\nDeleting following backup logs older than $DAYS_TO_KEEP_BACKUP days:"
    echo $output
    find $PATH_TO_BACKUP_LOGDIR -maxdepth 1 -mtime +$DAYS_TO_KEEP_BACKUP -type f -exec rm -f '{}' +
  fi
}

# Do pre command checks, run the rsync command, create symlink to latest
run_rsync_command () {
  pre_command_check $PATH_TO_BACKUP_DIR $PATH_TO_BACKUP_LOGDIR $PATH_TO_BACKUP_LOGFILE
  if [ $1 == "incremental" ]
  then
    backup=$(/usr/bin/rsync -avzhh --delete --log-file=$PATH_TO_BACKUP_LOGFILE --append --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} --link-dest=$LINK_DEST $SOURCE $TARGET)
  else
    backup=$(/usr/bin/rsync -avzhh --delete --log-file=$PATH_TO_BACKUP_LOGFILE --append --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} $SOURCE $TARGET)
  fi
  create_latest_symlink $TARGET
  echo -e "\n" >> $PATH_TO_BACKUP_LOGFILE

  if [ $REMOVE_OLD_BACKUP_AND_LOGS  -eq 1 ]
  then
    # Remove old weekly backups and log files
    remove_old_backups_and_logs
  fi
}

# Create full weekly backup first and then a daily incremental backup for same day
create_weekly_full_then_daily_incremental () {
  # Create a weekly full system backup
  echo "Creating weekly full backup"
  set_path "weekly"
  run_rsync_command "full"
  
  # Create a daily incremental backup
  echo -e "\nCreating daily incremental backup"
  LINK_DEST=$TARGET
  set_path "daily"
  run_rsync_command "incremental"
}


# Main Script Begins

if [ $DAY_OF_WEEK = $WEEKLY_BACKUP_DAY ]; then
  # Weekly full Backup and then do daily incremental backup for same day
  set_path "weekly"
  create_weekly_full_then_daily_incremental
else
  # Make incremental daily backup
  set_path "daily"
  LINK_DEST=$PATH_TO_BACKUP_DIR/$DATE_YESTERDAY
  if [ -d $LINK_DEST ]
  then
    # Yesterday's backup is present so do a incremental backup using it
    echo -e "\nCreating daily incremental backup from $LINK_DEST"
    run_rsync_command "incremental"
  else
    # Yesterday's backup is not present so check if today's backup is present 
    LINK_DEST=$PATH_TO_BACKUP_DIR/$DATE_TODAY
    if [ -d $LINK_DEST ]
    then
      # Today's backup is present so do a incremental backup using it
      echo -e "\nCreating daily incremental backup from $LINK_DEST"
      run_rsync_command "incremental"
    else
      # No backups are present so do a full weekly backup and then do daily incremental backup for same day
      create_weekly_full_then_daily_incremental
    fi
  fi
fi
