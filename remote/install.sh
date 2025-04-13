#!/bin/bash
# Simple install script for remote monitoring agents

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Get the monitoring server address
read -p "Enter monitoring server IP or hostname: " MONITORING_SERVER
if [ -z "$MONITORING_SERVER" ]; then
  echo "Monitoring server address is required"
  exit 1
fi

# Get this host's name for labels
read -p "Enter this host's name [$(hostname)]: " HOST_NAME
HOST_NAME=${HOST_NAME:-$(hostname)}

# Install Docker if needed
if ! command -v docker &> /dev/null; then
  echo "Docker not found. Installing Docker..."
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
fi

# Install Docker Compose if needed
if ! command -v docker-compose &> /dev/null; then
  echo "Docker Compose not found. Installing Docker Compose..."
  curl -L "https://github.com/docker/compose/releases/download/v2.19.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

# Update promtail config with monitoring server address and host name
echo "Configuring promtail..."
sed -i "s/MONITORING_SERVER/${MONITORING_SERVER}/g" promtail-config.yml
sed -i "s/HOST_NAME/${HOST_NAME}/g" promtail-config.yml

# Start the monitoring agents
echo "Starting monitoring agents..."
docker-compose up -d

# Check if services are running
if [ "$(docker ps | grep -c "node-exporter\|cadvisor\|promtail")" -eq 3 ]; then
  echo "✅ Monitoring agents started successfully!"
  echo ""
  echo "Monitoring endpoints:"
  echo "- Node Exporter: http://$(hostname -I | awk '{print $1}'):9100"
  echo "- cAdvisor: http://$(hostname -I | awk '{print $1}'):8080"
  echo ""
  echo "This host (${HOST_NAME}) is now sending metrics and logs to ${MONITORING_SERVER}"
else
  echo "❌ Some services failed to start. Check with 'docker-compose logs'"
fi

# Create a systemd service for auto-start on boot
echo "Creating systemd service for auto-start..."
cat > /etc/systemd/system/monitoring-agent.service << EOF
[Unit]
Description=Monitoring Agent Stack
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl daemon-reload
systemctl enable monitoring-agent.service

echo ""
echo "Installation complete! Make sure this host is added to Prometheus on ${MONITORING_SERVER}"
echo "Add the following to your Prometheus configuration:"
echo ""
echo "  - job_name: \"${HOST_NAME}-node\""
echo "    static_configs:"
echo "      - targets: [\"${HOST_NAME}:9100\"]"
echo "        labels:"
echo "          host: \"${HOST_NAME}\""
echo ""
echo "  - job_name: \"${HOST_NAME}-cadvisor\""
echo "    static_configs:"
echo "      - targets: [\"${HOST_NAME}:8080\"]"
echo "        labels:"
echo "          host: \"${HOST_NAME}\""