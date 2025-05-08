#!/bin/bash
#
# Monitoring Stack Restore Script
# Downloads backup from S3 and restores Docker volumes for 
# Prometheus, Loki, Grafana, and Alertmanager
# Supports both full and incremental backups

# Configuration
DOCKER_COMPOSE_PATH="/root/monitoring-tools/docker-compose.yml"
S3_BUCKET="dev-cw-backup-s3"  # Replace with your actual S3 bucket name
S3_PREFIX="monitoring-backups"
TEMP_DIR="/tmp/monitoring-restore"
WORK_DIR="/tmp/monitoring-restore-work"
VOLUMES=("prometheus_data" "loki_data" "grafana_data" "alertmanager_data")

# Function to display usage information
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -f FILENAME    Specify backup filename in S3 (required unless using -l or -r)"
  echo "  -l             List available backups in S3 bucket"
  echo "  -r             Restore the latest full backup and all subsequent incremental backups"
  echo "  -h             Show this help message"
  echo ""
  echo "Example:"
  echo "  $0 -f full-backup-2025-05-08-120000.tar.gz"
  echo "  $0 -r          # Restore latest full backup + all incremental backups"
  echo "  $0 -l"
  exit 1
}

# Function to list available backups
list_backups() {
  echo "Listing available backups in s3://$S3_BUCKET/$S3_PREFIX/"
  echo "Full backups:"
  aws s3 ls "s3://$S3_BUCKET/$S3_PREFIX/" | grep "full-backup" | sort -r
  echo -e "\nIncremental backups:"
  aws s3 ls "s3://$S3_BUCKET/$S3_PREFIX/" | grep "incr-backup" | sort -r
  exit 0
}

# Function to restore a single backup file
restore_backup() {
  local backup_file=$1
  local restore_dir=$2
  
  echo "Processing backup: $backup_file"
  
  # Download the backup from S3 if needed
  if [ ! -f "$restore_dir/$backup_file" ]; then
    echo "Downloading backup from S3: s3://$S3_BUCKET/$S3_PREFIX/$backup_file"
    if ! aws s3 cp "s3://$S3_BUCKET/$S3_PREFIX/$backup_file" "$restore_dir/$backup_file"; then
      echo "Error: Failed to download backup from S3"
      return 1
    fi
  fi
  
  # Extract the backup
  echo "Extracting backup..."
  if ! tar -xzf "$restore_dir/$backup_file" -C "$WORK_DIR"; then
    echo "Error: Failed to extract backup"
    return 1
  fi
  
  return 0
}

# Parse command line arguments
RESTORE_LATEST=false
while getopts "f:lrh" opt; do
  case $opt in
    f)
      BACKUP_FILE="$OPTARG"
      ;;
    l)
      list_backups
      ;;
    r)
      RESTORE_LATEST=true
      ;;
    h)
      usage
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      ;;
  esac
done

# Check if backup file was specified or restore latest was requested
if [ -z "$BACKUP_FILE" ] && [ "$RESTORE_LATEST" = false ]; then
  echo "Error: Backup filename must be specified with -f option, or use -r to restore latest"
  usage
fi

# Check if docker is running
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker is not running or accessible"
  exit 1
fi

# Check if docker-compose file exists
if [ ! -f "$DOCKER_COMPOSE_PATH" ]; then
  echo "Error: Docker compose file not found at $DOCKER_COMPOSE_PATH"
  exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws > /dev/null 2>&1; then
  echo "Error: AWS CLI is not installed. Please install it first."
  exit 1
fi

# Clean up old temporary directories if they exist
rm -rf "$TEMP_DIR" "$WORK_DIR"
mkdir -p "$TEMP_DIR" "$WORK_DIR"

echo "Starting restore process..."

# If restoring latest, find the latest full backup and all subsequent incremental backups
if [ "$RESTORE_LATEST" = true ]; then
  echo "Finding latest full backup and incremental backups..."
  
  # Get the latest full backup
  LATEST_FULL=$(aws s3 ls "s3://$S3_BUCKET/$S3_PREFIX/" | grep "full-backup" | sort -r | head -1 | awk '{print $4}')
  
  if [ -z "$LATEST_FULL" ]; then
    echo "Error: No full backup found in S3 bucket"
    exit 1
  fi
  
  echo "Latest full backup: $LATEST_FULL"
  
  # Extract date from the full backup filename (format: full-backup-YYYY-MM-DD-HHMMSS.tar.gz)
  FULL_DATE=$(echo "$LATEST_FULL" | sed -n 's/full-backup-\(.*\)\.tar\.gz/\1/p')
  
  if [ -z "$FULL_DATE" ]; then
    echo "Error: Could not parse date from backup filename"
    exit 1
  fi
  
  echo "Full backup date: $FULL_DATE"
  
  # Download and extract the full backup
  if ! restore_backup "$LATEST_FULL" "$TEMP_DIR"; then
    echo "Error: Failed to restore full backup"
    exit 1
  fi
  
  # Find all incremental backups after the full backup
  INCREMENTAL_LIST=$(aws s3 ls "s3://$S3_BUCKET/$S3_PREFIX/" | grep "incr-backup" | awk '{print $4}' | sort)
  
  # Process each incremental backup that is newer than the full backup
  for INCR in $INCREMENTAL_LIST; do
    INCR_DATE=$(echo "$INCR" | sed -n 's/incr-backup-\(.*\)\.tar\.gz/\1/p')
    
    # Compare dates (simple string comparison works with our date format YYYY-MM-DD-HHMMSS)
    if [[ "$INCR_DATE" > "$FULL_DATE" ]]; then
      echo "Processing incremental backup: $INCR (date: $INCR_DATE)"
      if ! restore_backup "$INCR" "$TEMP_DIR"; then
        echo "Warning: Failed to process incremental backup $INCR"
        # Continue with the next incremental backup
      fi
    fi
  done
else
  # Single backup file specified
  if ! restore_backup "$BACKUP_FILE" "$TEMP_DIR"; then
    echo "Error: Failed to restore specified backup"
    exit 1
  fi
fi

# Stop the docker-compose stack
echo "Stopping monitoring stack services..."
docker-compose -f "$DOCKER_COMPOSE_PATH" down
if [ $? -ne 0 ]; then
  echo "Warning: Failed to stop some services, trying to continue with restore..."
fi

# Restore each volume
for VOLUME in "${VOLUMES[@]}"; do
  echo "Restoring $VOLUME..."

  # Check if the volume backup exists in the work directory
  if [ ! -f "$WORK_DIR/$VOLUME.tar.gz" ]; then
    echo "Warning: Backup for $VOLUME not found, skipping"
    continue
  fi
  
  # Create a temporary container to restore the volume
  CONTAINER_ID=$(docker run -d -v "$VOLUME:/data" --name "restore-$VOLUME" alpine:latest tail -f /dev/null)
  
  if [ $? -ne 0 ]; then
    echo "Error creating restore container for $VOLUME"
    continue
  fi

  # If doing a full restore or restoring a full backup, clear existing volume data
  if [ "$RESTORE_LATEST" = true ] || [[ "$BACKUP_FILE" == full-backup-* ]]; then
    echo "Clearing existing data in $VOLUME..."
    docker exec "$CONTAINER_ID" sh -c "rm -rf /data/*"
  fi
  
  # Copy the backup file to the container
  echo "Copying backup file to container..."
  docker cp "$WORK_DIR/$VOLUME.tar.gz" "$CONTAINER_ID:/volume-backup.tar.gz"
  
  if [ $? -ne 0 ]; then
    echo "Error copying backup for $VOLUME to container"
    docker rm -f "$CONTAINER_ID" > /dev/null 2>&1
    continue
  fi
  
  # Extract the backup in the container
  echo "Extracting backup in container..."
  docker exec "$CONTAINER_ID" tar -xzf "/volume-backup.tar.gz" -C "/data"
  
  if [ $? -ne 0 ]; then
    echo "Error extracting backup for $VOLUME"
    docker rm -f "$CONTAINER_ID" > /dev/null 2>&1
    continue
  fi
  
  # Clean up the temporary container
  docker rm -f "$CONTAINER_ID" > /dev/null 2>&1
  
  echo "Successfully restored $VOLUME"
done

# Start the docker-compose stack
echo "Starting monitoring stack services..."
docker-compose -f "$DOCKER_COMPOSE_PATH" up -d

if [ $? -ne 0 ]; then
  echo "Warning: Failed to start some services, please check the logs"
else
  echo "Services started successfully"
fi

# Clean up
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR" "$WORK_DIR"

echo "Restore process completed!"
if [ "$RESTORE_LATEST" = true ]; then
  echo "Restored latest full backup and all subsequent incremental backups"
else
  echo "Restored from: $BACKUP_FILE"
fi