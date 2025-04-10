#!/bin/bash
#
# Script to set up the backup cron job
#

# Configuration
BACKUP_SCRIPT="/opt/backup/scripts/docker-volume-backup.sh"
LOG_FILE="/var/log/monitoring-backup.log"

# Create necessary directories
mkdir -p /opt/backup/scripts
mkdir -p /opt/backup/monitoring
touch $LOG_FILE
chmod 644 $LOG_FILE

# Copy the backup script
cp docker-volume-backup.sh $BACKUP_SCRIPT
chmod +x $BACKUP_SCRIPT

# Create cron job for daily backup at 22:00 UTC
CRON_JOB="0 22 * * * $BACKUP_SCRIPT >> $LOG_FILE 2>&1"

# Check if the cron job already exists
EXISTING_CRON=$(crontab -l 2>/dev/null | grep -F "$BACKUP_SCRIPT")

if [ -z "$EXISTING_CRON" ]; then
    # Add the new cron job
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "Cron job installed: $CRON_JOB"
else
    echo "Cron job already exists"
fi

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI..."
    apt-get update && apt-get install -y awscli
    # Alternative for Amazon Linux or if apt doesn't work:
    # yum install -y awscli
fi

# Reminder for AWS credentials
echo "
============================================
Setup complete!

Remember to configure AWS credentials:
1. Run: aws configure
2. Enter your AWS Access Key, Secret Key, region (e.g., us-east-1), and output format (json)

Or create credentials file manually:
mkdir -p ~/.aws
cat > ~/.aws/credentials << EOL
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
region = YOUR_REGION
EOL

Don't forget to update the S3 bucket name in the backup script:
1. Edit $BACKUP_SCRIPT
2. Change the S3_BUCKET value to your actual bucket name
============================================
"