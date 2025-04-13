# CW Server Cluster Monitoring Stack

A complete monitoring solution for monitoring multiple hosts and Docker containers across your server infrastructure. This stack is configured specifically for the CW server cluster that includes:

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

## Quick Start

### Setting Up the Main Monitoring Server

1. Clone this repository:

   ```bash
   git clone https://github.com/yourusername/cw-monitoring.git
   cd cw-monitoring
   ```

2. Make the installation script executable:

   ```bash
   chmod +x install.sh
   ```

3. Run the installation script:

   ```bash
   sudo ./install.sh
   ```

4. Follow the prompts to configure your monitoring stack:
   - Enter your monitoring server hostname (default: monitor01.cw.internal)
   - Enter your remote host names (defaults: dev01.cw.internal and fe01.cw.internal)
   - Configure Grafana credentials (defaults: admin/admin)

5. The monitoring stack will start on your main server.

### Setting Up Remote Hosts

After installing the main monitoring server, you need to set up monitoring agents on your remote hosts:

1. Copy the generated remote setup script to each remote host:

   ```bash
   scp remote-setup.sh user@dev01.cw.internal:~/
   scp remote-setup.sh user@fe01.cw.internal:~/
   ```

2. SSH into each remote host and run the setup script:

   ```bash
   ssh user@dev01.cw.internal
   chmod +x remote-setup.sh
   sudo ./remote-setup.sh
   ```

3. When prompted, enter your main monitoring server hostname (monitor01.cw.internal).

4. Repeat for all remote hosts.

## Accessing the Interfaces

After installation, you can access the following web interfaces:

- **Grafana**: `http://monitor01.cw.internal:3000`
  - Credentials: as configured during installation (default: admin/admin)
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

1. Edit the Prometheus configuration:

   ```bash
   nano configs/prometheus/prometheus.yml
   ```

2. Add new scrape configurations for the additional host:

   ```yaml
   # New Remote Host - Node Exporter
   - job_name: "newhost-node-exporter"
     static_configs:
       - targets: ["newhost.cw.internal:9100"]
         labels:
           host: "newhost.cw.internal"
           instance_group: "your-group-name"

   # New Remote Host - cAdvisor
   - job_name: "newhost-cadvisor"
     static_configs:
       - targets: ["newhost.cw.internal:8080"]
         labels:
           host: "newhost.cw.internal"
           instance_group: "your-group-name"
   ```

3. Reload Prometheus configuration:

   ```bash
   curl -X POST http://monitor01.cw.internal:9090/-/reload
   ```

4. Run the remote setup script on the new host.

### Customizing Alerts

Edit the alert rules in `configs/prometheus/alert-rules.yml` to customize monitoring thresholds.

### Customizing Email Notifications

Edit `configs/alertmanager/alertmanager.yml` to configure recipients and SMTP settings for alert notifications.

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
