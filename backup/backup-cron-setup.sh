#!/bin/bash
#
# Script to set up the backup cron job
#

# Configuration
BACKUP_SCRIPT="/opt/backup/scripts/docker-volume-backup.sh"
LOG_FILE="/var/log/monitoring-backup.log"
S3_BUCKET="dev-cw-backup-s3"  # The bucket you've already created

# Create necessary directories
mkdir -p /opt/backup/scripts
mkdir -p /opt/backup/monitoring
touch $LOG_FILE
chmod 644 $LOG_FILE

# Copy the backup script
cp docker-volume-backup.sh $BACKUP_SCRIPT
chmod +x $BACKUP_SCRIPT

# Create cron jobs for backups at 22:00 UTC
# Full backup on Sunday (day 0), incremental backups Monday-Saturday (days 1-6)
CRON_FULL="0 22 * * 0 $BACKUP_SCRIPT full >> $LOG_FILE 2>&1 # Full backup on Sunday"
CRON_INCREMENTAL="0 22 * * 1-6 $BACKUP_SCRIPT incremental >> $LOG_FILE 2>&1 # Incremental backup Mon-Sat"

# Check if the cron jobs already exist
EXISTING_CRON=$(crontab -l 2>/dev/null | grep -F "$BACKUP_SCRIPT")

if [ -z "$EXISTING_CRON" ]; then
    # Add the new cron jobs
    (crontab -l 2>/dev/null; echo "$CRON_FULL"; echo "$CRON_INCREMENTAL") | crontab -
    echo "Cron jobs installed:"
    echo "  - Full backup: Every Sunday at 22:00 UTC"
    echo "  - Incremental backup: Monday through Saturday at 22:00 UTC"
else
    # Remove old cron entries and add new ones
    (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT"; echo "$CRON_FULL"; echo "$CRON_INCREMENTAL") | crontab -
    echo "Cron jobs updated:"
    echo "  - Full backup: Every Sunday at 22:00 UTC"
    echo "  - Incremental backup: Monday through Saturday at 22:00 UTC"
fi

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI..."
    apt-get update && apt-get install -y awscli
    # Alternative for Amazon Linux or if apt doesn't work:
    # yum install -y awscli
fi

# Check if AWS credentials are configured
if [ ! -f ~/.aws/credentials ] && [ ! -f ~/.aws/config ]; then
    echo "AWS credentials not found. Setting up now..."
    echo "Please provide your AWS credentials:"
    
    # Ask for AWS credentials
    read -p "AWS Access Key ID: " AWS_ACCESS_KEY
    read -p "AWS Secret Access Key: " AWS_SECRET_KEY
    read -p "Default region (e.g., us-east-1): " AWS_REGION
    
    # Create credentials file
    mkdir -p ~/.aws
    cat > ~/.aws/credentials << EOL
[default]
aws_access_key_id = $AWS_ACCESS_KEY
aws_secret_access_key = $AWS_SECRET_KEY
EOL
    
    cat > ~/.aws/config << EOL
[default]
region = $AWS_REGION
output = json
EOL
    
    echo "AWS credentials configured."
fi

# Check if we can access the S3 bucket
if ! aws s3api head-bucket --bucket $S3_BUCKET 2>/dev/null; then
    echo "WARNING: Cannot access S3 bucket $S3_BUCKET."
    echo "Please make sure:"
    echo "  1. The bucket exists in your AWS account"
    echo "  2. Your AWS credentials have proper permissions"
    echo "  3. The bucket name is spelled correctly in docker-volume-backup.sh"
else
    echo "Successfully connected to S3 bucket: $S3_BUCKET"
    echo "The prefix (folder) 'monitoring-backups/' will be automatically created when the first backup runs."
fi

# Reminder for AWS credentials
echo "
============================================
Setup complete!

S3 bucket information:
- Bucket name: $S3_BUCKET (already created)
- Backup prefix: monitoring-backups/ (will be created automatically)

If you need to update AWS credentials in the future:
1. Run: aws configure
2. Enter your AWS Access Key, Secret Key, region (e.g., us-east-1), and output format (json)

To test the backup script manually:
$BACKUP_SCRIPT

The next scheduled backup will run at 22:00 UTC.
============================================
"