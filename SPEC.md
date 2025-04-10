# ✅ WordPress Podcast Hosting Stack - Project Spec

## 📌 Overview

This project provides a **one-command deployment** of a production-grade WordPress server with:

- **Dockerized WordPress + Nginx + PostgreSQL**
- **Automatic media offloading to AWS S3**
- **CloudFront CDN integration**
- **Let's Encrypt SSL**
- **SSH-only access (no password login)**
- **Azure-hosted Ubuntu Linux slice**
- Beginner-friendly setup with all config managed through a single `secrets.yml` file

---

## 🗂 Project Structure

```
.
├── docker-compose.yml
├── Dockerfile
├── nginx/
│   └── wordpress.conf
├── certbot/
│   └── init-letsencrypt.sh
├── secrets.yml            # User-supplied secrets and credentials
├── setup.sh               # Azure & server bootstrap script
├── README.md
```

---

## 🔐 `secrets.yml` Format

```yaml
ssh:
  public_key_path: ~/.ssh/id_rsa.pub
  private_key_path: ~/.ssh/id_rsa
  admin_username: admin
  admin_password: strong-unix-password

azure:
  subscription_id: YOUR_AZURE_SUBSCRIPTION_ID
  tenant_id: YOUR_AZURE_TENANT_ID
  client_id: YOUR_AZURE_CLIENT_ID
  client_secret: YOUR_AZURE_CLIENT_SECRET
  region: eastus

domain:
  name: yourdomain.com
  owner_email: you@example.com

aws:
  access_key_id: YOUR_AWS_ACCESS_KEY_ID
  secret_access_key: YOUR_AWS_SECRET_ACCESS_KEY
  region: us-east-1
  s3_bucket: your-podcast-media
  cloudfront_domain: YOUR_CLOUDFRONT_DISTRIBUTION_DOMAIN

wordpress:
  site_title: "My Podcast Site"
  admin_user: admin
  admin_password: admin_secure_password
  admin_email: admin@example.com
```

---

## 🛠 Features & Tools

| Component     | Purpose                                     |
|---------------|---------------------------------------------|
| Docker        | Isolated app containers                     |
| Nginx         | Web server + reverse proxy + SSL            |
| PostgreSQL    | WordPress database                          |
| Big File Uploads | Upload large podcast episodes easily    |
| Media Cloud   | Offload media to S3                         |
| CloudFront    | Serve media files globally via CDN          |
| Certbot       | Auto-SSL using Let's Encrypt                |
| Azure VM      | Ubuntu slice to host your Docker stack      |

---

## 🛡️ Security Model

- Only SSH key-based access (no passwords accepted)
- `admin` is the only system user (with sudo access)
- PostgreSQL port **not exposed** outside Docker
- All external web traffic is routed through Nginx and secured with SSL
- AWS IAM user only has S3 + CloudFront permissions

---

## ⚙️ Automation

The project includes:

- `setup.sh`: provisions Azure VM, installs Docker & Docker Compose, copies secrets, and boots containers.
- `certbot/init-letsencrypt.sh`: automatically issues and installs Let's Encrypt certs.
- `docker-compose.yml`: spins up Nginx, WordPress, PostgreSQL, and Certbot.
- CloudFront and S3 setup instructions are provided via AWS CLI and Terraform templates (optional).

---

## 🚀 Deployment Steps (Mac or Windows WSL)

1. **Clone the Repo**:
   ```bash
   git clone https://github.com/your-repo/wp-s3-podcast-hosting.git
   cd wp-s3-podcast-hosting
   ```

2. **Create Your `secrets.yml`**:
   Fill out your credentials and info in `secrets.yml`.

3. **Run the Setup Script**:
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

4. **Wait 5–10 minutes** for provisioning, Docker boot-up, and SSL issuance.

5. **Done!** Visit your domain: `https://yourdomain.com`

---

## 🪄 What the Script Does

- Authenticates with Azure and provisions a VM
- Adds your SSH key to the server
- Installs Docker, Docker Compose, UFW (firewall), and Certbot
- Sets up firewall: only ports 22, 80, 443 allowed
- Copies over all config and secrets
- Spins up the full WordPress stack
- Requests SSL via Certbot and reloads Nginx
- Pre-configures WordPress with your admin credentials
- Connects Media Cloud to AWS S3 + CloudFront via plugin CLI/API

---

## ✅ Requirements

- Docker & Docker Compose installed locally
- Azure CLI installed & logged in
- AWS IAM credentials with S3 + CloudFront permissions
- A registered domain pointed to your Azure VM IP

---

## 📝 Notes

- To rotate SSL certificates: `docker exec certbot certbot renew --dry-run`
- To manually re-deploy: `docker-compose down && docker-compose up -d --build`
- To upload podcast episodes: use WordPress media uploader or FTP to the `/uploads` dir

---

## 🔒 Future Enhancements (Optional)

- Terraform module for Azure VM provisioning
- Fail2Ban for brute-force protection
- Email notifications for cert renewals