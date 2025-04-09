# Monitoring Toolkit for EC2 and Docker Containers

A comprehensive monitoring solution for EC2 instances and Docker containers using Prometheus, Grafana, Loki, Alertmanager, and related exporters.

## Overview

This monitoring toolkit provides a complete stack for monitoring remote EC2 instances and Docker containers with:

- **Prometheus**: For metrics collection and storage
- **Grafana**: For visualization and dashboarding
- **Loki & Promtail**: For log aggregation
- **Alertmanager**: For alert handling and notifications
- **Node Exporter**: For host-level metrics
- **cAdvisor**: For container metrics

![Architecture Overview](docs/architecture_diagram.png)

## Features

- **Complete Observability**: Metrics, logs, and alerts in one solution
- **Container-Aware**: Detailed monitoring of Docker containers
- **Alerting**: Configurable alerts via email, Slack, and more
- **Pre-built Dashboards**: Ready-to-use dashboards for common monitoring needs
- **Deployment Automation**: Scripts and Ansible playbooks for easy deployment
- **Remote Monitoring**: Monitor multiple EC2 instances from a central location

## Prerequisites

- Docker and Docker Compose
- An EC2 instance with SSH access
- Basic understanding of monitoring concepts
- SMTP server for email alerts (optional)
- Slack webhook for Slack notifications (optional)

## Quick Start

### Local Installation

1. Clone this repository:

   ```bash
   git clone https://github.com/yourusername/monitoring-toolkit.git
   cd monitoring-toolkit
   ```

2. Run the installation script:

   ```bash
   sudo ./scripts/install.sh
   ```

3. Access the interfaces:
   - Grafana: <http://localhost:3000> (default credentials: admin/admin)
   - Prometheus: <http://localhost:9090>
   - Alertmanager: <http://localhost:9093>

### Remote EC2 Monitoring

1. Update the inventory file:

   ```bash
   nano ansible/inventory/hosts
   ```

2. Deploy to remote instances:

   ```bash
   cd ansible
   ansible-playbook playbooks/deploy-monitoring.yml
   ```

## Configuration

### Alerting

Edit the Alertmanager configuration to set up notification channels:

```bash
nano configs/alertmanager/alertmanager.yml
```

Update the following sections:

- Global SMTP settings for email notifications
- Slack webhook URL for Slack notifications
- Routes and receivers for alert routing

### Adding Alert Rules

Define new alert rules in the Prometheus configuration:

```bash
nano configs/prometheus/alert-rules.yml
```

Example alert rule:

```yaml
- alert: HighCPUUsage
  expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High CPU usage on {{ $labels.instance }}"
    description: "CPU usage is above 90% for 5 minutes (current value: {{ $value }}%)"
```

### Configuring Dashboards

Custom dashboards can be added to the `dashboards` directory:

```bash
cp your-dashboard.json dashboards/
```

## Project Structure

```txt
monitoring-toolkit/
├── ansible/                        # Deployment automation
├── configs/                        # Configuration files
│   ├── prometheus/                 # Prometheus configs
│   ├── alertmanager/              # Alertmanager configs
│   ├── grafana/                    # Grafana configs
│   ├── loki/                       # Loki configs
│   ├── promtail/                   # Promtail configs
│   └── cadvisor/                   # cAdvisor configs
├── dashboards/                     # Grafana dashboards
├── scripts/                        # Utility scripts
├── terraform/                      # Infrastructure as code (optional)
└── docs/                           # Documentation
```

## Customization

### Adding New Targets

To monitor additional EC2 instances or containers:

1. Update the Prometheus configuration:

   ```bash
   nano configs/prometheus/prometheus.yml
   ```

2. Add new targets under `scrape_configs`:

   ```yaml
   - job_name: 'new-ec2-instance'
     static_configs:
       - targets: ['new-ec2-ip:9100']
         labels:
           instance: new-ec2-name
   ```

### Persistent Storage

By default, the monitoring data uses Docker volumes. For production, consider using more robust storage:

```yaml
volumes:
  prometheus_data:
    driver: local
    driver_opts:
      type: 'none'
      o: 'bind'
      device: '/path/to/prometheus/data'
```

## Maintenance

### Backup

Backup your configuration and data:

```bash
./scripts/backup.sh
```

### Updates

Update the monitoring stack:

```bash
./scripts/update.sh
```

### Troubleshooting

Common issues and solutions are documented in `docs/troubleshooting.md`.

## Security Considerations

- Configure proper authentication for all components
- Use HTTPS for production deployments
- Restrict network access using security groups
- Regularly update the components to patch security vulnerabilities

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- [Prometheus](https://prometheus.io/)
- [Grafana](https://grafana.com/)
- [Loki](https://grafana.com/oss/loki/)
- [cAdvisor](https://github.com/google/cadvisor)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/)
