#!/bin/bash

domains=(propellers.io www.propellers.io)
email="tyler@propellers.io"
staging=0 # Set to 1 if you're testing your setup

if [ -d "./certbot/conf/live/propellers.io" ]; then
  echo "Certificates already exist, skipping..."
  exit 0
fi

echo "Creating dummy certificates..."
mkdir -p "./certbot/conf/live/propellers.io"
docker-compose run --rm --entrypoint "  openssl req -x509 -nodes -newkey rsa:4096 -days 1    -keyout '/etc/letsencrypt/live/propellers.io/privkey.pem'     -out '/etc/letsencrypt/live/propellers.io/fullchain.pem'     -subj '/CN=localhost'" certbot

echo "Starting nginx..."
docker-compose up -d nginx

echo "Removing dummy certificates..."
docker-compose run --rm --entrypoint "  rm -Rf /etc/letsencrypt/live/propellers.io &&   rm -Rf /etc/letsencrypt/archive/propellers.io &&   rm -Rf /etc/letsencrypt/renewal/propellers.io.conf" certbot

echo "Requesting Let's Encrypt certificates..."
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

docker-compose run --rm --entrypoint "  certbot certonly --webroot -w /var/www/certbot     $domain_args     --email $email     --agree-tos     --no-eff-email     --force-renewal" certbot

echo "Reloading nginx..."
docker-compose exec nginx nginx -s reload
