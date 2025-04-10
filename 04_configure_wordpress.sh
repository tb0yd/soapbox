#!/bin/bash
set -euo pipefail

# WordPress Podcast Server Setup
# Script 4: Configure WordPress

# Configuration
SECRETS_FILE="./secrets.yml"
LOG_FILE="./logs/04_configure.log"
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

# Extract SSH credentials and WordPress settings from secrets.yml
SSH_PRIVATE_KEY_PATH=$(get_secret '.ssh.private_key_path')
ADMIN_USERNAME=$(get_secret '.ssh.admin_username')
DOMAIN_NAME=$(get_secret '.domain.name')
WP_SITE_TITLE=$(get_secret '.wordpress.site_title')
WP_ADMIN_USER=$(get_secret '.wordpress.admin_user')
WP_ADMIN_PASSWORD=$(get_secret '.wordpress.admin_password')
WP_ADMIN_EMAIL=$(get_secret '.wordpress.admin_email')

# AWS credentials
AWS_ACCESS_KEY=$(get_secret '.aws.access_key_id')
AWS_SECRET_KEY=$(get_secret '.aws.secret_access_key')
AWS_REGION=$(get_secret '.aws.region')
S3_BUCKET=$(get_secret '.aws.s3_bucket')
CLOUDFRONT_DOMAIN=$(get_secret '.aws.cloudfront_domain')

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

# Function to run WP-CLI commands
run_wp_cli() {
  run_remote "cd ~/wordpress && docker-compose exec -T wordpress wp $1 --allow-root"
}

# Wait for WordPress to be ready
log "Waiting for WordPress to be ready..."
for i in {1..30}; do
  if run_remote "curl -s http://localhost/wp-admin/install.php | grep -q 'already installed'"; then
    log "✅ WordPress is already installed"
    WORDPRESS_INSTALLED=true
    break
  elif run_remote "curl -s http://localhost/wp-admin/install.php | grep -q 'information needed'"; then
    log "WordPress installation page is available"
    WORDPRESS_INSTALLED=false
    break
  fi
  
  if [ $i -eq 30 ]; then
    log "❌ Timed out waiting for WordPress to be ready"
    exit 1
  fi
  
  log "Waiting for WordPress... (attempt $i/30)"
  sleep 10
done

# Check if WordPress is already configured
log "Checking if WordPress is already configured..."
WP_CONFIGURED=$(run_wp_cli "core is-installed" || echo "no")
if [ "$WP_CONFIGURED" == "no" ]; then
  log "WordPress is not configured. Running installation..."
  
  # Install WordPress
  log "Installing WordPress..."
  run_wp_cli "core install --url=https://${DOMAIN_NAME} --title='${WP_SITE_TITLE}' --admin_user=${WP_ADMIN_USER} --admin_password=${WP_ADMIN_PASSWORD} --admin_email=${WP_ADMIN_EMAIL}"
  
  # Update permalink structure
  log "Setting permalink structure..."
  run_wp_cli "rewrite structure '/%postname%/'"
  
  log "✅ WordPress core installed successfully"
else
  log "✅ WordPress is already installed"
fi

# Install and activate required plugins
log "Installing and activating required plugins..."

# Check if Big File Uploads plugin is installed
BFU_INSTALLED=$(run_wp_cli "plugin is-installed big-file-uploads" || echo "no")
if [ "$BFU_INSTALLED" == "no" ]; then
  log "Installing Big File Uploads plugin..."
  run_wp_cli "plugin install big-file-uploads --activate"
  log "✅ Big File Uploads plugin installed and activated"
else
  log "✅ Big File Uploads plugin is already installed"
  
  # Activate if not already active
  BFU_ACTIVE=$(run_wp_cli "plugin is-active big-file-uploads" || echo "no")
  if [ "$BFU_ACTIVE" == "no" ]; then
    run_wp_cli "plugin activate big-file-uploads"
    log "✅ Big File Uploads plugin activated"
  fi
fi

# Check if Media Cloud plugin is installed
MC_INSTALLED=$(run_wp_cli "plugin is-installed ilab-media-tools" || echo "no")
if [ "$MC_INSTALLED" == "no" ]; then
  log "Installing Media Cloud plugin..."
  run_wp_cli "plugin install ilab-media-tools --activate"
  log "✅ Media Cloud plugin installed and activated"
else
  log "✅ Media Cloud plugin is already installed"
  
  # Activate if not already active
  MC_ACTIVE=$(run_wp_cli "plugin is-active ilab-media-tools" || echo "no")
  if [ "$MC_ACTIVE" == "no" ]; then
    run_wp_cli "plugin activate ilab-media-tools"
    log "✅ Media Cloud plugin activated"
  fi
fi

# Configure Media Cloud with AWS S3 and CloudFront
log "Configuring Media Cloud with AWS S3 and CloudFront..."

# Create Media Cloud configuration file
cat > media-cloud-config.json << EOF
{
  "storage": {
    "provider": "s3",
    "s3": {
      "access-key": "${AWS_ACCESS_KEY}",
      "secret": "${AWS_SECRET_KEY}",
      "bucket": "${S3_BUCKET}",
      "region": "${AWS_REGION}"
    }
  },
  "imgix": {
    "enabled": false
  },
  "cdn": {
    "enabled": true,
    "provider": "cloudfront",
    "cloudfront": {
      "domain": "${CLOUDFRONT_DOMAIN}"
    }
  },
  "upload-handling": {
    "enabled": true,
    "upload-direct": true
  }
}
EOF

# Copy configuration file to server
log "Copying Media Cloud configuration to server..."
scp -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null media-cloud-config.json "$ADMIN_USERNAME@$SERVER_IP:~/media-cloud-config.json"

# Import configuration
log "Importing Media Cloud configuration..."
run_remote "cd ~/wordpress && docker-compose exec -T wordpress wp media-cloud:settings import ~/media-cloud-config.json --allow-root"

# Clean up configuration file
rm -f media-cloud-config.json
run_remote "rm -f ~/media-cloud-config.json"

# Configure upload limits
log "Configuring upload limits..."
run_remote "cd ~/wordpress && docker-compose exec -T wordpress bash -c 'echo \"upload_max_filesize = 500M\npost_max_size = 500M\nmax_execution_time = 300\nmemory_limit = 512M\" > /usr/local/etc/php/conf.d/uploads.ini'"

# Restart WordPress container to apply PHP settings
log "Restarting WordPress container to apply settings..."
run_remote "cd ~/wordpress && docker-compose restart wordpress"

# Set up cron job for WordPress
log "Setting up WordPress cron job..."
CRON_JOB="*/5 * * * * cd ~/wordpress && docker-compose exec -T wordpress php /var/www/html/wp-cron.php > /dev/null 2>&1"
CRON_EXISTS=$(run_remote "crontab -l 2>/dev/null | grep -q 'wp-cron.php' && echo 'yes' || echo 'no'")
if [ "$CRON_EXISTS" == "no" ]; then
  run_remote "(crontab -l 2>/dev/null; echo \"$CRON_JOB\") | crontab -"
  log "✅ WordPress cron job added"
else
  log "✅ WordPress cron job already exists"
fi

# Test upload functionality
log "Testing upload functionality..."
run_remote "cd ~/wordpress && docker-compose exec -T wordpress wp media import https://sample-videos.com/audio/mp3/crowd-cheering.mp3 --allow-root"
UPLOAD_SUCCESS=$?
if [ $UPLOAD_SUCCESS -eq 0 ]; then
  log "✅ Test upload successful"
else
  log "⚠️ Test upload failed. Please check Media Cloud configuration manually."
fi

log "✅ WordPress configuration complete"
log "🌐 Your WordPress Podcast Server is now ready at https://${DOMAIN_NAME}"
log "🔑 Login with username: ${WP_ADMIN_USER} and your configured password"
