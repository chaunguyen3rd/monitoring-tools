#!/bin/bash
# Remote EC2 monitoring setup script

set -e

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if files exist
if [ ! -f "remote-docker-compose.yml" ] || [ ! -f "promtail-config.yml" ]; then
  echo -e "${RED}Error: remote-docker-compose.yml and promtail-config.yml must exist in the current directory${NC}"
  exit 1
fi

# Ask for main monitoring server IP
read -p "Enter your main monitoring server IP or hostname: " MONITORING_SERVER_IP
if [ -z "$MONITORING_SERVER_IP" ]; then
  echo -e "${RED}Monitoring server IP is required. Exiting.${NC}"
  exit 1
fi

# Update Promtail config with the correct monitoring server IP
echo -e "${BLUE}Updating promtail configuration...${NC}"
sed -i "s|http://MONITORING_SERVER_IP:3100/loki/api/v1/push|http://${MONITORING_SERVER_IP}:3100/loki/api/v1/push|g" promtail-config.yml

# Rename to standard docker-compose file
echo -e "${BLUE}Preparing Docker Compose configuration...${NC}"
cp remote-docker-compose.yml docker-compose.yml

# Get the hostname of this EC2 instance
EC2_HOSTNAME=$(hostname)
echo -e "${BLUE}Setting up monitoring for host: ${EC2_HOSTNAME}${NC}"

# Start the monitoring services with the HOSTNAME environment variable
echo -e "${BLUE}Starting monitoring services...${NC}"
HOSTNAME=$EC2_HOSTNAME docker compose up -d

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