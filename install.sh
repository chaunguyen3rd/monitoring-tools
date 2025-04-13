#!/bin/bash
# Monitoring stack installation script for CW server cluster

set -e

# Color codes for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Installing monitoring stack for CW server cluster...${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

# Prompt for configuration details
read -p "Enter this host's FQDN [monitor01.cw.internal]: " HOST_FQDN
HOST_FQDN=${HOST_FQDN:-monitor01.cw.internal}

read -p "Enter first remote host FQDN [dev01.cw.internal]: " REMOTE_HOST1
REMOTE_HOST1=${REMOTE_HOST1:-dev01.cw.internal}

read -p "Enter second remote host FQDN [fe01.cw.internal]: " REMOTE_HOST2
REMOTE_HOST2=${REMOTE_HOST2:-fe01.cw.internal}

read -p "Enter Grafana admin username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

read -s -p "Enter Grafana admin password [admin]: " ADMIN_PASSWORD
echo ""
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}

# Check Docker installation
if ! command -v docker &> /dev/null; then
  echo -e "${BLUE}Docker not found. Installing Docker...${NC}"
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
fi

# Check Docker Compose installation
if ! command -v docker-compose &> /dev/null; then
  echo -e "${BLUE}Docker Compose not found. Installing Docker Compose...${NC}"
  curl -L "https://github.com/docker/compose/releases/download/v2.19.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

# Check if .env file exists, create if not
if [ ! -f .env ]; then
  echo -e "${BLUE}Creating .env file...${NC}"
  cat > .env << EOL
# Grafana credentials
ADMIN_USER=${ADMIN_USER}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
EOL
fi

# Update prometheus.yml with the correct hostnames
echo -e "${BLUE}Updating Prometheus configuration...${NC}"
sed -i "s/monitor01.cw.internal/${HOST_FQDN}/g" configs/prometheus/prometheus.yml
sed -i "s/dev01.cw.internal/${REMOTE_HOST1}/g" configs/prometheus/prometheus.yml
sed -i "s/fe01.cw.internal/${REMOTE_HOST2}/g" configs/prometheus/prometheus.yml

# Update other configs to use the correct hostname
echo -e "${BLUE}Updating other configurations...${NC}"
sed -i "s/monitor01.cw.internal/${HOST_FQDN}/g" configs/promtail/promtail-config.yml
sed -i "s/monitor01.cw.internal/${HOST_FQDN}/g" docker-compose.yml

# Set proper permissions
echo -e "${BLUE}Setting permissions...${NC}"
chmod -R 777 configs/grafana
chown -R 472:472 configs/grafana 2>/dev/null || echo "Could not set Grafana directory ownership"

# Start the monitoring stack
echo -e "${BLUE}Starting monitoring stack...${NC}"
docker-compose up -d

# Verify services are running
echo -e "${BLUE}Verifying services...${NC}"
if docker-compose ps | grep -q "Up"; then
  echo -e "${GREEN}Monitoring stack started successfully!${NC}"
  echo -e "${GREEN}You can access:${NC}"
  echo -e "${GREEN}- Grafana at http://${HOST_FQDN}:3000 (credentials: ${ADMIN_USER}/${ADMIN_PASSWORD})${NC}"
  echo -e "${GREEN}- Prometheus at http://${HOST_FQDN}:9090${NC}"
  echo -e "${GREEN}- AlertManager at http://${HOST_FQDN}:9093${NC}"
  echo -e "${GREEN}- Loki at http://${HOST_FQDN}:3100${NC}"
else
  echo -e "${RED}Some services failed to start. Check with 'docker-compose logs'${NC}"
  exit 1
fi

echo -e "${GREEN}Main monitoring node installation complete!${NC}"
echo -e "${BLUE}Next steps:${NC}"
echo -e "1. Use the 'remote' folder to set up monitoring on your remote hosts"
echo -e "2. Copy the remote folder to each host and run the install.sh script there"
echo -e "3. When prompted, enter this server's hostname: ${HOST_FQDN}"
echo -e ""
echo -e "Once completed, all your servers will be monitored and viewable in Grafana."