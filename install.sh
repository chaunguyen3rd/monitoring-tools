#!/bin/bash
# Simple monitoring stack installation script

set -e

# Color codes for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Installing monitoring stack...${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

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
  cat > .env << 'EOL'
# Grafana credentials
ADMIN_USER=admin
ADMIN_PASSWORD=admin
EOL
fi

# Create a sample .env file
if [ ! -f .env ]; then
  echo -e "${BLUE}Creating .env file...${NC}"
  cat > .env << 'EOL'
# Grafana credentials
ADMIN_USER=admin
ADMIN_PASSWORD=admin
EOL
fi

# Set proper permissions
echo -e "${BLUE}Setting permissions...${NC}"
chown -R 472:472 configs/grafana 2>/dev/null || echo "Could not set Grafana directory ownership"

# Start the monitoring stack
echo -e "${BLUE}Starting monitoring stack...${NC}"
docker-compose up -d

# Verify services are running
echo -e "${BLUE}Verifying services...${NC}"
if docker-compose ps | grep -q "Up"; then
  echo -e "${GREEN}Monitoring stack started successfully!${NC}"
  echo -e "${GREEN}You can access:${NC}"
  echo -e "${GREEN}- Grafana at http://localhost:3000 (default: admin/admin)${NC}"
  echo -e "${GREEN}- Prometheus at http://localhost:9090${NC}"
  echo -e "${GREEN}- Alertmanager at http://localhost:9093${NC}"
  echo -e "${GREEN}- Loki at http://localhost:3100${NC}"
else
  echo -e "${RED}Some services failed to start. Check with 'docker-compose logs'${NC}"
  exit 1
fi

echo -e "${GREEN}Installation complete!${NC}"