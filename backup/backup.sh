#!/bin/bash
#
# Monitoring Stack Backup Script
# Backs up Docker volumes for Prometheus, Loki, Grafana, and Alertmanager
# Supports full and incremental backups
# Uploads backup to S3 bucket

# Configuration
DATE=$(date +%Y-%m-%d-%H%M%S)
DAY_OF_WEEK=$(date +%u)  # 1-7, where 1 is Monday and 7 is Sunday
BACKUP_DIR="/tmp/monitoring-backup-$DATE"
BACKUP_TYPE="incremental"  # Default to incremental
LAST_FULL_BACKUP_FILE="/tmp/last_full_backup.txt"
S3_BUCKET="dev-cw-backup-s3"  # Replace with your actual S3 bucket name
S3_PREFIX="monitoring-backups"
DOCKER_COMPOSE_PATH="/root/monitoring-tools/docker-compose.yml"
VOLUMES=("prometheus_data" "loki_data" "grafana_data" "alertmanager_data")

# Parse command line arguments
while getopts "ft:" opt; do
  case $opt in
    f)
      BACKUP_TYPE="full"
      ;;
    t)
      BACKUP_TYPE="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# Auto-detect backup type based on day of the week if not specified
if [ "$BACKUP_TYPE" = "incremental" ] && [ "$DAY_OF_WEEK" -eq 7 ]; then
  echo "Sunday detected - performing full backup"
  BACKUP_TYPE="full"
fi

# Set backup file name based on type
if [ "$BACKUP_TYPE" = "full" ]; then
  BACKUP_FILE="full-backup-$DATE.tar.gz"
  # Store the timestamp for incremental backups to reference
  echo "$DATE" > "$LAST_FULL_BACKUP_FILE"
else
  BACKUP_FILE="incr-backup-$DATE.tar.gz"
fi

echo "Starting $BACKUP_TYPE backup..."

# Create backup directory
mkdir -p "$BACKUP_DIR"
echo "Created backup directory: $BACKUP_DIR"

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

echo "Starting backup process for monitoring stack volumes..."

# For incremental backup, we need to know when the last full backup was
INCREMENTAL_OPTIONS=""
if [ "$BACKUP_TYPE" = "incremental" ]; then
  if [ -f "$LAST_FULL_BACKUP_FILE" ]; then
    LAST_FULL_DATE=$(cat "$LAST_FULL_BACKUP_FILE")
    echo "Last full backup was: $LAST_FULL_DATE"
    # Convert date to seconds since epoch for comparison
    LAST_FULL_SECONDS=$(date -j -f "%Y-%m-%d-%H%M%S" "$LAST_FULL_DATE" "+%s" 2>/dev/null)
    if [ $? -ne 0 ]; then
      echo "Error parsing last full backup date. Defaulting to full backup."
      BACKUP_TYPE="full"
    else
      # Use find's -newer flag with a reference file for incremental backups
      touch -t "${LAST_FULL_DATE:0:4}${LAST_FULL_DATE:5:2}${LAST_FULL_DATE:8:2}${LAST_FULL_DATE:11:2}${LAST_FULL_DATE:13:2}.${LAST_FULL_DATE:15:2}" "/tmp/reference_time"
      INCREMENTAL_OPTIONS="--newer-than=/tmp/reference_time"
    fi
  else
    echo "No record of previous full backup. Defaulting to full backup."
    BACKUP_TYPE="full"
    BACKUP_FILE="full-backup-$DATE.tar.gz"
    echo "$DATE" > "$LAST_FULL_BACKUP_FILE"
  fi
fi

# Create backup of each volume
for VOLUME in "${VOLUMES[@]}"; do
  echo "Backing up $VOLUME..."
  
  # Create a temporary container that mounts the volume and archives its contents
  CONTAINER_ID=$(docker run -d -v "$VOLUME:/data" --name "backup-$VOLUME" alpine:latest tail -f /dev/null)
  
  if [ $? -ne 0 ]; then
    echo "Error creating backup container for $VOLUME"
    continue
  fi
  
  # Archive the volume contents
  if [ "$BACKUP_TYPE" = "full" ]; then
    # Full backup - archive all files
    docker exec "$CONTAINER_ID" tar -czf "/data-backup.tar.gz" -C /data ./
  else
    # Incremental backup - only archive files newer than the last full backup
    # Copy reference file to container
    if [ -f "/tmp/reference_time" ]; then
      docker cp "/tmp/reference_time" "$CONTAINER_ID:/reference_time"
      docker exec "$CONTAINER_ID" find /data -type f -newer /reference_time -print | docker exec -i "$CONTAINER_ID" tar -czf "/data-backup.tar.gz" -T -
      if [ ! -s "/data-backup.tar.gz" ]; then
        echo "No changes detected for $VOLUME since last full backup"
      fi
    else
      # Fallback to full backup if reference time is not available
      docker exec "$CONTAINER_ID" tar -czf "/data-backup.tar.gz" -C /data ./
    fi
  fi
  
  if [ $? -ne 0 ]; then
    echo "Error creating archive for $VOLUME"
    docker rm -f "$CONTAINER_ID" > /dev/null 2>&1
    continue
  fi
  
  # Copy the archive from the container to the host
  docker cp "$CONTAINER_ID:/data-backup.tar.gz" "$BACKUP_DIR/$VOLUME.tar.gz"
  
  if [ $? -ne 0 ]; then
    echo "Error copying archive for $VOLUME to host"
  else
    echo "Successfully backed up $VOLUME"
  fi
  
  # Clean up the temporary container
  docker rm -f "$CONTAINER_ID" > /dev/null 2>&1
done

# Create a consolidated archive of all volume backups
echo "Creating consolidated backup archive..."
tar -czf "/tmp/$BACKUP_FILE" -C "$BACKUP_DIR" .

if [ $? -ne 0 ]; then
  echo "Error creating consolidated backup archive"
  exit 1
fi

# Upload the backup to S3
echo "Uploading $BACKUP_TYPE backup to S3..."
aws s3 cp "/tmp/$BACKUP_FILE" "s3://$S3_BUCKET/$S3_PREFIX/$BACKUP_FILE"

if [ $? -ne 0 ]; then
  echo "Error uploading backup to S3"
  echo "Backup file is still available at: /tmp/$BACKUP_FILE"
else
  echo "Successfully uploaded backup to S3: s3://$S3_BUCKET/$S3_PREFIX/$BACKUP_FILE"
fi

# Clean up
echo "Cleaning up temporary files..."
rm -rf "$BACKUP_DIR"
rm -f "/tmp/$BACKUP_FILE"
if [ -f "/tmp/reference_time" ]; then
  rm -f "/tmp/reference_time"
fi

echo "Backup process completed!"
echo "Backup info:"
echo "  Type: $BACKUP_TYPE"
echo "  Date: $DATE"
echo "  S3 Location: s3://$S3_BUCKET/$S3_PREFIX/$BACKUP_FILE"