#!/bin/bash
set -euo pipefail

# WordPress Podcast Server Setup
# Script 2: Bootstrap Server

# Configuration
SECRETS_FILE="./secrets.yml"
LOG_FILE="./logs/02_bootstrap.log"
SERVER_IP_FILE="./server_ip.txt"

# Create logs directory if it doesn't exist
mkdir -p logs

# Function to log messages
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to extract values from secrets.yml
get_secret() {
  local path=$1
  yq eval "$path" "$SECRETS_FILE"
}

# Check if secrets.yml exists
if [ ! -f "$SECRETS_FILE" ]; then
  log "❌ Error: secrets.yml file not found!"
  exit 1
fi

# Check if server_ip.txt exists
if [ ! -f "$SERVER_IP_FILE" ]; then
  log "❌ Error: server_ip.txt file not found! Run 01_provision_vm.sh first."
  exit 1
fi

# Extract SSH credentials from secrets.yml
SSH_PRIVATE_KEY_PATH=$(get_secret '.ssh.private_key_path')
ADMIN_USERNAME=$(get_secret '.ssh.admin_username')

# Expand ~ in path if present
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH/#\~/$HOME}"

# Get server IP
SERVER_IP=$(cat "$SERVER_IP_FILE")

# Check if SSH private key exists
if [ ! -f "$SSH_PRIVATE_KEY_PATH" ]; then
  log "❌ Error: SSH private key file not found at $SSH_PRIVATE_KEY_PATH"
  exit 1
fi

# Function to run commands on the remote server
run_remote() {
  ssh -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$ADMIN_USERNAME@$SERVER_IP" "$1"
}

# Function to check if a command exists on the remote server
remote_command_exists() {
  run_remote "command -v $1 > /dev/null 2>&1 && echo 'yes' || echo 'no'"
}

# Wait for SSH to be available
log "Waiting for SSH to be available on $SERVER_IP..."
for i in {1..30}; do
  if ssh -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "$ADMIN_USERNAME@$SERVER_IP" "echo 'SSH is available'" &> /dev/null; then
    log "✅ SSH is available"
    break
  fi
  
  if [ $i -eq 30 ]; then
    log "❌ Timed out waiting for SSH to be available"
    exit 1
  fi
  
  log "Waiting for SSH... (attempt $i/30)"
  sleep 10
done

# Update system packages
log "Updating system packages..."
run_remote "sudo apt-get update && sudo apt-get upgrade -y"
log "✅ System packages updated"

# Install required packages
log "Installing required packages..."
run_remote "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg software-properties-common"
log "✅ Required packages installed"

# Install Docker
log "Checking if Docker is already installed..."
if [ "$(remote_command_exists docker)" == "yes" ]; then
  log "✅ Docker is already installed"
else
  log "Installing Docker..."
  run_remote "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
  run_remote "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
  run_remote "sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io"
  run_remote "sudo usermod -aG docker $ADMIN_USERNAME"
  log "✅ Docker installed successfully"
fi

# Install Docker Compose
log "Checking if Docker Compose is already installed..."
if [ "$(remote_command_exists docker-compose)" == "yes" ]; then
  log "✅ Docker Compose is already installed"
else
  log "Installing Docker Compose..."
  run_remote "sudo curl -L \"https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose"
  run_remote "sudo chmod +x /usr/local/bin/docker-compose"
  log "✅ Docker Compose installed successfully"
fi

# Configure UFW firewall
log "Configuring UFW firewall..."
run_remote "sudo apt-get install -y ufw"
run_remote "sudo ufw default deny incoming"
run_remote "sudo ufw default allow outgoing"
run_remote "sudo ufw allow 22/tcp"
run_remote "sudo ufw allow 80/tcp"
run_remote "sudo ufw allow 443/tcp"
run_remote "echo 'y' | sudo ufw enable"
log "✅ UFW firewall configured"

# Install Certbot
log "Installing Certbot..."
run_remote "sudo apt-get install -y certbot python3-certbot-nginx"
log "✅ Certbot installed"

# Harden SSH configuration
log "Hardening SSH configuration..."
run_remote "sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak"
run_remote "sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
run_remote "sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config"
run_remote "sudo sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config"
run_remote "sudo sed -i 's/#LoginGraceTime 2m/LoginGraceTime 1m/' /etc/ssh/sshd_config"
run_remote "sudo sed -i 's/#ClientAliveInterval 0/ClientAliveInterval 300/' /etc/ssh/sshd_config"
run_remote "sudo sed -i 's/#ClientAliveCountMax 3/ClientAliveCountMax 2/' /etc/ssh/sshd_config"
run_remote "sudo systemctl restart sshd"
log "✅ SSH configuration hardened"

# Set up automatic security updates
log "Setting up automatic security updates..."
run_remote "sudo apt-get install -y unattended-upgrades"
run_remote "sudo dpkg-reconfigure -plow unattended-upgrades"
log "✅ Automatic security updates configured"

# Create required directories
log "Creating required directories..."
run_remote "sudo mkdir -p /var/www/wordpress"
run_remote "sudo chown -R $ADMIN_USERNAME:$ADMIN_USERNAME /var/www/wordpress"
log "✅ Required directories created"

log "✅ Server bootstrap complete"
