#!/bin/bash
#
# Docker Container Log Troubleshooter for Loki/Promtail
#

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Docker Container Logging Troubleshooter${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Docker is running
if ! docker info &>/dev/null; then
  echo -e "${RED}Error: Docker is not running or you don't have permission to access it.${NC}"
  echo "Please make sure Docker is running and you have the proper permissions."
  exit 1
fi

# Check if our monitoring stack is running
echo -e "${YELLOW}Checking monitoring stack status...${NC}"
if ! docker ps | grep -q "grafana\|loki\|promtail"; then
  echo -e "${RED}Error: Monitoring stack containers are not running.${NC}"
  echo "Please start your monitoring stack with docker-compose up -d"
  exit 1
fi

# Check if Loki is running
if ! docker ps | grep -q "loki"; then
  echo -e "${RED}Error: Loki container is not running.${NC}"
  echo "Please check logs with: docker-compose logs loki"
  exit 1
else
  echo -e "${GREEN}✓ Loki is running${NC}"
fi

# Check if Promtail is running
if ! docker ps | grep -q "promtail"; then
  echo -e "${RED}Error: Promtail container is not running.${NC}"
  echo "Please check logs with: docker-compose logs promtail"
  exit 1
else
  echo -e "${GREEN}✓ Promtail is running${NC}"
fi

# Check if promtail can reach loki
echo -e "${YELLOW}Checking Promtail connectivity to Loki...${NC}"
PROMTAIL_LOGS=$(docker logs promtail 2>&1 | grep -i "error\|failed\|cannot" | wc -l)
if [ $PROMTAIL_LOGS -gt 0 ]; then
  echo -e "${YELLOW}Potential issues found in Promtail logs:${NC}"
  docker logs promtail 2>&1 | grep -i "error\|failed\|cannot" | head -5
  echo "See full logs with: docker logs promtail"
else
  echo -e "${GREEN}✓ No obvious errors in Promtail logs${NC}"
fi

# Check if containers have logs
echo -e "${YELLOW}Checking container log files...${NC}"
CONTAINER_LOGS=$(find /var/lib/docker/containers -name "*-json.log" | wc -l)
if [ $CONTAINER_LOGS -eq 0 ]; then
  echo -e "${RED}No container log files found in /var/lib/docker/containers${NC}"
  echo "This could be due to missing permissions or a different Docker log location"
else
  echo -e "${GREEN}✓ Found $CONTAINER_LOGS container log files${NC}"
fi

# Check prometheus container logs specifically
echo -e "${YELLOW}Checking for Prometheus container logs...${NC}"
PROMETHEUS_ID=$(docker ps | grep "prometheus" | awk '{print $1}')
if [ -z "$PROMETHEUS_ID" ]; then
  echo -e "${RED}Prometheus container not found running${NC}"
else
  PROMETHEUS_LOG=$(find /var/lib/docker/containers -name "${PROMETHEUS_ID}*-json.log")
  if [ -z "$PROMETHEUS_LOG" ]; then
    echo -e "${RED}Log file for Prometheus container not found${NC}"
  else
    echo -e "${GREEN}✓ Prometheus log file exists: ${PROMETHEUS_LOG}${NC}"
    
    # Check if log file is being updated
    LAST_MODIFIED=$(stat -c %Y "$PROMETHEUS_LOG")
    CURRENT_TIME=$(date +%s)
    TIME_DIFF=$((CURRENT_TIME - LAST_MODIFIED))
    
    if [ $TIME_DIFF -gt 3600 ]; then
      echo -e "${YELLOW}Warning: Prometheus log file hasn't been modified in the last hour${NC}"
    else
      echo -e "${GREEN}✓ Prometheus log file was modified within the last hour${NC}"
    fi
  fi
fi

# Check Promtail configuration
echo -e "${YELLOW}Verifying Promtail configuration...${NC}"
if docker exec promtail ls /etc/promtail/config.yml &>/dev/null; then
  echo -e "${GREEN}✓ Promtail configuration file exists${NC}"
  
  # Check Docker pipeline stages
  if docker exec promtail grep -q "docker:" /etc/promtail/config.yml; then
    echo -e "${GREEN}✓ Promtail has Docker pipeline stage configured${NC}"
  else
    echo -e "${RED}ERROR: Promtail is missing Docker pipeline stage${NC}"
    echo "Please update your Promtail configuration to include Docker pipeline stage."
  fi
  
  # Check container_name_label mapping
  if docker exec promtail grep -q "container_name_label" /etc/promtail/config.yml; then
    echo -e "${GREEN}✓ Promtail has container_name_label mapping${NC}"
  else
    echo -e "${RED}ERROR: Promtail is missing container_name_label mapping${NC}"
    echo "Please update your Promtail configuration to extract container names."
  fi
else
  echo -e "${RED}ERROR: Promtail configuration file not found${NC}"
fi

# Test direct Loki query through Loki API
echo -e "${YELLOW}Testing direct Loki query...${NC}"
LOKI_QUERY_RESULT=$(curl -s "http://localhost:3100/loki/api/v1/label/container_name/values" | grep -c "values")
if [ $LOKI_QUERY_RESULT -gt 0 ]; then
  echo -e "${GREEN}✓ Loki returned container_name label values${NC}"
  echo "Available container names in Loki:"
  curl -s "http://localhost:3100/loki/api/v1/label/container_name/values" | grep -o '"[^"]*"' | sed 's/"//g' | grep -v "values" | sort
else
  echo -e "${RED}ERROR: Loki did not return container_name label values${NC}"
  echo "This suggests Promtail is not correctly extracting container names"
fi

# Update recommendations
echo ""
echo -e "${BLUE}==========================${NC}"
echo -e "${BLUE}Recommendations${NC}"
echo -e "${BLUE}==========================${NC}"
echo ""
echo "1. Update your Promtail configuration:"
echo "   - Check that the container log path is correct (/var/lib/docker/containers/*/*-json.log)"
echo "   - Ensure the Docker pipeline stage is configured correctly"
echo ""
echo "2. Install the new Container Logs Explorer Dashboard:"
echo "   - Copy container-logs-explorer.json to your dashboards directory"
echo "   - Restart Grafana with: docker-compose restart grafana"
echo ""
echo "3. Restart Promtail after configuration changes:"
echo "   - docker-compose restart promtail"
echo ""
echo "4. If still having issues, manually query logs with:"
echo "   - curl -G -s 'http://localhost:3100/loki/api/v1/query_range' \\"
echo "     --data-urlencode 'query={job=\"docker\"}' \\"
echo "     --data-urlencode 'start=1714000000000000000' \\"
echo "     --data-urlencode 'end=1714699999999999999' | jq"
echo ""