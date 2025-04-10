# setup.sh project

## 🧱 Overall Structure

```
setup.sh
├── 01_provision_vm.sh         # Provision Azure VM, SSH config, DNS
├── 02_bootstrap_server.sh     # Install Docker, Compose, UFW, Certbot, system setup
├── 03_deploy_wordpress.sh     # Copy Docker files, secrets, and start containers
├── 04_configure_wordpress.sh  # Finalize WP setup, Media Cloud, SSL, cron, etc.
```

Each sub-script should be executable on its own and safely re-runnable.

---

## 🧾 1. `01_provision_vm.sh` — Provision Azure VM

**Goal**: Create the Azure VM, add the SSH key, associate public IP, point domain.

**Guard Clause Ideas**:
- Check if VM with same name already exists via Azure CLI
- Check if SSH public key is already authorized on the instance

**Steps**:
- Authenticate with Azure CLI
- Create resource group and VM using secrets
- Attach public IP
- Add SSH public key to `~/.ssh/authorized_keys`
- Optionally: set DNS A record if domain registrar allows API access (Cloudflare, etc.)

---

## 🧾 2. `02_bootstrap_server.sh` — Server Setup

**Goal**: Prepare Ubuntu slice with base packages, Docker, firewall, users.

**Guard Clause Ideas**:
- Check if Docker is installed: `which docker`
- Check if UFW is configured
- Check if `admin` user already exists

**Steps**:
- SSH into server
- Install Docker & Docker Compose (check version)
- Enable UFW (only ports 22, 80, 443)
- Add user `admin` and grant sudo
- Set password (via `secrets.yml`)
- Install Certbot & dependencies
- Harden SSH (disable password login in sshd_config)

---

## 🧾 3. `03_deploy_wordpress.sh` — Docker & Secrets Deployment

**Goal**: Upload Docker setup, bring up containers, and request SSL.

**Guard Clause Ideas**:
- Check if Docker containers already running: `docker ps`
- Check if cert already exists in `/etc/letsencrypt/live/...`

**Steps**:
- Copy Docker config, Nginx config, secrets.yml to server
- Create required directories (e.g. `/var/www/wordpress`)
- Bring up containers with `docker-compose up -d`
- Run Certbot for Let's Encrypt SSL
- Reload Nginx after cert issuance

---

## 🧾 4. `04_configure_wordpress.sh` — WP & Plugin Config

**Goal**: Post-install automation for WordPress, Media Cloud, and cron.

**Guard Clause Ideas**:
- Check if WP is already installed: `wp core is-installed`
- Check if Media Cloud is configured: look for plugin config file or use WP-CLI

**Steps**:
- Use WP-CLI to set site title, admin user/pass/email
- Install & activate Big File Uploads + Media Cloud
- Use WP-CLI or REST API to configure Media Cloud with AWS keys + S3 bucket + CloudFront
- Configure scheduled cron via `wp cron event schedule`
- Set upload limits if needed
- Confirm everything with a test upload

---

## 🔁 Idempotency Best Practices

For every sub-script:
- Check the current system state before doing anything destructive or redundant
- Log output to a file (e.g. `logs/01_provision.log`) for easy review
- Exit early with a clear message if work has already been done
- Use `set -euo pipefail` for safety

---

## ✅ Bonus Ideas

- Add a `--force` or `--dry-run` flag to each sub-script
- Print user-friendly status updates during setup
- Create a top-level `setup.sh` to orchestrate all phases with clear output
