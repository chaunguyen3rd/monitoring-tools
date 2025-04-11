#!/bin/bash
# Setup script for remote EC2 monitoring agents
# Run this on the remote EC2 instance you want to monitor

set -e

# Color codes for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Define the central monitoring server IP/hostname
# Replace with your main monitoring server address
MONITORING_SERVER="monitor01.cw.internal"

# Node name (used to identify this instance in Prometheus)
NODE_NAME=$(hostname)
# Get the instance private IP
INSTANCE_IP=$(hostname -I | awk '{print $1}')

echo -e "${BLUE}Setting up monitoring agents on ${NODE_NAME} (${INSTANCE_IP})${NC}"
echo -e "${BLUE}Metrics and logs will be sent to ${MONITORING_SERVER}${NC}"

# Check Docker installation
if ! command -v docker &> /dev/null; then
  echo -e "${RED}Docker not found. Installing Docker...${NC}"
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
fi

# Create directories for configs and data
mkdir -p /opt/monitoring/configs
mkdir -p /opt/monitoring/data

# Create Node Exporter config
cat > /opt/monitoring/configs/node_exporter.service << EOL
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=root
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100

[Install]
WantedBy=multi-user.target
EOL

# Create cAdvisor container config
cat > /opt/monitoring/configs/cadvisor-compose.yml << EOL
version: '3'
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "8080:8080"
    dns:
      - 10.0.0.2
    command:
      - '--housekeeping_interval=10s'
      - '--docker_only=true'
      - '--disable_metrics=percpu,hugetlb,sched,tcp,udp,advtcp'
EOL

# Create Promtail config
cat > /opt/monitoring/configs/promtail-compose.yml << EOL
version: '3'
services:
  promtail:
    image: grafana/promtail:latest
    container_name: promtail
    restart: unless-stopped
    volumes:
      - /opt/monitoring/configs/promtail-config.yml:/etc/promtail/promtail-config.yml
      - /var/log:/var/log
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
    dns:
      - 10.0.0.2
    command: -config.file=/etc/promtail/promtail-config.yml
EOL

# Create Promtail config file
cat > /opt/monitoring/configs/promtail-config.yml << EOL
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://${MONITORING_SERVER}:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          host: ${NODE_NAME}
          instance: ${INSTANCE_IP}
          __path__: /var/log/*log

  - job_name: docker
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker
          host: ${NODE_NAME}
          instance: ${INSTANCE_IP}
          __path__: /var/lib/docker/containers/*/*-json.log

    pipeline_stages:
      - json:
          expressions:
            stream: stream
            attrs: attrs
            tag: attrs.tag
            source: source
      - labels:
          stream:
          tag:
      - regex:
          expression: '(?P<container_id>(?:[0-9a-f]{64}|[0-9a-f]{12}))'
          source: filename
      - docker: 
          host: ${NODE_NAME}
          container_name_label: container_name
          stream_label: stream
      - timestamp:
          source: time
          format: RFC3339Nano
      - output:
          source: log
      - labeldrop:
          - attrs
          - tag
EOL

# Download and install Node Exporter
echo -e "${BLUE}Installing Node Exporter...${NC}"
NODE_EXPORTER_VERSION="1.6.1"
wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

# Install Node Exporter as a service
cp /opt/monitoring/configs/node_exporter.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Start cAdvisor
echo -e "${BLUE}Starting cAdvisor...${NC}"
cd /opt/monitoring && docker-compose -f configs/cadvisor-compose.yml up -d

# Start Promtail
echo -e "${BLUE}Starting Promtail...${NC}"
cd /opt/monitoring && docker-compose -f configs/promtail-compose.yml up -d

echo -e "${GREEN}Remote node setup complete!${NC}"
echo -e "${GREEN}Node Exporter: http://${INSTANCE_IP}:9100${NC}"
echo -e "${GREEN}cAdvisor: http://${INSTANCE_IP}:8080${NC}"
echo -e "${GREEN}Promtail: http://${INSTANCE_IP}:9080${NC}"
echo ""
echo -e "${BLUE}IMPORTANT: You must update the main Prometheus configuration${NC}"
echo -e "${BLUE}to scrape metrics from this node. See the accompanying guide.${NC}"