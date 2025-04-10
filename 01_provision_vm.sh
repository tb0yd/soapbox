#!/bin/bash
set -euo pipefail

# WordPress Podcast Server Setup
# Script 1: Provision DigitalOcean Droplet

# Configuration
SECRETS_FILE="./secrets.yml"
LOG_FILE="./logs/01_provision.log"
SERVER_IP_FILE="./server_ip.txt"
DROPLET_NAME="soapbox-$(date +%s)"
DROPLET_REGION="nyc3"
DROPLET_SIZE="s-2vcpu-4gb"
DROPLET_IMAGE="ubuntu-22-04-x64"
SSH_KEY_NAME="soapbox-$(date +%s)"
ADMIN_USER="admin"

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

# Function to validate DigitalOcean resources
validate_do_resources() {
  log "Validating DigitalOcean resources..."
  
  # Check if region exists (case-insensitive)
  if ! doctl compute region list --format Slug --no-header | grep -i "^$DROPLET_REGION$" > /dev/null; then
    log "❌ Invalid region: $DROPLET_REGION"
    log "Available regions:"
    doctl compute region list --format Slug,Name
    exit 1
  fi
  
  # Check if size exists (case-insensitive)
  if ! doctl compute size list --format Slug --no-header | grep -i "^$DROPLET_SIZE$" > /dev/null; then
    log "❌ Invalid size: $DROPLET_SIZE"
    log "Available sizes:"
    doctl compute size list --format Slug,Memory,VCPUs,Disk
    exit 1
  fi
  
  # Check if image exists using a different approach
  if ! doctl compute image list --public --format Slug,Name | grep -i "ubuntu.*22.04.*x64" > /dev/null; then
    log "❌ Invalid image: $DROPLET_IMAGE"
    log "Available Ubuntu 22.04 images:"
    doctl compute image list --public --format Slug,Name | grep -i "ubuntu.*22.04"
    exit 1
  fi
  
  log "✅ All DigitalOcean resources validated"
}

# Check if secrets.yml exists
if [ ! -f "$SECRETS_FILE" ]; then
  log "❌ Error: secrets.yml file not found!"
  exit 1
fi

# Extract DigitalOcean credentials from secrets.yml
DO_TOKEN=$(get_secret '.digitalocean.token')
SSH_PUBLIC_KEY_PATH=$(get_secret '.ssh.public_key_path')
DOMAIN_NAME=$(get_secret '.domain.name')

# Use the ADMIN_USER variable defined at the top
ADMIN_USERNAME="$ADMIN_USER"

# Expand ~ in path if present
SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH/#\~/$HOME}"

# Verify SSH key exists
log "Checking SSH public key at $SSH_PUBLIC_KEY_PATH..."
if [ ! -f "$SSH_PUBLIC_KEY_PATH" ]; then
  log "❌ SSH public key not found at $SSH_PUBLIC_KEY_PATH"
  log "Please ensure your SSH key exists or update the path in secrets.yml"
  exit 1
fi
log "✅ Found SSH public key"

# Read SSH key content
SSH_KEY_CONTENT=$(cat "$SSH_PUBLIC_KEY_PATH")
if [ -z "$SSH_KEY_CONTENT" ]; then
  log "❌ SSH public key is empty"
  exit 1
fi
log "✅ SSH public key content read successfully"

# Check if doctl is installed
if ! command -v doctl &> /dev/null; then
  log "Installing DigitalOcean CLI (doctl)..."
  
  # Detect OS and architecture
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)
  
  # Map architecture to doctl's naming convention
  case $ARCH in
    x86_64) ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) log "❌ Unsupported architecture: $ARCH"; exit 1 ;;
  esac
  
  # Download and install doctl
  DOCTL_VERSION="1.94.0"
  DOCTL_URL="https://github.com/digitalocean/doctl/releases/download/v${DOCTL_VERSION}/doctl-${DOCTL_VERSION}-${OS}-${ARCH}.tar.gz"
  
  curl -L "$DOCTL_URL" | tar xz
  sudo mv doctl /usr/local/bin/
  log "✅ doctl installed successfully"
fi

# Authenticate with DigitalOcean
log "Authenticating with DigitalOcean..."
doctl auth init -t "$DO_TOKEN"

# Validate DigitalOcean resources
validate_do_resources

check_existing_droplet() {
    log "Checking if droplet already exists..."
    local droplet_list=$(doctl compute droplet list --format ID,Name --no-header)
    log "Droplet list output: $droplet_list"
    
    if echo "$droplet_list" | grep -q "$DROPLET_NAME"; then
        local existing_id=$(echo "$droplet_list" | grep "$DROPLET_NAME" | awk '{print $1}')
        log "Found existing droplet with ID: $existing_id"
        
        read -p "❓ Existing droplet found. Would you like to delete it and create a new one? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Deleting existing droplet..."
            if doctl compute droplet delete $existing_id -f; then
                log "✅ Existing droplet deleted successfully"
                # Wait for the droplet to be fully deleted
                sleep 10
                return 0
            else
                log "❌ Failed to delete existing droplet"
                return 1
            fi
        else
            log "❌ Aborting due to existing droplet"
            return 1
        fi
    fi
    
    log "No existing droplet found, proceeding with creation..."
    return 0
}

# Main script execution
validate_do_resources || exit 1
check_existing_droplet || exit 1

# Check if SSH key exists in DigitalOcean
log "Finding SSH key in DigitalOcean..."

# List all keys
SSH_KEYS_LIST=$(doctl compute ssh-key list --format ID,Name,FingerPrint --no-header)
log "Existing SSH keys: $SSH_KEYS_LIST"

# Use the first key found
SSH_KEY_ID=$(echo "$SSH_KEYS_LIST" | head -n 1 | awk '{print $1}')

if [ -z "$SSH_KEY_ID" ]; then
  log "❌ No SSH keys found in DigitalOcean account"
  exit 1
fi

log "✅ Using SSH key with ID: $SSH_KEY_ID"

# Create droplet
log "Creating droplet $DROPLET_NAME..."
log "Running: doctl compute droplet create $DROPLET_NAME --size $DROPLET_SIZE --region $DROPLET_REGION --image $DROPLET_IMAGE --ssh-keys $SSH_KEY_ID --wait"

# Create droplet with detailed error handling
DROPLET_CREATE_OUTPUT=$(doctl compute droplet create "$DROPLET_NAME" \
  --size "$DROPLET_SIZE" \
  --region "$DROPLET_REGION" \
  --image "$DROPLET_IMAGE" \
  --ssh-keys "$SSH_KEY_ID" \
  --wait 2>&1)

DROPLET_CREATE_STATUS=$?
log "Droplet creation status: $DROPLET_CREATE_STATUS"
log "Droplet creation output: $DROPLET_CREATE_OUTPUT"

if [ $DROPLET_CREATE_STATUS -ne 0 ]; then
  log "❌ Failed to create droplet"
  log "Error output: $DROPLET_CREATE_OUTPUT"
  
  # Check if droplet was partially created
  if echo "$DROPLET_CREATE_OUTPUT" | grep -q "already exists"; then
    log "⚠️ Droplet may already exist, checking..."
    DROPLET_ID=$(doctl compute droplet list --format ID,Name --no-header | grep "$DROPLET_NAME" | awk '{print $1}')
    if [ -n "$DROPLET_ID" ]; then
      log "✅ Found existing droplet with ID: $DROPLET_ID"
      PUBLIC_IP=$(doctl compute droplet get "$DROPLET_ID" --format PublicIPv4 --no-header)
      if [ -n "$PUBLIC_IP" ]; then
        log "✅ Found public IP: $PUBLIC_IP"
        echo "$PUBLIC_IP" > "$SERVER_IP_FILE"
        log "✅ Saved IP to $SERVER_IP_FILE"
        exit 0
      fi
    fi
  fi
  
  exit 1
fi

log "✅ Droplet creation command completed successfully"

# Get the public IP address
log "Getting droplet IP..."
PUBLIC_IP=$(doctl compute droplet get "$DROPLET_NAME" --format PublicIPv4 --no-header)

if [ -z "$PUBLIC_IP" ]; then
  log "❌ Failed to get droplet IP"
  log "Attempting to get IP from droplet list..."
  PUBLIC_IP=$(doctl compute droplet list --format Name,PublicIPv4 --no-header | grep "$DROPLET_NAME" | awk '{print $2}')
  
  if [ -z "$PUBLIC_IP" ]; then
    log "❌ Could not find IP in droplet list either"
    exit 1
  fi
fi

log "✅ Droplet created with public IP: $PUBLIC_IP"

# Save the IP to a file for other scripts to use
echo "$PUBLIC_IP" > "$SERVER_IP_FILE"
log "✅ Saved IP to $SERVER_IP_FILE"

# Ensure we're using the private key corresponding to the public key
SSH_PRIVATE_KEY_PATH="${SSH_PUBLIC_KEY_PATH%.pub}"

# Validate SSH key permissions
if [ -f "$SSH_PRIVATE_KEY_PATH" ]; then
    current_perms=$(stat -f "%Lp" "$SSH_PRIVATE_KEY_PATH")
    if [ "$current_perms" != "600" ]; then
        log "Fixing SSH private key permissions..."
        chmod 600 "$SSH_PRIVATE_KEY_PATH"
    fi
else
    log "❌ Private key file not found at $SSH_PRIVATE_KEY_PATH"
    exit 1
fi

wait_for_ssh() {
    local ip=$1
    local max_attempts=30
    local attempt=1
    local ssh_output=""
    
    log "Waiting for SSH to be available..."
    
    while [ $attempt -le $max_attempts ]; do
        log "Waiting for SSH... (attempt $attempt/$max_attempts)"
        
        # Try to connect with verbose output for debugging
        ssh_output=$(ssh -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -v root@$ip "echo 'SSH connection successful'" 2>&1)
        local ssh_status=$?
        
        if [ $ssh_status -eq 0 ]; then
            log "✅ SSH connection established successfully"
            return 0
        fi
        
        # Log SSH debug output if connection failed
        if [ $attempt -eq 1 ] || [ $attempt -eq 15 ] || [ $attempt -eq 30 ]; then
            log "SSH debug output: $ssh_output"
        fi
        
        # Check if droplet is still active
        local droplet_status=$(doctl compute droplet get $DROPLET_NAME --format Status --no-header 2>/dev/null)
        if [ "$droplet_status" != "active" ]; then
            log "❌ Droplet is not in active state. Current status: $droplet_status"
            return 1
        fi
        
        sleep 15
        attempt=$((attempt + 1))
    done
    
    log "❌ Timed out waiting for SSH to be available"
    log "Last SSH attempt output: $ssh_output"
    return 1
}

if ! wait_for_ssh "$PUBLIC_IP"; then
  exit 1
fi

# Create admin user and set up SSH access
log "Setting up admin user..."
ssh -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$PUBLIC_IP" << EOF
    set -e
    # Create admin user if it doesn't exist
    if ! id -u "$ADMIN_USERNAME" >/dev/null 2>&1; then
        useradd -m -s /bin/bash -g admin "$ADMIN_USERNAME"
        # Set up sudo access
        usermod -aG sudo "$ADMIN_USERNAME"
    fi
    
    # Set up SSH directory
    mkdir -p "/home/$ADMIN_USERNAME/.ssh"
    echo "$(cat $SSH_PUBLIC_KEY_PATH)" > "/home/$ADMIN_USERNAME/.ssh/authorized_keys"
    chown -R "$ADMIN_USERNAME:admin" "/home/$ADMIN_USERNAME/.ssh"
    chmod 700 "/home/$ADMIN_USERNAME/.ssh"
    chmod 600 "/home/$ADMIN_USERNAME/.ssh/authorized_keys"
    
    # Set up password-less sudo for admin user
    echo "$ADMIN_USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$ADMIN_USERNAME"
    chmod 440 "/etc/sudoers.d/$ADMIN_USERNAME"
    
    # Disable root SSH access
    sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl restart sshd
EOF

if [ $? -eq 0 ]; then
    log "✅ Admin user setup complete"
else
    log "❌ Failed to set up admin user"
    exit 1
fi

log "✅ Droplet provisioning complete"
log "⚠️ Note: You need to manually set up DNS A record for $DOMAIN_NAME pointing to $PUBLIC_IP"
