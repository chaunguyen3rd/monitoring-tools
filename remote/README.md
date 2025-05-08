# Remote Host Monitoring Setup

This folder contains a minimal setup to monitor remote hosts and their Docker containers. It includes:

1. `docker-compose.yml` - Defines the monitoring agent containers
2. `promtail-config.yml` - Configuration template for Promtail (log collector)
3. `README.md` - This documentation file

## Quick Start

1. Copy these files to your remote host:

   ```bash
   scp -r remote/ user@your-remote-host:~/monitoring/
   ```

2. SSH into your remote host:

   ```bash
   ssh user@your-remote-host
   cd ~/monitoring
   ```

3. Start the monitoring stack:

   ```bash
   docker-compose up -d
   ```

4. You may need to edit `promtail-config.yml` to update:
   - The Loki server URL (`clients.url`)
   - The host label in both scrape configs (currently set to "dev01.cw.internal")

## What Gets Installed

This setup installs three monitoring agents:

- **Node Exporter** (port 9100) - Collects host metrics (CPU, memory, disk, etc.)
- **cAdvisor** (port 8080) - Collects container metrics
- **Promtail** - Collects logs from both the host and containers

## Monitoring Components

### Node Exporter

Collects system-level metrics including CPU, memory, disk usage, and network statistics. Access metrics at http://[host-ip]:9100/metrics

### cAdvisor

Provides container-level metrics including CPU, memory, network usage for all running containers. Access the web interface at http://[host-ip]:8080

### Promtail

Collects and forwards logs to a Loki instance. Configured to collect:

- System logs from `/var/log/`
- Container logs via Docker API
- Falls back to reading container logs directly from `/var/lib/docker/containers/`

## After Installation

After deployment, you'll need to update your Prometheus configuration on the monitoring server to scrape metrics from this host. Add the following to your Prometheus configuration:

```yaml
scrape_configs:
  - job_name: 'remote-node'
    static_configs:
      - targets: ['remote-host-ip:9100']
        labels:
          instance: 'remote-host-name'
  
  - job_name: 'remote-cadvisor'
    static_configs:
      - targets: ['remote-host-ip:8080']
        labels:
          instance: 'remote-host-name'
```

Replace 'remote-host-ip' and 'remote-host-name' with your actual host IP and name.

## Custom Configuration

You can customize the behavior of these monitoring agents by editing the docker-compose.yml and promtail-config.yml files.
