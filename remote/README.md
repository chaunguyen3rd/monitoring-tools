# Remote Host Monitoring Setup

This folder contains a minimal setup to monitor remote EC2 hosts and their Docker containers. It includes:

1. `docker-compose.yml` - Defines the monitoring agent containers
2. `install.sh` - Installation script that sets up everything
3. `promtail-config.yml` - Configuration template for Promtail (log collector)
4. `README.md` - This documentation file

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

3. Make the installation script executable and run it:

   ```bash
   chmod +x install.sh
   sudo ./install.sh
   ```

4. When prompted, enter:
   - Your monitoring server's IP address or hostname
   - A name for this host (defaults to the hostname)

## What Gets Installed

This setup installs three monitoring agents:

- **Node Exporter** (port 9100) - Collects host metrics (CPU, memory, disk, etc.)
- **cAdvisor** (port 8080) - Collects container metrics
- **Promtail** - Collects logs from both the host and containers

## After Installation

After installation, you'll need to update your Prometheus configuration on the monitoring server to scrape metrics from this host. The exact configuration is shown at the end of the installation process.

The script also creates a systemd service called `monitoring-agent` that will automatically start the monitoring agents when the host boots up.
