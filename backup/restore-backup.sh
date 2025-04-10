#!/bin/bash
#
# Restore script for monitoring stack backups
#

# Configuration
BACKUP_DIR="/opt/backup/monitoring"
DATA_DIR="~/monitoring-tools/data"  # Target directory to restore to
S3_BUCKET="dev-cw-backup-s3"
S3_PREFIX="monitoring-backups"
LOG_FILE="/var/log/monitoring-restore.log"

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Check requirements
command -v aws >/dev/null 2>&1 || { log "AWS CLI is required but not installed. Aborting."; exit 1; }
command -v tar >/dev/null 2>&1 || { log "tar is required but not installed. Aborting."; exit 1; }

# List available backups from S3
list_backups() {
    log "Listing available backups in S3..."
    aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | grep "tar.gz"
}

# Download backup from S3
download_backup() {
    local BACKUP_FILE=$1
    
    if [ -z "$BACKUP_FILE" ]; then
        log "No backup file specified"
        return 1
    fi
    
    log "Downloading $BACKUP_FILE from S3..."
    aws s3 cp "s3://${S3_BUCKET}/${S3_PREFIX}/${BACKUP_FILE}" "${BACKUP_DIR}/${BACKUP_FILE}"
    
    if [ $? -eq 0 ]; then
        log "Download completed successfully"
        return 0
    else
        log "Download failed"
        return 1
    fi
}

# Restore a full backup
restore_full_backup() {
    local BACKUP_FILE=$1
    local BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"
    
    if [ ! -f "$BACKUP_PATH" ]; then
        log "Backup file not found: $BACKUP_PATH"
        return 1
    fi
    
    # Stop the Docker containers
    log "Stopping Docker containers..."
    cd $(dirname $DATA_DIR) && docker-compose down
    
    # Backup existing data (just in case)
    if [ -d "$DATA_DIR" ]; then
        log "Backing up existing data..."
        mv "$DATA_DIR" "${DATA_DIR}_old_$(date +%Y%m%d%H%M%S)"
        mkdir -p "$DATA_DIR"
    fi
    
    # Extract the backup
    log "Extracting $BACKUP_FILE..."
    tar -xzf "$BACKUP_PATH" -C $(dirname $DATA_DIR) --strip-components=1
    
    if [ $? -eq 0 ]; then
        log "Restore completed successfully"
        
        # Restart the Docker containers
        log "Starting Docker containers..."
        cd $(dirname $DATA_DIR) && docker-compose up -d
        
        return 0
    else
        log "Restore failed"
        return 1
    fi
}

# Restore an incremental backup - requires the full backup and all incrementals in sequence
restore_incremental_sequence() {
    local FULL_BACKUP=$1
    shift
    local INCREMENTAL_BACKUPS=("$@")
    
    # First restore the full backup
    restore_full_backup "$FULL_BACKUP"
    
    if [ $? -ne 0 ]; then
        log "Full backup restore failed. Cannot proceed with incrementals."
        return 1
    fi
    
    # Then apply each incremental in sequence
    for INCREMENTAL in "${INCREMENTAL_BACKUPS[@]}"; do
        log "Applying incremental backup: $INCREMENTAL"
        local BACKUP_PATH="${BACKUP_DIR}/${INCREMENTAL}"
        
        if [ ! -f "$BACKUP_PATH" ]; then
            log "Incremental backup file not found: $BACKUP_PATH"
            continue
        fi
        
        # Extract the incremental backup
        tar -xzf "$BACKUP_PATH" -C $(dirname $DATA_DIR) --strip-components=1
        
        if [ $? -ne 0 ]; then
            log "Failed to apply incremental backup: $INCREMENTAL"
        fi
    done
    
    # Restart the Docker containers
    log "Starting Docker containers..."
    cd $(dirname $DATA_DIR) && docker-compose up -d
    
    return 0
}

# Interactive mode
interactive_restore() {
    echo "=== Monitoring Stack Backup Restore ==="
    echo ""
    
    # List available backups
    echo "Available backups:"
    list_backups
    echo ""
    
    # Choose restore type
    echo "Select restore type:"
    echo "1) Restore latest full backup"
    echo "2) Restore specific full backup"
    echo "3) Restore full backup with incrementals"
    echo "4) Exit"
    read -p "Choice: " choice
    
    case $choice in
        1)
            # Find latest full backup
            LATEST_FULL=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | grep "full" | sort -r | head -n 1 | awk '{print $4}')
            if [ -z "$LATEST_FULL" ]; then
                log "No full backup found"
                return 1
            fi
            
            log "Latest full backup: $LATEST_FULL"
            download_backup "$LATEST_FULL"
            restore_full_backup "$LATEST_FULL"
            ;;
        2)
            # Choose specific full backup
            echo "Available full backups:"
            aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | grep "full" | awk '{print NR ") " $4}'
            read -p "Enter number: " num
            
            SELECTED_BACKUP=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | grep "full" | awk 'NR=='$num'{print $4}')
            if [ -z "$SELECTED_BACKUP" ]; then
                log "Invalid selection"
                return 1
            fi
            
            download_backup "$SELECTED_BACKUP"
            restore_full_backup "$SELECTED_BACKUP"
            ;;
        3)
            # Choose full backup and incrementals
            echo "Available full backups:"
            aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | grep "full" | awk '{print NR ") " $4}'
            read -p "Enter number for full backup: " num
            
            FULL_BACKUP=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | grep "full" | awk 'NR=='$num'{print $4}')
            if [ -z "$FULL_BACKUP" ]; then
                log "Invalid selection"
                return 1
            fi
            
            # Extract date from full backup filename
            FULL_DATE=$(echo $FULL_BACKUP | grep -o "[0-9]\{8\}")
            
            echo "Available incremental backups after $FULL_DATE:"
            aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | grep "incremental" | grep -A 100 "$FULL_DATE" | awk '{print NR ") " $4}'
            
            read -p "Enter numbers for incrementals (comma-separated, or 'all'): " inc_choice
            
            if [ "$inc_choice" == "all" ]; then
                INCREMENTALS=($(aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | grep "incremental" | grep -A 100 "$FULL_DATE" | awk '{print $4}'))
            else
                IFS=',' read -ra NUMS <<< "$inc_choice"
                for i in "${NUMS[@]}"; do
                    INC=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | grep "incremental" | grep -A 100 "$FULL_DATE" | awk 'NR=='$i'{print $4}')
                    INCREMENTALS+=("$INC")
                done
            fi
            
            # Download all selected backups
            download_backup "$FULL_BACKUP"
            for inc in "${INCREMENTALS[@]}"; do
                download_backup "$inc"
            done
            
            # Perform the restore
            restore_incremental_sequence "$FULL_BACKUP" "${INCREMENTALS[@]}"
            ;;
        4)
            log "Exiting"
            return 0
            ;;
        *)
            log "Invalid choice"
            return 1
            ;;
    esac
}

# Main entry point - run in interactive mode
interactive_restore