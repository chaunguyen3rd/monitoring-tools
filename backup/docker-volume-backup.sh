#!/bin/bash
#
# Monitoring Stack Backup Script
# - Performs full backup on Sundays
# - Performs incremental backups Monday-Saturday
# - Uploads to S3 bucket
# - Maintains 7-day retention policy
#

# Configuration
BACKUP_DIR="/opt/backup/monitoring"
DATA_DIR="~/monitoring-tools/data"                       # Location of bind-mounted volumes
S3_BUCKET="dev-cw-backup-s3"     # Replace with your S3 bucket name
S3_PREFIX="monitoring-backups"          # Path prefix in the S3 bucket
RETENTION_DAYS=30                       # Number of days to keep backups
LOG_FILE="/var/log/monitoring-backup.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DAY_OF_WEEK=$(date +"%u")               # 1-7, where 1 is Monday and 7 is Sunday

# Create backup directory if it doesn't exist
mkdir -p $BACKUP_DIR

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Function to check required tools
check_requirements() {
    command -v aws >/dev/null 2>&1 || { log "AWS CLI is required but not installed. Aborting."; exit 1; }
    command -v tar >/dev/null 2>&1 || { log "tar is required but not installed. Aborting."; exit 1; }
    command -v find >/dev/null 2>&1 || { log "find is required but not installed. Aborting."; exit 1; }
}

# Function to perform full backup
full_backup() {
    log "Starting full backup"
    
    BACKUP_FILE="monitoring_full_${TIMESTAMP}.tar.gz"
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"
    
    # Create a marker file for incremental backups to use
    LAST_FULL_MARKER="${BACKUP_DIR}/last_full_backup"
    touch $LAST_FULL_MARKER
    
    # Create list of files for incremental backup reference
    find $DATA_DIR -type f -print > "${BACKUP_DIR}/full_file_list.txt"
    
    # Optional: Check available disk space before starting
    
    # Optionally ensure consistent backup - if your services can handle a temporary restart,
    # uncomment these lines
    # log "Stopping services for consistent backup"
    # cd $(dirname $DATA_DIR) && docker-compose down
    
    # Create the backup - excludes temp files, logs that can be regenerated, etc.
    tar --exclude="*/tmp/*" --exclude="*/logs/*" --exclude="*/cache/*" \
        -czf $BACKUP_PATH $DATA_DIR
    
    BACKUP_STATUS=$?
    
    # Restart services if you stopped them
    # log "Restarting services"
    # cd $(dirname $DATA_DIR) && docker-compose up -d
    
    if [ $BACKUP_STATUS -eq 0 ]; then
        log "Full backup completed successfully: $BACKUP_FILE"
        return 0
    else
        log "Full backup failed with status $BACKUP_STATUS"
        return 1
    fi
}

# Function to perform incremental backup
incremental_backup() {
    log "Starting incremental backup"
    
    BACKUP_FILE="monitoring_incremental_${TIMESTAMP}.tar.gz"
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"
    LAST_FULL_MARKER="${BACKUP_DIR}/last_full_backup"
    
    if [ ! -f "$LAST_FULL_MARKER" ]; then
        log "No full backup marker found. Performing full backup instead."
        full_backup
        return $?
    fi
    
    # Find files modified since the last full backup
    find $DATA_DIR -type f -newer $LAST_FULL_MARKER > "${BACKUP_DIR}/incremental_file_list.txt"
    
    # Count files to be backed up
    FILE_COUNT=$(wc -l < "${BACKUP_DIR}/incremental_file_list.txt")
    
    if [ $FILE_COUNT -eq 0 ]; then
        log "No files changed since last full backup. Skipping incremental backup."
        return 0
    fi
    
    log "Backing up $FILE_COUNT changed files"
    
    # Create incremental backup with only changed files
    tar -czf $BACKUP_PATH -T "${BACKUP_DIR}/incremental_file_list.txt"
    
    BACKUP_STATUS=$?
    
    if [ $BACKUP_STATUS -eq 0 ]; then
        log "Incremental backup completed successfully: $BACKUP_FILE"
        return 0
    else
        log "Incremental backup failed with status $BACKUP_STATUS"
        return 1
    fi
}

# Function to upload backup to S3
upload_to_s3() {
    local BACKUP_FILE=$1
    local BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"
    
    if [ ! -f "$BACKUP_PATH" ]; then
        log "Backup file not found: $BACKUP_PATH"
        return 1
    fi
    
    log "Uploading $BACKUP_FILE to S3"
    
    # Upload with standard storage class
    aws s3 cp $BACKUP_PATH "s3://${S3_BUCKET}/${S3_PREFIX}/${BACKUP_FILE}" --storage-class STANDARD
    UPLOAD_STATUS=$?
    
    if [ $UPLOAD_STATUS -eq 0 ]; then
        log "Upload completed successfully"
        # Optionally remove local file after successful upload
        # rm $BACKUP_PATH
        return 0
    else
        log "Upload failed with status $UPLOAD_STATUS"
        return 1
    fi
}

# Function to clean up old local backups
# Note: S3 cleanup is handled by the already configured lifecycle policies
cleanup_old_backups() {
    # Local cleanup
    log "Cleaning up local backups older than 7 days"
    # We keep local backups only for 7 days to save space, S3 keeps them longer
    find $BACKUP_DIR -name "monitoring_*.tar.gz" -type f -mtime +7 -delete
    
    log "Note: S3 retention is handled by the MonitoringBackupsLifecycle policy"
    log "   - 0-30 days: S3 Standard"
    log "   - 31-60 days: S3 Standard-IA" 
    log "   - After 60 days: Deleted automatically"
}

# Main execution
main() {
    log "Starting backup process"
    check_requirements
    
    # Sunday (7) = Full backup, other days = Incremental
    if [ "$DAY_OF_WEEK" -eq 7 ]; then
        BACKUP_TYPE="full"
        full_backup
    else
        BACKUP_TYPE="incremental"
        incremental_backup
    fi
    
    BACKUP_STATUS=$?
    
    if [ $BACKUP_STATUS -eq 0 ]; then
        # Upload the latest backup
        if [ "$BACKUP_TYPE" = "full" ]; then
            upload_to_s3 "monitoring_full_${TIMESTAMP}.tar.gz"
        else
            upload_to_s3 "monitoring_incremental_${TIMESTAMP}.tar.gz"
        fi
        
        # Clean up old backups
        cleanup_old_backups
    fi
    
    log "Backup process completed"
}

# Execute the main function
main