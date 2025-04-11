# Monitoring Stack

A complete monitoring solution for Docker containers and hosts using Prometheus, Grafana, Loki, AlertManager, and related exporters.

## Overview

This monitoring stack provides comprehensive monitoring capabilities:

- **Prometheus**: For metrics collection and storage
- **Grafana**: For visualization and dashboarding
- **Loki & Promtail**: For log aggregation
- **AlertManager**: For alert handling and notifications
- **Node Exporter**: For host-level metrics
- **cAdvisor**: For container metrics

## Project Structure

```txt
monitoring-stack/
├── docker-compose.yml                  # Main docker-compose file
├── install.sh                          # Installation script
├── .env                                # Environment variables
├── configs/                            # Configuration files
│   ├── prometheus/                     # Prometheus configs
│   ├── alertmanager/                   # AlertManager configs
│   ├── loki/                           # Loki configs
│   ├── promtail/                       # Promtail configs
│   └── grafana/                        # Grafana configs
├── dashboards/                         # Grafana dashboards
└── backup/                             # Backup solution
    ├── docker-volume-backup.sh         # Main backup script for Docker volumes
    ├── backup-cron-setup.sh            # Cron setup script
    ├── restore-backup.sh               # Backup restoration script
    ├── setup-s3-lifecycle.sh           # S3 lifecycle configuration
    └── s3-lifecycle-policy.json        # S3 lifecycle policy definition
```

## Prerequisites

- Docker and Docker Compose
- Linux host with sufficient resources
- Root access for installation
- AWS account (for backup solution)

## Quick Start

1. Clone this repository:

   ```bash
   git clone https://github.com/yourusername/monitoring-stack.git
   cd monitoring-stack
   ```

2. Make the installation script executable:

   ```bash
   chmod +x install.sh
   ```

3. Run the installation script:

   ```bash
   sudo ./install.sh
   ```

4. Access the interfaces:
   - **Grafana**: <http://localhost:3000> (default credentials: admin/admin)
   - **Prometheus**: <http://localhost:9090>
   - **AlertManager**: <http://localhost:9093>
   - **Loki**: <http://localhost:3100>

## Components & Ports

- **Prometheus** (port 9090): Time-series database for metrics
- **Node Exporter** (port 9100): Host metrics collector
- **cAdvisor** (port 8080): Container metrics collector
- **Loki** (port 3100): Log aggregation system
- **Promtail**: Log collector for Loki (no external port)
- **AlertManager** (port 9093): Alert handling and notifications
- **Grafana** (port 3000): Visualization and dashboard platform

## Configuration

All configuration files are located in the `configs/` directory:

### Prometheus

- `configs/prometheus/prometheus.yml`: Main Prometheus configuration
- `configs/prometheus/alert-rules.yml`: Alert rules

### AlertManager

- `configs/alertmanager/alertmanager.yml`: AlertManager configuration
- `configs/alertmanager/templates/email.tmpl`: Email notification template

### Loki & Promtail

- `configs/loki/loki-config.yml`: Loki configuration
- `configs/promtail/promtail-config.yml`: Promtail configuration

### Grafana

- `configs/grafana/datasources/datasources.yml`: Grafana data sources
- `configs/grafana/dashboards/dashboards.yml`: Dashboard provisioning

## Customizing Alerts

To modify alert rules, edit the Prometheus alert rules file:

```bash
nano configs/prometheus/alert-rules.yml
```

## Setting Up Alert Notifications

Configure email notifications by updating the AlertManager configuration:

```bash
nano configs/alertmanager/alertmanager.yml
```

1. Update the SMTP settings:

   ```yaml
   global:
     smtp_smarthost: "your-smtp-server:587"
     smtp_from: "alerts@example.com"
     smtp_auth_username: "your-username"
     smtp_auth_password: "your-password"
   ```

2. For Slack notifications, uncomment and update the webhook URL:

   ```yaml
   global:
     slack_api_url: 'https://hooks.slack.com/services/YOUR_WEBHOOK_URL'
   ```

After making changes, restart AlertManager:

```bash
docker-compose restart alertmanager
```

## Backup Solution for Docker Volumes

The monitoring stack now includes a comprehensive backup solution for Docker volumes that performs:

- Full backups every Sunday at 22:00 UTC
- Incremental backups Monday-Saturday at 22:00 UTC
- Uploads to Amazon S3 with intelligent storage tiering
- Automated retention management

### How Docker Volume Backup Works

This solution directly backs up the native Docker volumes rather than bind-mounted directories:

1. The system identifies the Docker volumes created by the stack
2. Creates consistent backups using temporary containers
3. **Performs full backups every Sunday at 22:00 UTC**
4. **Performs incremental backups Monday-Saturday at 22:00 UTC** (only backing up changed files)
5. Preserves all metadata and permissions
6. Provides a simple recovery interface

You can also manually trigger specific backup types:

```bash
# Run a full backup
sudo /opt/backup/scripts/docker-volume-backup.sh full

# Run an incremental backup
sudo /opt/backup/scripts/docker-volume-backup.sh incremental
```

### Storage Tiering Strategy

Backups automatically move through these storage tiers:

| Age of Backup | Storage Class | Benefits |
|---------------|---------------|----------|
| 0-30 days     | S3 Standard   | Fast retrieval, no minimum storage duration |
| 31-60 days    | S3 Standard-IA| ~54% cost savings, small retrieval fee |
| 60+ days      | Deleted       | Prevents unnecessary storage costs |

### Setting Up the Backup System

1. Create an S3 bucket in your AWS account (if not already done):
   - Go to the AWS Management Console
   - Navigate to S3
   - Click "Create bucket"
   - Name it (e.g., "dev-cw-backup-s3")
   - Configure other settings as needed
   - Click "Create bucket"

   Note: You only need to create the bucket itself. The `monitoring-backups/` prefix (folder) will be automatically created when the first backup runs.

2. Install the AWS CLI:

   ```bash
   sudo apt-get update && sudo apt-get install -y awscli
   # Or for Amazon Linux/RHEL:
   # sudo yum install -y awscli
   ```

3. Configure AWS credentials:

   ```bash
   aws configure
   ```

   Enter your AWS Access Key, Secret Key, Default region (e.g., us-east-1), and output format (json)

4. Set up the backup system:

   ```bash
   cd backup
   chmod +x *.sh
   
   # Edit scripts to set your S3 bucket name
   nano docker-volume-backup.sh
   # Change the S3_BUCKET variable to your bucket name (e.g., "dev-cw-backup-s3")
   # The default S3_PREFIX is "monitoring-backups" which will be created automatically
   
   nano setup-s3-lifecycle.sh
   # Update the S3_BUCKET variable to match your bucket name
   
   # Install the cron job and verify S3 connectivity
   sudo ./backup-cron-setup.sh
   
   # Set up S3 lifecycle rules for the bucket
   sudo ./setup-s3-lifecycle.sh
   
   # If you need to update existing lifecycle rules, use:
   # sudo ./setup-s3-lifecycle.sh --force
   ```

5. Verify the setup:

   ```bash
   # Test if the backup script works properly
   sudo /opt/backup/scripts/docker-volume-backup.sh
   
   # Check the logs
   tail -f /var/log/monitoring-backup.log
   
   # Verify the backup was uploaded to S3
   aws s3 ls s3://your-bucket-name/monitoring-backups/
   ```

### About the S3 Lifecycle Configuration

The `setup-s3-lifecycle.sh` script checks for an existing lifecycle policy:

- Detects if the MonitoringBackupsLifecycle policy is already enabled
- Shows current settings if the policy exists
- Provides an option to update the policy with the `--force` flag
- Affects only files with the specified prefix (not other content in your bucket)

The script manages a lifecycle policy that:

```json
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
```

The script only needs to be run once during initial setup or if you change your retention policy. The lifecycle rules it creates will then automatically manage all backups according to the storage tiering strategy.

You can verify the lifecycle configuration with:

```bash
aws s3api get-bucket-lifecycle-configuration --bucket your-backup-bucket-name
```

### Verifying Backups

Check your backup logs:

```bash
tail -f /var/log/monitoring-backup.log
```

List backup files in S3:

```bash
aws s3 ls s3://your-backup-bucket-name/monitoring-backups/
```

Check storage classes:

```bash
aws s3api list-objects-v2 --bucket your-backup-bucket-name \
  --prefix monitoring-backups/ \
  --query "Contents[].{Key:Key,StorageClass:StorageClass}" \
  --output table
```

### Restoring from Backup

To restore from a backup:

```bash
sudo ./restore-backup.sh
```

Follow the interactive prompts to select which backup to restore. The script will:

1. List available backups in your S3 bucket
2. Allow you to choose a full backup or full+incremental sequence
3. Download the selected backups
4. Safely restore the data to your Docker volumes
5. Restart the monitoring stack with the restored data

## Container-Specific Logs

To view logs from specific containers in Grafana:

1. Import the Container Logs Dashboard:

   ```bash
   # Place the JSON file in the dashboards directory
   cp container-logs-dashboard.json dashboards/
   ```

2. In Grafana, navigate to the Container Logs Dashboard
3. Use the container dropdown to select specific containers

## Maintenance

### Stopping the Stack

```bash
docker-compose down
```

### Updating Components

```bash
docker-compose pull
docker-compose up -d
```

### Data Persistence

All data is stored in Docker volumes:

- `prometheus_data`: Metrics history
- `grafana_data`: Dashboards, users, etc.
- `loki_data`: Log data
- `alertmanager_data`: Alert history

## Troubleshooting

If services fail to start, check logs:

```bash
# Check all logs
docker-compose logs

# Check specific service logs
docker-compose logs prometheus
docker-compose logs grafana
```

Common issues:

- Port conflicts: Make sure ports 3000, 9090, 9093, 9100, 8080, and 3100 are available
- Permissions issues: Make sure Docker has permission to manage volumes
- Resource limitations: Ensure your system has enough memory and CPU

## License

MIT License
