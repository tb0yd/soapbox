# Soapbox

A production-ready WordPress hosting solution optimized for podcast hosting, featuring automatic media offloading to AWS S3, CloudFront CDN integration, and Let's Encrypt SSL.

## 🚀 Features

- Dockerized WordPress with Nginx and PostgreSQL
- Automatic media offloading to AWS S3
- CloudFront CDN integration for global media delivery
- Let's Encrypt SSL certificates
- SSH-only access for enhanced security
- DigitalOcean-hosted Ubuntu Linux server
- Simple configuration via `secrets.yml`

## 📋 System Requirements to run setup.sh

- MacOS
- SSH
- Homebrew

## Other Requirements to run setup.sh

- SSH key pair for server access
- Registered domain name for hosting
- DigitalOcean account with API token
- AWS account with API token

## 🔑 Required Credentials

The `secrets.yml` file requires the following credentials:

### SSH Configuration
- Public and private SSH key paths
- Admin username and password

### DigitalOcean Configuration
- DigitalOcean API token (generate at https://cloud.digitalocean.com/account/api/tokens)

### Domain Configuration
- Domain name
- Domain owner email

### AWS Configuration
- AWS access key ID and secret access key
- AWS region
- S3 bucket name
- CloudFront distribution domain

### WordPress Configuration
- Site title
- Admin user credentials
- Admin email

## 🛠️ Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/your-repo/wp-s3-podcast-hosting.git
   cd wp-s3-podcast-hosting
   ```

2. Create your `secrets.yml` file with all required credentials

3. Make the setup script executable and run it:
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

4. During the process, you will be instructed to point the DNS record to your new server IP.

4. Wait for the provisioning process to complete

5. Visit your domain at `https://yourdomain.com`

## 🔒 Security Notes

- Only SSH key-based access is allowed (no password login)
- PostgreSQL port is not exposed outside Docker
- All web traffic is routed through Nginx with SSL
- AWS IAM user has limited S3 and CloudFront permissions only

## 📝 Maintenance

- To renew SSL certificates: `docker exec certbot certbot renew --dry-run`
- To redeploy: `docker-compose down && docker-compose up -d --build`
- Podcast episodes can be uploaded via WordPress media uploader or FTP to `/uploads` directory 
