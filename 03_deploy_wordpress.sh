#!/bin/bash
set -euo pipefail

# WordPress Podcast Server Setup
# Script 3: Deploy WordPress

# Configuration
SECRETS_FILE="./secrets.yml"
LOG_FILE="./logs/03_deploy.log"
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

# Extract SSH credentials and domain from secrets.yml
SSH_PRIVATE_KEY_PATH=$(get_secret '.ssh.private_key_path')
ADMIN_USERNAME=$(get_secret '.ssh.admin_username')
DOMAIN_NAME=$(get_secret '.domain.name')
DOMAIN_EMAIL=$(get_secret '.domain.owner_email')

# WordPress database credentials
DB_NAME="wordpress"
DB_USER="wordpress"
DB_PASSWORD=$(get_secret '.wordpress.admin_password')_db
DB_ROOT_PASSWORD=$(get_secret '.wordpress.admin_password')_root

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

# Function to copy files to the remote server
copy_to_remote() {
  scp -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$1" "$ADMIN_USERNAME@$SERVER_IP:$2"
}

# Function to verify DNS propagation
verify_dns() {
  local domain=$1
  local expected_ip=$2
  local current_ip
  
  log "Verifying DNS for $domain..."
  
  # Try multiple DNS servers for robustness
  for dns_server in "8.8.8.8" "1.1.1.1" "8.8.4.4"; do
    current_ip=$(dig @$dns_server +short $domain | head -n1)
    if [ "$current_ip" == "$expected_ip" ]; then
      log "✅ DNS verified for $domain (points to $expected_ip)"
      return 0
    fi
  done
  
  log "❌ DNS verification failed for $domain"
  log "Expected IP: $expected_ip"
  log "Current IP: $current_ip"
  log "Please update your DNS records to point $domain to $expected_ip"
  return 1
}

# Verify DNS before proceeding
if ! verify_dns "$DOMAIN_NAME" "$SERVER_IP"; then
  log "❌ DNS verification failed. Please update your DNS records and try again."
  exit 1
fi

if ! verify_dns "www.$DOMAIN_NAME" "$SERVER_IP"; then
  log "❌ DNS verification failed for www.$DOMAIN_NAME. Please update your DNS records and try again."
  exit 1
fi

# Check if Docker containers are already running
log "Checking if WordPress containers are already running..."
CONTAINERS_RUNNING=$(run_remote "docker ps | grep -q wordpress && echo 'yes' || echo 'no'")
if [ "$CONTAINERS_RUNNING" == "yes" ]; then
  log "✅ WordPress containers are already running"
  
  # Check if we need to update the configuration
  log "Checking if configuration update is needed..."
  # This is a placeholder for checking if config needs updating
  # In a real scenario, you might compare file hashes or timestamps
  
  UPDATE_NEEDED="no"
  if [ "$UPDATE_NEEDED" == "yes" ]; then
    log "Updating Docker configuration..."
    # Update configuration logic would go here
  else
    log "✅ No configuration update needed"
  fi
else
  # Create necessary directories on the server
  log "Creating necessary directories..."
  run_remote "mkdir -p ~/wordpress"
  run_remote "mkdir -p ~/wordpress/nginx"
  run_remote "mkdir -p ~/wordpress/certbot"
  run_remote "mkdir -p ~/wordpress/postgres"
  run_remote "mkdir -p ~/wordpress/wordpress"
  
  # Create docker-compose.yml file
  log "Creating docker-compose.yml file..."
  cat > docker-compose.yml << EOF
version: '3'

services:
  db:
    image: postgres:14
    volumes:
      - ./postgres:/var/lib/postgresql/data
    restart: always
    environment:
      POSTGRES_PASSWORD: ${DB_ROOT_PASSWORD}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_DB: ${DB_NAME}
    networks:
      - wordpress

  wordpress:
    image: wordpress:latest
    depends_on:
      - db
    volumes:
      - ./wordpress:/var/www/html
    restart: always
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: ${DB_USER}
      WORDPRESS_DB_PASSWORD: ${DB_ROOT_PASSWORD}
      WORDPRESS_DB_NAME: ${DB_NAME}
      WORDPRESS_CONFIG_EXTRA: |
        define('WP_MEMORY_LIMIT', '256M');
        define('WP_MAX_MEMORY_LIMIT', '512M');
        define('FS_METHOD', 'direct');
    networks:
      - wordpress

  nginx:
    image: nginx:latest
    depends_on:
      - wordpress
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx:/etc/nginx/conf.d
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
      - ./wordpress:/var/www/html
    restart: always
    networks:
      - wordpress

  certbot:
    image: certbot/certbot
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    networks:
      - wordpress

networks:
  wordpress:
EOF

  # Create Nginx configuration file
  log "Creating Nginx configuration file..."
  cat > nginx.conf << EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};
    
    ssl_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    
    # Improve HTTPS performance with session resumption
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    
    # Enable HSTS
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    
    # Other security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";
    
    # Root directory and index
    root /var/www/html;
    index index.php;
    
    # WordPress permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    # Pass PHP scripts to FastCGI server
    location ~ \.php$ {
        fastcgi_pass wordpress:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }
    
    # Deny access to .htaccess files
    location ~ /\.ht {
        deny all;
    }
    
    # Media files caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|mp3|mp4|webm|ogg)$ {
        expires 365d;
        add_header Cache-Control "public, max-age=31536000";
    }
    
    # Increase max upload size
    client_max_body_size 500M;
}
EOF

  # Create init-letsencrypt.sh script
  log "Creating init-letsencrypt.sh script..."
  cat > init-letsencrypt.sh << EOF
#!/bin/bash

domains=(${DOMAIN_NAME} www.${DOMAIN_NAME})
email="${DOMAIN_EMAIL}"
staging=0 # Set to 1 if you're testing your setup

if [ -d "./certbot/conf/live/${DOMAIN_NAME}" ]; then
  echo "Certificates already exist, skipping..."
  exit 0
fi

echo "Creating dummy certificates..."
mkdir -p "./certbot/conf/live/${DOMAIN_NAME}"
docker-compose run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:4096 -days 1\
    -keyout '/etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem' \
    -out '/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem' \
    -subj '/CN=localhost'" certbot

echo "Starting nginx..."
docker-compose up -d nginx

echo "Removing dummy certificates..."
docker-compose run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/${DOMAIN_NAME} && \
  rm -Rf /etc/letsencrypt/archive/${DOMAIN_NAME} && \
  rm -Rf /etc/letsencrypt/renewal/${DOMAIN_NAME}.conf" certbot

echo "Requesting Let's Encrypt certificates..."
domain_args=""
for domain in "\${domains[@]}"; do
  domain_args="\$domain_args -d \$domain"
done

# Add staging flag if needed
staging_arg=""
if [ \$staging -eq 1 ]; then
  staging_arg="--staging"
fi

docker-compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    \$domain_args \
    --email \$email \
    --agree-tos \
    --no-eff-email \
    --force-renewal \
    \$staging_arg" certbot

if [ \$? -eq 0 ]; then
  echo "Reloading nginx..."
  docker-compose exec nginx nginx -s reload
else
  echo "Failed to obtain certificates. Check the logs for details."
  exit 1
fi
EOF

  # Copy files to the server
  log "Copying files to the server..."
  copy_to_remote "docker-compose.yml" "~/wordpress/"
  copy_to_remote "nginx.conf" "~/wordpress/nginx/default.conf"
  copy_to_remote "init-letsencrypt.sh" "~/wordpress/certbot/"
  
  # Make init-letsencrypt.sh executable
  run_remote "chmod +x ~/wordpress/certbot/init-letsencrypt.sh"
  
  # Start Docker containers
  log "Starting Docker containers..."
  run_remote "cd ~/wordpress && docker-compose up -d"
  
  # Wait for containers to be healthy
  log "Waiting for containers to be healthy..."
  run_remote "cd ~/wordpress && docker-compose ps"
  
  # Run Let's Encrypt initialization script
  log "Running Let's Encrypt initialization script..."
  run_remote "cd ~/wordpress && ./certbot/init-letsencrypt.sh"
  
  # Clean up temporary files
  log "Cleaning up temporary files..."
  rm -f docker-compose.yml nginx.conf init-letsencrypt.sh
  
  log "✅ WordPress deployed successfully"
fi

# Check if SSL certificates exist and are valid
log "Checking SSL certificates..."
SSL_EXISTS=$(run_remote "[ -d ~/wordpress/certbot/conf/live/${DOMAIN_NAME} ] && echo 'yes' || echo 'no'")
if [ "$SSL_EXISTS" == "yes" ]; then
  log "✅ SSL certificates exist"
  
  # Check certificate expiration
  EXPIRY_DATE=$(run_remote "docker-compose exec -T certbot certbot certificates | grep 'Expiry Date' | head -1 | awk '{print \$3, \$4, \$5, \$6}'")
  log "Certificate expires on: $EXPIRY_DATE"
else
  log "⚠️ SSL certificates not found. Running Let's Encrypt initialization script..."
  run_remote "cd ~/wordpress && ./certbot/init-letsencrypt.sh"
fi

# Function to print DNS instructions
print_dns_instructions() {
  echo "📝 DNS Configuration Required:"
  echo "----------------------------------------"
  echo "Add the following A records in your DNS provider:"
  echo "1. Create an A record for ${DOMAIN_NAME} pointing to ${SERVER_IP}"
  echo "2. Create an A record for www.${DOMAIN_NAME} pointing to ${SERVER_IP}"
  echo ""
  echo "Example DNS records:"
  echo "Type: A"
  echo "Name: @ (or ${DOMAIN_NAME})"
  echo "Value: ${SERVER_IP}"
  echo "TTL: 3600 (or your provider's default)"
  echo ""
  echo "Type: A"
  echo "Name: www"
  echo "Value: ${SERVER_IP}"
  echo "TTL: 3600 (or your provider's default)"
  echo "----------------------------------------"
  echo "Note: DNS changes may take up to 24 hours to propagate,"
  echo "but usually complete within 1-2 hours."
}

# Print DNS instructions at the end
print_dns_instructions

log "✅ WordPress deployment complete"
