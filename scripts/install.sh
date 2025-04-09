#!/bin/bash
set -e

# Color codes for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

echo -e "${BLUE}Installing monitoring toolkit...${NC}"

# Create necessary directories
mkdir -p configs/{prometheus,grafana/{datasources,dashboards},loki,promtail,cadvisor,alertmanager/templates}
mkdir -p dashboards

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
  echo -e "${BLUE}Docker not found. Installing Docker...${NC}"
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
  echo -e "${BLUE}Docker Compose not found. Installing Docker Compose...${NC}"
  curl -L "https://github.com/docker/compose/releases/download/v2.19.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

# Copy configuration files
echo -e "${BLUE}Copying configuration files...${NC}"
cp docker-compose.yml configs/
cp configs/prometheus/prometheus.yml configs/prometheus/
cp configs/prometheus/alert-rules.yml configs/prometheus/
cp configs/loki/loki-config.yml configs/loki/
cp configs/promtail/promtail-config.yml configs/promtail/
cp configs/alertmanager/alertmanager.yml configs/alertmanager/
cp configs/alertmanager/templates/email.tmpl configs/alertmanager/templates/

# If .env file doesn't exist, create from example
if [ ! -f .env ]; then
  echo -e "${BLUE}Creating .env file from template...${NC}"
  cp .env.example .env
  echo -e "${GREEN}Created .env file. Please review and update credentials before starting services.${NC}"
fi

# Set permissions
echo -e "${BLUE}Setting permissions...${NC}"
chown -R 472:472 configs/grafana
chmod 644 configs/prometheus/prometheus.yml
chmod 644 configs/prometheus/alert-rules.yml
chmod 644 configs/loki/loki-config.yml
chmod 644 configs/promtail/promtail-config.yml
chmod 644 configs/alertmanager/alertmanager.yml
chmod 644 configs/alertmanager/templates/email.tmpl

# Add firewall rules if UFW is enabled
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
  echo -e "${BLUE}Configuring firewall rules...${NC}"
  ufw allow 9090/tcp comment "Prometheus"
  ufw allow 9100/tcp comment "Node Exporter"
  ufw allow 8080/tcp comment "cAdvisor"
  ufw allow 3000/tcp comment "Grafana"
  ufw allow 3100/tcp comment "Loki"
  ufw allow 9093/tcp comment "Alertmanager"
fi

# Start the monitoring stack
echo -e "${BLUE}Starting monitoring stack...${NC}"
docker-compose up -d

# Verify services are running
echo -e "${BLUE}Verifying services...${NC}"
if docker-compose ps | grep -q "Up"; then
  echo -e "${GREEN}Monitoring stack installed successfully!${NC}"
  echo -e "${GREEN}You can access:${NC}"
  echo -e "${GREEN}- Grafana at http://localhost:3000 (default: admin/admin)${NC}"
  echo -e "${GREEN}- Prometheus at http://localhost:9090${NC}"
  echo -e "${GREEN}- Alertmanager at http://localhost:9093${NC}"
else
  echo -e "${RED}Some services failed to start. Please check logs with 'docker-compose logs'${NC}"
fi

echo -e "${BLUE}Installation complete!${NC}"