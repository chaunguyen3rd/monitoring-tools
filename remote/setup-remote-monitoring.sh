#!/bin/bash
# Remote EC2 monitoring setup script

set -e

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create a directory for monitoring files
echo -e "${BLUE}Creating monitoring directory...${NC}"
mkdir -p ~/docker-monitoring

# Ask for main monitoring server IP
read -p "Enter your main monitoring server IP or hostname: " MONITORING_SERVER_IP
if [ -z "$MONITORING_SERVER_IP" ]; then
  echo -e "${RED}Monitoring server IP is required. Exiting.${NC}"
  exit 1
fi

# Download the Docker Compose file
cat > ~/docker-monitoring/docker-compose.yml << 'EOL'
version: '3.8'

networks:
  remote-monitoring:
    driver: bridge

services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($|/)'
    ports:
      - "9100:9100"
    networks:
      - remote-monitoring
    labels:
      instance: "${HOSTNAME}"
      host: "${HOSTNAME}"
      
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
    networks:
      - remote-monitoring
    command:
      - '--housekeeping_interval=10s'
      - '--docker_only=true'
      - '--disable_metrics=percpu,hugetlb,sched,tcp,udp,advtcp'
    labels:
      instance: "${HOSTNAME}"
      host: "${HOSTNAME}"

  promtail:
    image: grafana/promtail:latest
    container_name: promtail
    restart: unless-stopped
    volumes:
      - ./promtail-config.yml:/etc/promtail/config.yml
      - /var/log:/var/log
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    command: -config.file=/etc/promtail/config.yml
    networks:
      - remote-monitoring
    labels:
      instance: "${HOSTNAME}"
      host: "${HOSTNAME}"
EOL

# Create Promtail config
cat > ~/docker-monitoring/promtail-config.yml << EOL
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://${MONITORING_SERVER_IP}:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          host: "${HOSTNAME}"
          __path__: /var/log/*log

  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container_name'
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: 'stream'
      - source_labels: ['__meta_docker_container_label_com_docker_compose_service']
        target_label: 'service'
      - target_label: 'host'
        replacement: '${HOSTNAME}'
    pipeline_stages:
      - json:
          expressions:
            stream: stream
            log: log
            attrs: attrs
            time: time
      - timestamp:
          source: time
          format: RFC3339Nano
      - output:
          source: log

  # Fallback for containers without our custom labels
  - job_name: docker_fallback
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker
          host: "${HOSTNAME}"
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
          expression: "(?P<container_id>(?:[0-9a-f]{64}|[0-9a-f]{12}))"
          source: filename
      - docker:
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

# Start the monitoring services
echo -e "${BLUE}Starting monitoring services...${NC}"
cd ~/docker-monitoring
docker compose up -d

# Print information
echo -e "${GREEN}Remote monitoring services started on $(hostname)${NC}"
echo -e "${GREEN}Node exporter: http://$(hostname -I | awk '{print $1}'):9100${NC}"
echo -e "${GREEN}cAdvisor: http://$(hostname -I | awk '{print $1}'):8080${NC}"
echo -e "${GREEN}Logs are being sent to ${MONITORING_SERVER_IP}:3100${NC}"
echo ""
echo -e "${BLUE}Important: Update your main Prometheus configuration to scrape this instance${NC}"
echo -e "${BLUE}Add the following to your prometheus.yml scrape_configs:${NC}"
echo ""
echo "  # EC2 Instance - Node Exporter"
echo "  - job_name: \"remote-node-exporter-$(hostname)\""
echo "    static_configs:"
echo "      - targets: [\"$(hostname -I | awk '{print $1}'):9100\"]"
echo "        labels:"
echo "          host: \"$(hostname)\""
echo "          instance_group: \"application\""
echo ""
echo "  # EC2 Instance - cAdvisor"
echo "  - job_name: \"remote-cadvisor-$(hostname)\""
echo "    static_configs:"
echo "      - targets: [\"$(hostname -I | awk '{print $1}'):8080\"]"
echo "        labels:"
echo "          host: \"$(hostname)\""
echo "          instance_group: \"application\""