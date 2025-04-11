#!/bin/bash
#
# Monitoring Stack Backup Script for Docker Volumes
# - Performs full backup on Sundays
# - Performs incremental backups Monday-Saturday
# - Uploads to S3 bucket
# - Maintains backup lifecycle according to S3 lifecycle policy
#

# Configuration
BACKUP_DIR="/opt/backup/monitoring"
DOCKER_VOLUME_PREFIX="monitoring-tools"  # Docker Compose project name prefix for volumes
S3_BUCKET="dev-cw-backup-s3"             # Replace with your S3 bucket name
S3_PREFIX="monitoring-backups"           # Path prefix in the S3 bucket
LOG_FILE="/var/log/monitoring-backup.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DAY_OF_WEEK=$(date +"%u")                # 1-7, where 1 is Monday and 7 is Sunday
VOLUMES_TO_BACKUP=(
    "prometheus_data"
    "grafana_data"
    "loki_data"
    "alertmanager_data"
)

# Create backup directory if it doesn't exist
mkdir -p $BACKUP_DIR

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Function to check required tools
check_requirements() {
    command -v aws >/dev/null 2>&1 || { log "AWS CLI is required but not installed. Aborting."; exit 1; }
    command -v docker >/dev/null 2>&1 || { log "Docker is required but not installed. Aborting."; exit 1; }
    command -v find >/dev/null 2>&1 || { log "find is required but not installed. Aborting."; exit 1; }
}

# Function to get volume mount path
get_volume_path() {
    local VOLUME_NAME=$1
    docker volume inspect --format '{{ .Mountpoint }}' ${DOCKER_VOLUME_PREFIX}_${VOLUME_NAME} 2>/dev/null || \
    docker volume inspect --format '{{ .Mountpoint }}' ${VOLUME_NAME}
}

# Function to perform full backup of Docker volumes
full_backup() {
    log "Starting full backup of Docker volumes"
    
    BACKUP_FILE="monitoring_full_${TIMESTAMP}.tar.gz"
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"
    
    # Create a marker file for incremental backups to use
    LAST_FULL_MARKER="${BACKUP_DIR}/last_full_backup"
    touch $LAST_FULL_MARKER
    
    # Create temporary directory for volume data
    TMP_BACKUP_DIR="${BACKUP_DIR}/tmp_backup_${TIMESTAMP}"
    mkdir -p $TMP_BACKUP_DIR
    
    # Backup each volume
    for VOLUME in "${VOLUMES_TO_BACKUP[@]}"; do
        log "Backing up volume: $VOLUME"
        
        # Get the actual volume name (with or without project prefix)
        ACTUAL_VOLUME=$(docker volume ls --format '{{.Name}}' | grep -E "${DOCKER_VOLUME_PREFIX}_${VOLUME}$|^${VOLUME}$" | head -n 1)
        
        if [ -z "$ACTUAL_VOLUME" ]; then
            log "Volume $VOLUME not found, skipping"
            continue
        fi
        
        # Create volume subdirectory
        mkdir -p "${TMP_BACKUP_DIR}/${VOLUME}"
        
        # Get volume data using a temporary container
        log "Creating backup of volume $ACTUAL_VOLUME"
        docker run --rm \
            -v ${ACTUAL_VOLUME}:/source \
            -v ${TMP_BACKUP_DIR}/${VOLUME}:/backup \
            alpine:latest \
            sh -c "cd /source && tar -cf - . | (cd /backup && tar -xf -)"
        
        # Create list of files for incremental backup reference
        find "${TMP_BACKUP_DIR}/${VOLUME}" -type f > "${BACKUP_DIR}/${VOLUME}_full_file_list.txt"
    done
    
    # Archive the backup directory
    log "Creating final backup archive"
    tar -czf $BACKUP_PATH -C ${TMP_BACKUP_DIR} .
    
    # Clean up
    rm -rf $TMP_BACKUP_DIR
    
    if [ -f "$BACKUP_PATH" ]; then
        log "Full backup completed successfully: $BACKUP_FILE"
        return 0
    else
        log "Full backup failed"
        return 1
    fi
}

# Function to perform incremental backup
incremental_backup() {
    log "Starting incremental backup of Docker volumes"
    
    BACKUP_FILE="monitoring_incremental_${TIMESTAMP}.tar.gz"
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"
    LAST_FULL_MARKER="${BACKUP_DIR}/last_full_backup"
    
    if [ ! -f "$LAST_FULL_MARKER" ]; then
        log "No full backup marker found. Performing full backup instead."
        full_backup
        return $?
    fi
    
    # Create temporary directory for incremental backup
    TMP_BACKUP_DIR="${BACKUP_DIR}/tmp_backup_${TIMESTAMP}"
    mkdir -p $TMP_BACKUP_DIR
    
    # Track if any files have changed across all volumes
    TOTAL_CHANGED_FILES=0
    
    # Backup each volume incrementally
    for VOLUME in "${VOLUMES_TO_BACKUP[@]}"; do
        log "Processing volume: $VOLUME"
        
        # Get the actual volume name (with or without project prefix)
        ACTUAL_VOLUME=$(docker volume ls --format '{{.Name}}' | grep -E "${DOCKER_VOLUME_PREFIX}_${VOLUME}$|^${VOLUME}$" | head -n 1)
        
        if [ -z "$ACTUAL_VOLUME" ]; then
            log "Volume $VOLUME not found, skipping"
            continue
        fi
        
        # Create volume subdirectory
        mkdir -p "${TMP_BACKUP_DIR}/${VOLUME}"
        
        # Create temporary directory to extract volume data
        TMP_EXTRACT_DIR="${BACKUP_DIR}/tmp_extract_${TIMESTAMP}_${VOLUME}"
        mkdir -p $TMP_EXTRACT_DIR
        
        # Get volume data using a temporary container
        docker run --rm \
            -v ${ACTUAL_VOLUME}:/source \
            -v ${TMP_EXTRACT_DIR}:/extract \
            alpine:latest \
            sh -c "cd /source && tar -cf - . | (cd /extract && tar -xf -)"
        
        # Find files modified since the last full backup
        if [ -f "${BACKUP_DIR}/${VOLUME}_full_file_list.txt" ]; then
            find $TMP_EXTRACT_DIR -type f -newer $LAST_FULL_MARKER > "${BACKUP_DIR}/${VOLUME}_incremental_file_list.txt"
            
            # Count files to be backed up
            FILE_COUNT=$(wc -l < "${BACKUP_DIR}/${VOLUME}_incremental_file_list.txt")
            TOTAL_CHANGED_FILES=$((TOTAL_CHANGED_FILES + FILE_COUNT))
            
            if [ $FILE_COUNT -eq 0 ]; then
                log "No files changed in volume $VOLUME since last full backup."
            else
                log "Backing up $FILE_COUNT changed files from volume $VOLUME"
                
                # Copy changed files to backup directory with preserve structure
                cat "${BACKUP_DIR}/${VOLUME}_incremental_file_list.txt" | while read FILE; do
                    REL_PATH=$(echo "$FILE" | sed "s|^${TMP_EXTRACT_DIR}||")
                    DEST_DIR=$(dirname "${TMP_BACKUP_DIR}/${VOLUME}${REL_PATH}")
                    mkdir -p "$DEST_DIR"
                    cp -p "$FILE" "${TMP_BACKUP_DIR}/${VOLUME}${REL_PATH}"
                done
            fi
        else
            log "Full file list for volume $VOLUME not found, including all files"
            # If no reference file list exists, copy all files
            cp -R "${TMP_EXTRACT_DIR}/." "${TMP_BACKUP_DIR}/${VOLUME}/"
            TOTAL_CHANGED_FILES=$((TOTAL_CHANGED_FILES + 1))  # At least one change
        fi
        
        # Clean up extract directory
        rm -rf $TMP_EXTRACT_DIR
    done
    
    if [ $TOTAL_CHANGED_FILES -eq 0 ]; then
        log "No files changed since last full backup. Skipping incremental backup creation."
        rm -rf $TMP_BACKUP_DIR
        return 0
    fi
    
    # Archive the backup directory
    log "Creating final incremental backup archive with $TOTAL_CHANGED_FILES changed files"
    tar -czf $BACKUP_PATH -C ${TMP_BACKUP_DIR} .
    
    # Clean up
    rm -rf $TMP_BACKUP_DIR
    
    if [ -f "$BACKUP_PATH" ]; then
        log "Incremental backup completed successfully: $BACKUP_FILE"
        return 0
    else
        log "Incremental backup failed"
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
    
    log "Uploading $BACKUP_FILE to S3 bucket ${S3_BUCKET}"
    
    # Check if the bucket exists and we have access
    if ! aws s3api head-bucket --bucket ${S3_BUCKET} 2>/dev/null; then
        log "Error: Cannot access bucket ${S3_BUCKET}. Please check if it exists and if you have proper permissions."
        return 1
    fi
    
    # The prefix (folder) will be automatically created when we upload the file
    # No need to create it separately
    log "Uploading to prefix (folder): ${S3_PREFIX}/"
    
    # Upload with standard storage class
    aws s3 cp $BACKUP_PATH "s3://${S3_BUCKET}/${S3_PREFIX}/${BACKUP_FILE}" --storage-class STANDARD
    UPLOAD_STATUS=$?
    
    if [ $UPLOAD_STATUS -eq 0 ]; then
        log "Upload completed successfully"
        log "Backup file available at: s3://${S3_BUCKET}/${S3_PREFIX}/${BACKUP_FILE}"
        # Optionally remove local file after successful upload
        # rm $BACKUP_PATH
        return 0
    else
        log "Upload failed with status $UPLOAD_STATUS"
        log "Please check AWS credentials and permissions"
        return 1
    fi
}

# Function to clean up old local backups
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

# Parse command line arguments
parse_args() {
    # Default to using day of week to determine backup type
    if [ -z "$1" ]; then
        # Sunday (0 in cron, 7 in date command) = Full backup, other days = Incremental
        if [ "$DAY_OF_WEEK" -eq 7 ]; then
            echo "full"
        else
            echo "incremental"
        fi
        return
    fi
    
    # Otherwise use the provided argument
    case "$1" in
        full|FULL|f)
            echo "full"
            ;;
        incremental|INCREMENTAL|inc|i)
            echo "incremental"
            ;;
        *)
            log "Unknown backup type: $1. Using day-based decision."
            if [ "$DAY_OF_WEEK" -eq 7 ]; then
                echo "full"
            else
                echo "incremental"
            fi
            ;;
    esac
}

# Main execution
main() {
    log "Starting backup process for Docker volumes"
    check_requirements
    
    # Determine backup type from command line argument or day of week
    BACKUP_TYPE=$(parse_args "$1")
    log "Performing ${BACKUP_TYPE} backup"
    
    if [ "$BACKUP_TYPE" = "full" ]; then
        full_backup
    else
        incremental_backup
    fi
    
    BACKUP_STATUS=$?
    
    if [ $BACKUP_STATUS -eq 0 ]; then
        # Upload the latest backup
        if [ "$BACKUP_TYPE" = "full" ]; then
            upload_to_s3 "monitoring_full_${TIMESTAMP}.tar.gz"
        else
            # Only upload incremental if it was created (files changed)
            if [ -f "${BACKUP_DIR}/monitoring_incremental_${TIMESTAMP}.tar.gz" ]; then
                upload_to_s3 "monitoring_incremental_${TIMESTAMP}.tar.gz"
            fi
        fi
        
        # Clean up old backups
        cleanup_old_backups
    fi
    
    log "Backup process completed"
}

# Execute the main function with all arguments passed to the script
main "$@"