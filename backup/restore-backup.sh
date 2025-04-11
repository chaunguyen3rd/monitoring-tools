#!/bin/bash
#
# Restore script for Docker volumes monitoring stack backups
#

# Configuration
BACKUP_DIR="/opt/backup/monitoring"
DOCKER_VOLUME_PREFIX="monitoring-tools"  # Docker Compose project name prefix for volumes
S3_BUCKET="dev-cw-backup-s3"
S3_PREFIX="monitoring-backups"
LOG_FILE="/var/log/monitoring-restore.log"
VOLUMES=(
    "prometheus_data"
    "grafana_data"
    "loki_data"
    "alertmanager_data"
)

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Check requirements
command -v aws >/dev/null 2>&1 || { log "AWS CLI is required but not installed. Aborting."; exit 1; }
command -v docker >/dev/null 2>&1 || { log "Docker is required but not installed. Aborting."; exit 1; }
command -v tar >/dev/null 2>&1 || { log "tar is required but not installed. Aborting."; exit 1; }

# List available backups from S3
list_backups() {
    log "Listing available backups in S3 bucket ${S3_BUCKET}..."
    
    # Check if the bucket exists and we have access
    if ! aws s3api head-bucket --bucket ${S3_BUCKET} 2>/dev/null; then
        log "Error: Cannot access bucket ${S3_BUCKET}. Please check if it exists and if you have proper permissions."
        return 1
    fi
    
    # Check if the prefix exists (it's okay if it doesn't)
    local PREFIX_EXISTS=$(aws s3api list-objects-v2 --bucket ${S3_BUCKET} --prefix "${S3_PREFIX}/" --max-items 1 --query 'Contents[0].Key' --output text 2>/dev/null)
    
    if [[ "$PREFIX_EXISTS" == "None" || -z "$PREFIX_EXISTS" ]]; then
        log "Warning: No backups found in s3://${S3_BUCKET}/${S3_PREFIX}/"
        log "The specified prefix (folder) may not exist yet or contains no backups."
        return 1
    fi
    
    # List the actual backups
    local BACKUPS=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | grep "tar.gz")
    
    if [[ -z "$BACKUPS" ]]; then
        log "No backup files found in s3://${S3_BUCKET}/${S3_PREFIX}/"
        return 1
    fi
    
    echo "$BACKUPS"
    return 0
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

# Restore a full backup to Docker volumes
restore_full_backup() {
    local BACKUP_FILE=$1
    local BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"
    
    if [ ! -f "$BACKUP_PATH" ]; then
        log "Backup file not found: $BACKUP_PATH"
        return 1
    fi
    
    # Create temporary directory for extraction
    local TMP_EXTRACT_DIR="${BACKUP_DIR}/tmp_extract_$(date +%Y%m%d%H%M%S)"
    mkdir -p "$TMP_EXTRACT_DIR"
    
    # Extract the backup archive
    log "Extracting $BACKUP_FILE..."
    tar -xzf "$BACKUP_PATH" -C "$TMP_EXTRACT_DIR"
    
    if [ $? -ne 0 ]; then
        log "Failed to extract backup"
        rm -rf "$TMP_EXTRACT_DIR"
        return 1
    fi
    
    # Stop the Docker containers
    log "Stopping Docker containers..."
    docker-compose down
    
    # Restore each volume
    for VOLUME in "${VOLUMES[@]}"; do
        log "Restoring volume: $VOLUME"
        
        # Check if volume directory exists in the backup
        if [ ! -d "${TMP_EXTRACT_DIR}/${VOLUME}" ]; then
            log "Volume $VOLUME not found in backup, skipping"
            continue
        fi
        
        # Get or create the actual volume
        ACTUAL_VOLUME=$(docker volume ls --format '{{.Name}}' | grep -E "${DOCKER_VOLUME_PREFIX}_${VOLUME}$|^${VOLUME}$" | head -n 1)
        
        if [ -z "$ACTUAL_VOLUME" ]; then
            log "Volume $VOLUME not found, creating it"
            # Try to create with project prefix first, then without if that fails
            docker volume create "${DOCKER_VOLUME_PREFIX}_${VOLUME}" || docker volume create "${VOLUME}"
            ACTUAL_VOLUME=$(docker volume ls --format '{{.Name}}' | grep -E "${DOCKER_VOLUME_PREFIX}_${VOLUME}$|^${VOLUME}$" | head -n 1)
        fi
        
        if [ -z "$ACTUAL_VOLUME" ]; then
            log "Failed to create volume $VOLUME, skipping"
            continue
        fi
        
        # Clear existing data in the volume
        log "Clearing existing data in volume $ACTUAL_VOLUME"
        docker run --rm -v "${ACTUAL_VOLUME}:/volume" alpine:latest sh -c "rm -rf /volume/*"
        
        # Restore the data
        log "Restoring data to volume $ACTUAL_VOLUME"
        docker run --rm \
            -v "${ACTUAL_VOLUME}:/volume" \
            -v "${TMP_EXTRACT_DIR}/${VOLUME}:/backup" \
            alpine:latest \
            sh -c "cd /backup && tar -cf - . | (cd /volume && tar -xf -)"
    done
    
    # Clean up
    rm -rf "$TMP_EXTRACT_DIR"
    
    # Restart the Docker containers
    log "Starting Docker containers..."
    docker-compose up -d
    
    log "Restore completed successfully"
    return 0
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
    
    # Now apply each incremental backup in sequence
    for INCREMENTAL in "${INCREMENTAL_BACKUPS[@]}"; do
        log "Applying incremental backup: $INCREMENTAL"
        local BACKUP_PATH="${BACKUP_DIR}/${INCREMENTAL}"
        
        if [ ! -f "$BACKUP_PATH" ]; then
            log "Incremental backup file not found: $BACKUP_PATH"
            continue
        fi
        
        # Create temporary directory for extraction
        local TMP_EXTRACT_DIR="${BACKUP_DIR}/tmp_extract_$(date +%Y%m%d%H%M%S)"
        mkdir -p "$TMP_EXTRACT_DIR"
        
        # Extract the incremental backup
        tar -xzf "$BACKUP_PATH" -C "$TMP_EXTRACT_DIR"
        
        if [ $? -ne 0 ]; then
            log "Failed to extract incremental backup: $INCREMENTAL"
            rm -rf "$TMP_EXTRACT_DIR"
            continue
        }
        
        # Stop containers before applying incremental backup
        log "Stopping Docker containers for incremental restore..."
        docker-compose down
        
        # Apply incremental changes to each volume
        for VOLUME in "${VOLUMES[@]}"; do
            # Skip if this volume doesn't have changes in this incremental
            if [ ! -d "${TMP_EXTRACT_DIR}/${VOLUME}" ]; then
                continue
            }
            
            log "Applying incremental changes to volume: $VOLUME"
            
            # Get the actual volume name
            ACTUAL_VOLUME=$(docker volume ls --format '{{.Name}}' | grep -E "${DOCKER_VOLUME_PREFIX}_${VOLUME}$|^${VOLUME}$" | head -n 1)
            
            if [ -z "$ACTUAL_VOLUME" ]; then
                log "Volume $VOLUME not found, skipping"
                continue
            fi
            
            # Apply incremental changes
            docker run --rm \
                -v "${ACTUAL_VOLUME}:/volume" \
                -v "${TMP_EXTRACT_DIR}/${VOLUME}:/backup" \
                alpine:latest \
                sh -c "cd /backup && tar -cf - . | (cd /volume && tar -xf -)"
        done
        
        # Clean up
        rm -rf "$TMP_EXTRACT_DIR"
        
        # Restart containers after applying incremental
        log "Restarting Docker containers..."
        docker-compose up -d
    done
    
    log "Incremental restore sequence completed successfully"
    return 0
}

# Interactive mode
interactive_restore() {
    echo "=== Monitoring Stack Docker Volume Restore ==="
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
            
            INCREMENTALS=()
            
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