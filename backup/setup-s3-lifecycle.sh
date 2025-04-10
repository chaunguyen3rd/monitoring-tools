#!/bin/bash
#
# Script to set up S3 lifecycle rules for tiered backup storage
#

# Configuration
S3_BUCKET="your-backup-bucket-name"  # Replace with your actual bucket name

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Create temporary lifecycle configuration file
cat > /tmp/lifecycle-config.json << EOL
{
    "Rules": [
        {
            "ID": "MonitoringBackupsLifecycle",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "monitoring-backups/"
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                }
            ],
            "Expiration": {
                "Days": 60
            }
        }
    ]
}
EOL

# Apply the lifecycle configuration to the S3 bucket
echo "Applying lifecycle configuration to bucket: $S3_BUCKET"
aws s3api put-bucket-lifecycle-configuration --bucket $S3_BUCKET --lifecycle-configuration file:///tmp/lifecycle-config.json

# Check if command was successful
if [ $? -eq 0 ]; then
    echo "✅ S3 lifecycle policy successfully applied!"
    echo "Your backups will now:"
    echo "  - Stay in S3 Standard for 30 days"
    echo "  - Transition to S3 Standard-IA from days 31-60"
    echo "  - Be automatically deleted after 60 days"
    echo ""
    echo "IMPORTANT: This lifecycle policy ONLY affects files with the prefix 'monitoring-backups/'"
    echo "Other files in your bucket are NOT affected by this policy."
else
    echo "❌ Failed to apply S3 lifecycle policy. Check the error message above."
fi

# Clean up
rm /tmp/lifecycle-config.json