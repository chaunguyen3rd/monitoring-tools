#!/bin/bash
#
# Script to set up S3 lifecycle rules for tiered backup storage
#

# Configuration
S3_BUCKET="dev-cw-backup-s3"  # Replace with your actual bucket name
FORCE_UPDATE=false

# Process command line arguments
for arg in "$@"; do
    case $arg in
        --force)
            FORCE_UPDATE=true
            shift
            ;;
        *)
            # Unknown option
            ;;
    esac
done

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if bucket exists
if ! aws s3api head-bucket --bucket $S3_BUCKET 2>/dev/null; then
    echo "Error: Bucket $S3_BUCKET does not exist or you don't have access to it."
    echo "Please make sure:"
    echo "  1. The bucket is created in your AWS account"
    echo "  2. Your AWS credentials have proper permissions"
    echo "  3. The bucket name is spelled correctly"
    exit 1
fi

echo "Successfully connected to S3 bucket: $S3_BUCKET"
echo "Note: The prefix (folder) 'monitoring-backups/' will be automatically created when the first backup runs."

# Check if lifecycle policy already exists
if ! $FORCE_UPDATE; then
    if aws s3api get-bucket-lifecycle-configuration --bucket $S3_BUCKET &>/dev/null; then
        # Policy exists, check if our rule is already there
        EXISTING_RULE=$(aws s3api get-bucket-lifecycle-configuration --bucket $S3_BUCKET \
                         --query "Rules[?ID=='MonitoringBackupsLifecycle']" --output json)
        
        if [ "$EXISTING_RULE" != "[]" ] && [ "$EXISTING_RULE" != "" ]; then
            echo "Lifecycle policy 'MonitoringBackupsLifecycle' already exists on bucket $S3_BUCKET"
            echo "Current configuration:"
            aws s3api get-bucket-lifecycle-configuration --bucket $S3_BUCKET \
                --query "Rules[?ID=='MonitoringBackupsLifecycle']" --output json
            
            echo ""
            echo "To update the policy, run this script with the --force flag:"
            echo "  ./setup-s3-lifecycle.sh --force"
            exit 0
        fi
    fi
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

# Check if there's an existing lifecycle configuration
if aws s3api get-bucket-lifecycle-configuration --bucket $S3_BUCKET &>/dev/null; then
    echo "Existing lifecycle configuration found on bucket $S3_BUCKET"
    
    # Get existing configuration and merge with our rule
    aws s3api get-bucket-lifecycle-configuration --bucket $S3_BUCKET > /tmp/existing-lifecycle.json
    
    # Create a merged configuration using jq if available, otherwise warn user
    if command -v jq &> /dev/null; then
        # Remove our rule if it exists, then add the new one
        jq 'del(.Rules[] | select(.ID == "MonitoringBackupsLifecycle"))' /tmp/existing-lifecycle.json > /tmp/temp.json
        jq --slurpfile new /tmp/lifecycle-config.json '.Rules += $new[0].Rules' /tmp/temp.json > /tmp/merged-lifecycle.json
        
        echo "Applying merged lifecycle configuration to bucket: $S3_BUCKET"
        aws s3api put-bucket-lifecycle-configuration --bucket $S3_BUCKET --lifecycle-configuration file:///tmp/merged-lifecycle.json
    else
        echo "Warning: 'jq' command not found. Cannot safely merge lifecycle policies."
        echo "To avoid disrupting existing rules, please install jq with:"
        echo "  apt-get install jq  # (for Debian/Ubuntu)"
        echo "  yum install jq      # (for CentOS/RHEL)"
        echo ""
        echo "Applying only the monitoring backup lifecycle rule will REMOVE all other rules."
        read -p "Continue anyway? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Operation canceled. Please install jq and run again."
            exit 1
        fi
        
        # Apply just our configuration (warning: this removes any other existing rules)
        echo "Applying monitoring backup lifecycle configuration to bucket: $S3_BUCKET"
        echo "WARNING: This will replace ALL existing lifecycle rules!"
        aws s3api put-bucket-lifecycle-configuration --bucket $S3_BUCKET --lifecycle-configuration file:///tmp/lifecycle-config.json
    fi
else
    # No existing configuration, just apply ours
    echo "No existing lifecycle configuration found."
    echo "Applying lifecycle configuration to bucket: $S3_BUCKET"
    aws s3api put-bucket-lifecycle-configuration --bucket $S3_BUCKET --lifecycle-configuration file:///tmp/lifecycle-config.json
fi

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
rm -f /tmp/lifecycle-config.json /tmp/existing-lifecycle.json /tmp/temp.json /tmp/merged-lifecycle.json