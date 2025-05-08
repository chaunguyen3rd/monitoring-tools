# Monitoring Tools Backup System

This folder contains scripts for backing up and restoring the Docker volumes used by the monitoring stack.

## Overview

The backup system provides:

- Full backups (all data)
- Incremental backups (only changes since last full backup)
- Automatic scheduled backups
- S3 cloud storage for backup archives
- Restore capabilities for both full and incremental backups

## Backup Schedule

- **Full backups**: Every Sunday at 23:00 UTC
- **Incremental backups**: Monday through Saturday at 23:00 UTC

## Files

- `backup.sh`: Script to create and upload backups to S3
- `restore.sh`: Script to download and restore backups from S3
- `backup-crontab.txt`: Crontab configuration for scheduled backups

## Setup

### Prerequisites

1. Docker and docker-compose must be installed
2. AWS CLI must be installed and configured with appropriate credentials
3. An S3 bucket must be created to store the backups

### Configuration

Before using the scripts, update the following in both `backup.sh` and `restore.sh`:

```bash
S3_BUCKET="your-s3-bucket-name"  # Replace with your actual S3 bucket name
```

### Setting Up Scheduled Backups

To set up the scheduled backups, import the crontab configuration:

```bash
crontab /Users/chaunguyen/Desktop/devops/monitoring-tools/backup/backup-crontab.txt
```

To verify the crontab entries were added:

```bash
crontab -l
```

## Usage

### Manual Backups

To manually run a full backup:

```bash
./backup.sh -f
```

To manually run an incremental backup:

```bash
./backup.sh
```

### Restore Operations

To list all available backups in the S3 bucket:

```bash
./restore.sh -l
```

To restore a specific backup (full or incremental):

```bash
./restore.sh -f full-backup-2025-05-08-120000.tar.gz
```

To automatically restore the latest full backup plus all subsequent incremental backups:

```bash
./restore.sh -r
```

## Backed Up Volumes

The following Docker volumes are backed up:

- `prometheus_data`
- `loki_data`
- `grafana_data`
- `alertmanager_data`

## Backup File Format

- Full backups: `full-backup-YYYY-MM-DD-HHMMSS.tar.gz`
- Incremental backups: `incr-backup-YYYY-MM-DD-HHMMSS.tar.gz`

## Troubleshooting

### Backup Logs

Logs for scheduled backups can be found at:

- Full backups: `/tmp/backup-full.log`
- Incremental backups: `/tmp/backup-incremental.log`

### Common Issues

1. **AWS Permissions**: Ensure your AWS CLI has proper permissions to access the S3 bucket
2. **Docker Access**: Scripts require access to the Docker daemon
3. **Missing Volumes**: If volumes don't exist, they will be created but might be empty

## Security Considerations

- The backup script does not encrypt backups. Consider using S3 server-side encryption
- AWS credentials should have minimal required permissions
- S3 bucket policy should restrict access appropriately

## Recovery Testing

It's recommended to periodically test the restore process to ensure your backups are valid and the restore procedure works as expected.

## License

Same license as the main project
