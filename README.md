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
└── dashboards/                         # Grafana dashboards
```

## Prerequisites

- Docker and Docker Compose
- Linux host with sufficient resources
- Root access for installation

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
- Permissions issues: Make sure Docker has permission to mount volumes
- Resource limitations: Ensure your system has enough memory and CPU

## License

MIT License
