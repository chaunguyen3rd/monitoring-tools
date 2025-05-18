# CW Server Cluster Monitoring Stack

A complete monitoring solution for multiple hosts and Docker containers across your server infrastructure. This stack is configured specifically for the CW server cluster that includes:

- `monitor01.cw.internal` - Main monitoring server
- `dev01.cw.internal` - Development server with Docker containers
- `fe01.cw.internal` - Frontend server with Nginx

## Components

- **Prometheus**: Time-series database for metrics collection
- **Grafana**: Data visualization and dashboarding
- **Loki**: Log aggregation system
- **AlertManager**: Alert handling and notifications
- **Node Exporter**: Host-level metrics collection
- **cAdvisor**: Container metrics collection
- **Promtail**: Log collection agent
- **AlertManager Discord**: Discord notification integration

## Quick Start

### Setting Up the Main Monitoring Server

1. Clone this repository:

   ```bash
   git clone https://github.com/yourusername/cw-monitoring.git
   cd cw-monitoring
   ```

2. Edit the `.env` file to configure your environment:

   ```bash
   nano .env
   ```

   Update the following variables:
   - Host names (MONITOR_HOST, DEV_HOST, FRONTEND_HOST)
   - Grafana credentials
   - Discord webhook URL for alerts
   - Other configuration parameters as needed

3. Start the monitoring stack:

   ```bash
   docker-compose up -d
   ```

### Setting Up Remote Hosts

After installing the main monitoring server, you need to set up monitoring agents on your remote hosts:

1. Copy the remote setup files to each remote host:

   ```bash
   scp -r remote/docker-compose.yml user@dev01.cw.internal:~/monitoring/
   scp -r remote/promtail-config.yml user@dev01.cw.internal:~/monitoring/
   ```

   For the frontend server with Nginx:

   ```bash
   scp -r remote/docker-compose.yml user@fe01.cw.internal:~/monitoring/
   scp -r remote/promtail-config.yml user@fe01.cw.internal:~/monitoring/
   ```

2. Create a simple `.env` file on each remote host:

   For development server:

   ```bash
   cat > ~/monitoring/.env << EOL
   MONITOR_HOST=monitor01.cw.internal
   DEV_HOST=dev01.cw.internal
   DNS_SERVER=10.0.0.2
   EOL
   ```

   For frontend server:

   ```bash
   cat > ~/monitoring/.env << EOL
   MONITOR_HOST=monitor01.cw.internal
   FRONTEND_HOST=fe01.cw.internal
   DNS_SERVER=10.0.0.2
   EOL
   ```

3. SSH into each remote host and start the monitoring agents:

   ```bash
   ssh user@dev01.cw.internal
   cd ~/monitoring
   docker-compose up -d
   ```

   Repeat for all remote hosts.

## Accessing the Interfaces

After installation, you can access the following web interfaces:

- **Grafana**: `http://monitor01.cw.internal:3000`
  - Credentials: as configured in `.env` (default: admin/admin)
- **Prometheus**: `http://monitor01.cw.internal:9090`
- **AlertManager**: `http://monitor01.cw.internal:9093`

## Available Dashboards

The monitoring stack comes with pre-configured dashboards:

1. **CW Server Cluster Overview**
   - Complete overview of all hosts in the cluster
   - CPU, Memory, and Disk usage for all hosts
   - Container distribution across hosts
   - Recent error logs from all systems

2. **Container Monitoring**
   - Detailed container metrics by host
   - CPU, Memory, Network usage for containers
   - Container logs with filtering

3. **CW Logs Explorer**
   - Advanced log exploration and filtering
   - Search across all hosts and containers
   - Error and warning filtering
   - Special section for Nginx logs from the frontend server

4. **Nginx Monitoring**
   - HTTP status code distribution
   - Request rate monitoring
   - Top requested URLs and client IPs
   - Error tracking
   - Full Nginx access and error log viewing

## Monitoring Structure

This monitoring stack is configured specifically for your three-server setup:

### Main Monitoring Server (monitor01.cw.internal)

- Runs the core monitoring services (Prometheus, Grafana, Loki, AlertManager)
- Collects its own metrics and logs
- Receives metrics and logs from remote hosts

### Development Server (dev01.cw.internal)

- Runs Node Exporter, cAdvisor, and Promtail
- Sends host metrics, container metrics, and logs to the main server

### Frontend Server (fe01.cw.internal)

- Runs Node Exporter, cAdvisor, and Promtail
- Special configuration for monitoring Nginx logs
- Sends host metrics, container metrics, and logs to the main server

## Customizing the Stack

### Adding More Remote Hosts

1. Edit the `.env` file to define the new host name

2. Edit the Prometheus configuration (`configs/prometheus/prometheus.yml`):

   ```yaml
   # New Remote Host - Node Exporter
   - job_name: "newhost-node-exporter"
     static_configs:
       - targets: ["${NEW_HOST}:9100"]
         labels:
           host: "${NEW_HOST}"
           instance_group: "your-group-name"

   # New Remote Host - cAdvisor
   - job_name: "newhost-cadvisor"
     static_configs:
       - targets: ["${NEW_HOST}:8080"]
         labels:
           host: "${NEW_HOST}"
           instance_group: "your-group-name"
   ```

3. Restart Prometheus:

   ```bash
   docker-compose restart prometheus
   ```

4. Set up the remote host with the monitoring agents.

### Customizing Alerts

Edit the alert rules in `configs/prometheus/alert-rules.yml` to customize monitoring thresholds.

### Customizing Discord Notifications

The stack integrates with Discord for alert notifications. The integration is configured in:

1. The `.env` file (for the webhook URL)
2. The Alertmanager configuration (`configs/alertmanager/alertmanager.yml`)

You can customize alert templates in `configs/alertmanager/templates/` to change the format and content of notifications.

## Backup and Restore

The monitoring stack includes backup scripts in the `backup/` directory:

- `backup.sh`: Script to create and upload backups to S3
- `restore.sh`: Script to download and restore backups from S3

See `backup/README.md` for detailed backup configuration and usage instructions.

## Troubleshooting

### Checking Service Status

```bash
# On main monitoring server
docker-compose ps

# View logs for a specific service
docker-compose logs grafana
docker-compose logs prometheus
```

### Common Issues

1. **Remote host metrics not appearing**
   - Check network connectivity between hosts
   - Verify that the remote services are running: `docker ps`
   - Check Prometheus targets: `http://monitor01.cw.internal:9090/targets`

2. **Logs not appearing in Grafana**
   - Check Loki service: `docker-compose logs loki`
   - Verify Promtail is running on all hosts
   - Check Promtail configuration

3. **Dashboard shows "No data"**
   - Verify data source connections in Grafana
   - Check queries in the dashboard panels
   - Ensure metrics are being collected (check Prometheus targets)

4. **Environment variable not being applied**
   - Make sure the `.env` file is in the same directory as your docker-compose.yml
   - Check that you're using the correct variable names in configuration files
   - Try running with `docker-compose --env-file .env up -d` to explicitly specify the env file

5. **Nginx logs not appearing**
   - Ensure Promtail has read access to `/var/log/nginx/`
   - Check that the Nginx log format matches what's expected in the Promtail config
   - Verify that the Nginx logs job is correctly configured in Promtail
