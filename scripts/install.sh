#!/bin/bash
# Monitoring Toolkit Installation Script
# This script installs and configures the monitoring toolkit for EC2 and Docker containers

# Exit on error, but allow for proper error handling
set -o errexit
set -o pipefail

# Script variables
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PARENT_DIR/configs"
LOG_FILE="/tmp/monitoring-toolkit-install.log"
DOCKER_COMPOSE_VERSION="2.19.1"
VERBOSE=false
SKIP_DOCKER_INSTALL=false
SKIP_DOCKER_COMPOSE_INSTALL=false
SKIP_FIREWALL_CONFIG=false
NON_INTERACTIVE=false
FORCE_INSTALL=false
BACKUP_CONFIGS=true

# Color codes for better output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display usage information
show_usage() {
  cat << EOF
Usage: $0 [OPTIONS]

This script installs the Monitoring Toolkit for EC2 and Docker Containers.

Options:
  -h, --help                   Show this help message
  -v, --verbose                Enable verbose output
  --skip-docker                Skip Docker installation
  --skip-docker-compose        Skip Docker Compose installation
  --skip-firewall              Skip firewall configuration
  --non-interactive            Run in non-interactive mode (no prompts)
  -f, --force                  Force installation even if components are already installed
  --no-backup                  Do not backup existing configuration files
  --version                    Show script version

Example:
  $0 --skip-docker --verbose

EOF
}

# Function to display version
show_version() {
  echo "Monitoring Toolkit Install Script v$SCRIPT_VERSION"
}

# Function to log messages
log() {
  local level=$1
  local message=$2
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
  
  case $level in
    INFO)
      [ "$VERBOSE" = true ] && echo -e "${BLUE}$message${NC}"
      ;;
    SUCCESS)
      echo -e "${GREEN}$message${NC}"
      ;;
    WARNING)
      echo -e "${YELLOW}$message${NC}"
      ;;
    ERROR)
      echo -e "${RED}$message${NC}"
      ;;
    *)
      echo -e "$message"
      ;;
  esac
}

# Function to handle errors
handle_error() {
  local exit_code=$?
  local line_number=$1
  log "ERROR" "Error occurred at line $line_number with exit code $exit_code"
  log "ERROR" "Check log file for details: $LOG_FILE"
  exit $exit_code
}

# Set the error trap
trap 'handle_error $LINENO' ERR

# Function to check system requirements
check_system_requirements() {
  log "INFO" "Checking system requirements..."
  
  # Check for minimum disk space (1GB free)
  local free_space=$(df -m "$PARENT_DIR" | awk 'NR==2 {print $4}')
  if [ "$free_space" -lt 1024 ]; then
    log "ERROR" "Not enough free disk space. At least 1GB required."
    exit 1
  fi
  
  # Check if running as root
  if [ "$EUID" -ne 0 ]; then
    log "ERROR" "This script must be run as root"
    exit 1
  fi
  
  # Check for required commands
  for cmd in curl wget; do
    if ! command -v $cmd &> /dev/null; then
      log "WARNING" "$cmd not found. Installing..."
      apt-get update -qq && apt-get install -y -qq $cmd
      if [ $? -ne 0 ]; then
        log "ERROR" "Failed to install $cmd. Please install it manually."
        exit 1
      fi
    fi
  done
  
  # Check for internet connectivity
  if ! ping -c 1 8.8.8.8 &> /dev/null; then
    log "WARNING" "No internet connectivity detected. Installation may fail."
    if [ "$NON_INTERACTIVE" = false ]; then
      read -p "Continue anyway? (y/n): " -r
      [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
  fi
  
  log "SUCCESS" "System requirements check passed."
}

# Function to backup existing configuration
backup_configs() {
  if [ "$BACKUP_CONFIGS" = false ]; then
    log "INFO" "Skipping configuration backup as requested."
    return 0
  fi
  
  log "INFO" "Backing up existing configurations..."
  
  local backup_dir="$PARENT_DIR/backups/$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$backup_dir"
  
  if [ -d "$CONFIG_DIR" ]; then
    cp -r "$CONFIG_DIR" "$backup_dir/"
    log "SUCCESS" "Configurations backed up to $backup_dir"
  else
    log "INFO" "No existing configurations to backup"
  fi
}

# Function to create necessary directories
create_directories() {
  log "INFO" "Creating necessary directories..."
  
  mkdir -p "$CONFIG_DIR"/{prometheus,grafana/{datasources,dashboards},loki,promtail,cadvisor,alertmanager/templates}
  mkdir -p "$PARENT_DIR/dashboards"
  
  log "SUCCESS" "Directory structure created"
}

# Function to check and install Docker
install_docker() {
  if [ "$SKIP_DOCKER_INSTALL" = true ]; then
    log "INFO" "Skipping Docker installation as requested"
    return 0
  fi
  
  if command -v docker &> /dev/null && [ "$FORCE_INSTALL" = false ]; then
    log "INFO" "Docker is already installed"
    docker --version | head -n 1 >> "$LOG_FILE"
    return 0
  fi
  
  log "INFO" "Installing Docker..."
  
  # Detect OS distribution
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
  else
    OS=$(uname -s)
  fi
  
  case $OS in
    ubuntu|debian)
      apt-get update -qq
      apt-get install -y -qq apt-transport-https ca-certificates curl software-properties-common
      
      # Add Docker repository
      if [ "$OS" = "ubuntu" ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
      else
        curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
      fi
      
      apt-get update -qq
      apt-get install -y -qq docker-ce docker-ce-cli containerd.io
      ;;
    centos|rhel|fedora)
      yum install -y yum-utils
      yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      yum install -y docker-ce docker-ce-cli containerd.io
      systemctl start docker
      systemctl enable docker
      ;;
    amzn)
      amazon-linux-extras install docker -y
      systemctl start docker
      systemctl enable docker
      ;;
    *)
      log "ERROR" "Unsupported OS for automatic Docker installation: $OS"
      log "ERROR" "Please install Docker manually: https://docs.docker.com/engine/install/"
      exit 1
      ;;
  esac
  
  # Verify Docker installation
  if command -v docker &> /dev/null; then
    log "SUCCESS" "Docker installed successfully"
    docker --version | head -n 1 >> "$LOG_FILE"
  else
    log "ERROR" "Docker installation failed"
    exit 1
  fi
}

# Function to check and install Docker Compose
install_docker_compose() {
  if [ "$SKIP_DOCKER_COMPOSE_INSTALL" = true ]; then
    log "INFO" "Skipping Docker Compose installation as requested"
    return 0
  fi
  
  if command -v docker-compose &> /dev/null && [ "$FORCE_INSTALL" = false ]; then
    log "INFO" "Docker Compose is already installed"
    docker-compose --version | head -n 1 >> "$LOG_FILE"
    return 0
  fi
  
  log "INFO" "Installing Docker Compose version $DOCKER_COMPOSE_VERSION..."
  
  # Download and install Docker Compose
  curl -L "https://github.com/docker/compose/releases/download/v$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  
  # Create a symbolic link for system-wide access
  ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
  
  # Verify Docker Compose installation
  if command -v docker-compose &> /dev/null; then
    log "SUCCESS" "Docker Compose installed successfully"
    docker-compose --version | head -n 1 >> "$LOG_FILE"
  else
    log "ERROR" "Docker Compose installation failed"
    exit 1
  fi
}

# Function to setup configuration files
setup_configurations() {
  log "INFO" "Setting up configuration files..."
  
  # Track if we need to copy any files
  local files_to_copy=false
  
  # Array of configuration files to check
  declare -A config_files=(
    ["configs/prometheus/prometheus.yml"]="example-configs/prometheus/prometheus.yml"
    ["configs/prometheus/alert-rules.yml"]="example-configs/prometheus/alert-rules.yml"
    ["configs/prometheus/recording-rules.yml"]="example-configs/prometheus/recording-rules.yml"
    ["configs/loki/loki-config.yml"]="example-configs/loki/loki-config.yml"
    ["configs/promtail/promtail-config.yml"]="example-configs/promtail/promtail-config.yml"
    ["configs/alertmanager/alertmanager.yml"]="example-configs/alertmanager/alertmanager.yml"
    ["configs/alertmanager/templates/email.tmpl"]="example-configs/alertmanager/templates/email.tmpl"
    ["configs/grafana/datasources/prometheus.yml"]="example-configs/grafana/datasources/prometheus.yml"
    ["configs/grafana/datasources/loki.yml"]="example-configs/grafana/datasources/loki.yml"
  )
  
  # Check each configuration file
  for file in "${!config_files[@]}"; do
    local dest="$PARENT_DIR/$file"
    local src="$PARENT_DIR/${config_files[$file]}"
    
    if [ ! -f "$dest" ]; then
      log "INFO" "Creating $file..."
      
      if [ -f "$src" ]; then
        cp "$src" "$dest"
        files_to_copy=true
      else
        log "WARNING" "Example file $src does not exist, skipping"
      fi
    else
      log "INFO" "$file already exists, skipping"
    fi
  done
  
  # Copy docker-compose.yml if it's not in the configs directory
  if [ ! -f "$CONFIG_DIR/docker-compose.yml" ]; then
    log "INFO" "Copying docker-compose.yml to configs directory..."
    if [ -f "$PARENT_DIR/docker-compose.yml" ]; then
      cp "$PARENT_DIR/docker-compose.yml" "$CONFIG_DIR/"
      files_to_copy=true
    else
      log "WARNING" "$PARENT_DIR/docker-compose.yml does not exist, cannot copy"
    fi
  fi
  
  # Create .env file if it doesn't exist
  if [ ! -f "$PARENT_DIR/.env" ]; then
    log "INFO" "Creating .env file from template..."
    if [ -f "$PARENT_DIR/.env.example" ]; then
      cp "$PARENT_DIR/.env.example" "$PARENT_DIR/.env"
      log "INFO" "Created .env file. Please review and update credentials before starting services."
    else
      log "WARNING" ".env.example file not found, creating empty .env file"
      touch "$PARENT_DIR/.env"
    fi
  fi
  
  # Validate configuration files if any were copied
  if [ "$files_to_copy" = true ]; then
    log "INFO" "Configuration files set up successfully"
  fi
}

# Function to set permissions
set_permissions() {
  log "INFO" "Setting permissions on configuration files..."
  
  # Set ownership for Grafana
  if [ -d "$CONFIG_DIR/grafana" ]; then
    chown -R 472:472 "$CONFIG_DIR/grafana" 2>/dev/null || log "WARNING" "Failed to set Grafana directory ownership"
  fi
  
  # Set permissions for config files
  declare -a config_files=(
    "$CONFIG_DIR/prometheus/prometheus.yml"
    "$CONFIG_DIR/prometheus/alert-rules.yml"
    "$CONFIG_DIR/loki/loki-config.yml"
    "$CONFIG_DIR/promtail/promtail-config.yml"
    "$CONFIG_DIR/alertmanager/alertmanager.yml"
    "$CONFIG_DIR/alertmanager/templates/email.tmpl"
  )
  
  for file in "${config_files[@]}"; do
    if [ -f "$file" ]; then
      chmod 644 "$file" 2>/dev/null || log "WARNING" "Failed to set permissions for $file"
    fi
  done
  
  log "SUCCESS" "Permissions set"
}

# Function to configure firewall
configure_firewall() {
  if [ "$SKIP_FIREWALL_CONFIG" = true ]; then
    log "INFO" "Skipping firewall configuration as requested"
    return 0
  fi
  
  if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
    log "INFO" "Configuring UFW firewall rules..."
    
    # Array of ports to open
    declare -A firewall_ports=(
      ["9090"]="Prometheus"
      ["9100"]="Node Exporter"
      ["8080"]="cAdvisor"
      ["3000"]="Grafana"
      ["3100"]="Loki"
      ["9093"]="Alertmanager"
    )
    
    # Add rules for each port
    for port in "${!firewall_ports[@]}"; do
      log "INFO" "Adding UFW rule for ${firewall_ports[$port]} (port $port)"
      ufw allow "$port/tcp" comment "${firewall_ports[$port]}" || log "WARNING" "Failed to add firewall rule for port $port"
    done
    
    log "SUCCESS" "Firewall configured"
  else
    log "INFO" "UFW firewall not active, skipping firewall configuration"
  fi
}

# Function to start the monitoring stack
start_monitoring_stack() {
  log "INFO" "Starting the monitoring stack..."
  
  # Check if docker-compose.yml exists
  if [ ! -f "$CONFIG_DIR/docker-compose.yml" ]; then
    log "ERROR" "docker-compose.yml not found in $CONFIG_DIR"
    exit 1
  fi
  
  # Switch to the config directory
  cd "$CONFIG_DIR"
  
  # Check if any services are already running
  if docker-compose ps | grep -q "Up" && [ "$FORCE_INSTALL" = false ]; then
    log "INFO" "Some services are already running"
    
    if [ "$NON_INTERACTIVE" = false ]; then
      read -p "Do you want to restart them? (y/n): " -r
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Skipping service restart"
        return 0
      fi
    fi
    
    # Stop running services
    log "INFO" "Stopping running services..."
    docker-compose down
  fi
  
  # Start the services
  log "INFO" "Starting services (this may take a while)..."
  if [ "$VERBOSE" = true ]; then
    docker-compose up -d
  else
    docker-compose up -d >/dev/null 2>&1
  fi
  
  # Verify services are running
  log "INFO" "Verifying services..."
  if docker-compose ps | grep -q "Up"; then
    log "SUCCESS" "Monitoring stack started successfully!"
  else
    log "ERROR" "Some services failed to start. Check with 'docker-compose logs'"
    exit 1
  fi
}

# Function to display success message
show_success_message() {
  log "SUCCESS" "Monitoring toolkit installed successfully!"
  log "SUCCESS" "You can access:"
  log "SUCCESS" "- Grafana at http://localhost:3000 (default: admin/admin)"
  log "SUCCESS" "- Prometheus at http://localhost:9090"
  log "SUCCESS" "- Alertmanager at http://localhost:9093"
  log "INFO" "For troubleshooting, check the log file: $LOG_FILE"
}

# Parse command line options
parse_options() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_usage
        exit 0
        ;;
      -v|--verbose)
        VERBOSE=true
        shift
        ;;
      --skip-docker)
        SKIP_DOCKER_INSTALL=true
        shift
        ;;
      --skip-docker-compose)
        SKIP_DOCKER_COMPOSE_INSTALL=true
        shift
        ;;
      --skip-firewall)
        SKIP_FIREWALL_CONFIG=true
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=true
        shift
        ;;
      -f|--force)
        FORCE_INSTALL=true
        shift
        ;;
      --no-backup)
        BACKUP_CONFIGS=false
        shift
        ;;
      --version)
        show_version
        exit 0
        ;;
      *)
        log "ERROR" "Unknown option: $1"
        show_usage
        exit 1
        ;;
    esac
  done
}

# Main function
main() {
  # Initialize log file
  echo "=== Monitoring Toolkit Installation Log ($(date)) ===" > "$LOG_FILE"
  log "INFO" "Starting installation script v$SCRIPT_VERSION"
  
  # Run installation steps
  check_system_requirements
  backup_configs
  create_directories
  install_docker
  install_docker_compose
  setup_configurations
  set_permissions
  configure_firewall
  start_monitoring_stack
  show_success_message
  
  log "INFO" "Installation completed"
}

# Parse command line options
parse_options "$@"

# Run the main function
main