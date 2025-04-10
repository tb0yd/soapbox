#!/bin/bash
set -euo pipefail

# WordPress Podcast Server Setup
# Main orchestration script

# Create logs directory
mkdir -p logs

# Script locations
PROVISION_SCRIPT="./01_provision_vm.sh"
BOOTSTRAP_SCRIPT="./02_bootstrap_server.sh"
SERVER_IP_FILE="./server_ip.txt"
DEPLOY_SCRIPT="./03_deploy_wordpress.sh"
CONFIGURE_SCRIPT="./04_configure_wordpress.sh"
SECRETS_FILE="./secrets.yml"

# Check if secrets.yml exists
if [ ! -f "$SECRETS_FILE" ]; then
  echo "❌ Error: secrets.yml file not found!"
  echo "Please create a secrets.yml file with your configuration before running this script."
  exit 1
fi

# Function to print section headers
print_header() {
  echo ""
  echo "🚀 $1"
  echo "========================================"
}

# Function to check if a script exists and is executable
check_script() {
  if [ ! -f "$1" ]; then
    echo "❌ Error: Script $1 not found!"
    exit 1
  fi
  
  if [ ! -x "$1" ]; then
    echo "Making $1 executable..."
    chmod +x "$1"
  fi
}

# Check all scripts
check_script "$PROVISION_SCRIPT"
check_script "$BOOTSTRAP_SCRIPT"
check_script "$DEPLOY_SCRIPT"
check_script "$CONFIGURE_SCRIPT"

# 1. Provision Azure VM
print_header "PHASE 1: Provisioning Azure VM"
$PROVISION_SCRIPT

# Check if server_ip.txt was created by the provision script
if [ ! -f "$SERVER_IP_FILE" ]; then
  echo "❌ Error: Server IP file not found after provisioning!"
  exit 1
fi

SERVER_IP=$(cat "$SERVER_IP_FILE")
echo "✅ Server provisioned with IP: $SERVER_IP"

# 2. Bootstrap Server
print_header "PHASE 2: Bootstrapping Server"
$BOOTSTRAP_SCRIPT

# 3. Deploy WordPress
print_header "PHASE 3: Deploying WordPress"
$DEPLOY_SCRIPT

# 4. Configure WordPress
print_header "PHASE 4: Configuring WordPress"
$CONFIGURE_SCRIPT

# Final message
print_header "DEPLOYMENT COMPLETE"
DOMAIN=$(grep -A1 "domain:" "$SECRETS_FILE" | grep "name:" | awk '{print $2}')
echo "✅ WordPress Podcast Server has been successfully deployed!"
echo "🌐 You can access your site at: https://$DOMAIN"
echo ""
echo "📝 Login credentials can be found in your secrets.yml file"
echo "🔒 Remember to keep your secrets.yml file secure!"
