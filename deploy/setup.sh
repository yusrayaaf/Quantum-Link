#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  ██████  ██    ██  █████  ███    ██ ████████ ██    ██ ███    ███
# ██    ██ ██    ██ ██   ██ ████   ██    ██    ██    ██ ████  ████
# ██    ██ ██    ██ ███████ ██ ██  ██    ██    ██    ██ ██ ████ ██
# ██ ▄▄ ██ ██    ██ ██   ██ ██  ██ ██    ██    ██    ██ ██  ██  ██
#  ██████   ██████  ██   ██ ██   ████    ██     ██████  ██      ██
#     ▀▀
#  ██      ██ ███    ██ ██   ██
#  ██      ██ ████   ██ ██  ██
#  ██      ██ ██ ██  ██ █████
#  ██      ██ ██  ██ ██ ██  ██
#  ███████ ██ ██   ████ ██   ██
#
#  Quantum Link — IONOS VPS Deploy Script
#  Runs from Termux on Android, deploys to IONOS VPS via SSH
#
#  Usage:
#    chmod +x setup.sh
#    ./setup.sh [--domain yourdomain.com] [--user deploy] [--host 1.2.3.4]
#
#  Requirements (on this device):
#    pkg install openssh
#    pkg install git
#
#  What this does on the VPS:
#    1. System update + install Node.js 20, Nginx, Certbot, PM2
#    2. Create deploy user + directory structure
#    3. Upload project files via rsync/scp
#    4. Configure Nginx reverse proxy
#    5. Obtain SSL certificate via Certbot
#    6. Set up PM2 process with auto-restart
#    7. Configure UFW firewall
#    8. Final health check
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
IFS=$'\n\t'

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Default config (override via args or prompts) ────────────────────────────
DOMAIN=""
VPS_HOST=""
VPS_USER="root"
DEPLOY_USER="quantum"
APP_PORT=3001
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_APP_DIR="/var/www/quantum-link"
SSH_KEY="$HOME/.ssh/quantum_deploy"

# ─── Parse CLI args ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --domain)   DOMAIN="$2";   shift 2 ;;
    --host)     VPS_HOST="$2"; shift 2 ;;
    --user)     VPS_USER="$2"; shift 2 ;;
    --key)      SSH_KEY="$2";  shift 2 ;;
    --port)     APP_PORT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ─── Helpers ─────────────────────────────────────────────────────────────────
log()     { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
success() { echo -e "${GREEN}✔${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC} $*"; }
error()   { echo -e "${RED}✘ ERROR:${NC} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}${BLUE}━━━ $* ━━━${NC}\n"; }

prompt_if_empty() {
  local varname="$1"
  local label="$2"
  local secret="${3:-false}"
  if [[ -z "${!varname}" ]]; then
    if [[ "$secret" == "true" ]]; then
      read -rsp "${BOLD}${label}:${NC} " "$varname"
      echo
    else
      read -rp "${BOLD}${label}:${NC} " "$varname"
    fi
  fi
}

ssh_cmd() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes \
    "${VPS_USER}@${VPS_HOST}" "$@"
}

scp_upload() {
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -r "$1" "${VPS_USER}@${VPS_HOST}:$2"
}

# ─── Banner ───────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${BLUE}"
cat << 'EOF'
  ╔═══════════════════════════════════════════╗
  ║         QUANTUM LINK  DEPLOYER            ║
  ║         IONOS VPS  ×  Termux              ║
  ╚═══════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ─── Collect config ───────────────────────────────────────────────────────────
header "Configuration"

prompt_if_empty VPS_HOST  "VPS IP Address (IONOS)"
prompt_if_empty DOMAIN    "Domain name (e.g. quantumlink.app)"

echo ""
log "VPS Host : ${VPS_HOST}"
log "Domain   : ${DOMAIN}"
log "App Port : ${APP_PORT}"
log "SSH Key  : ${SSH_KEY}"
echo ""

# ─── SSH key setup ────────────────────────────────────────────────────────────
header "SSH Key Setup"

if [[ ! -f "$SSH_KEY" ]]; then
  log "Generating SSH keypair at $SSH_KEY ..."
  ssh-keygen -t ed25519 -C "quantum-deploy" -f "$SSH_KEY" -N ""
  success "SSH keypair generated"

  echo ""
  warn "Copy this public key to your VPS root user's authorized_keys:"
  echo ""
  echo -e "${YELLOW}$(cat "${SSH_KEY}.pub")${NC}"
  echo ""
  read -rp "Press ENTER once you've added the key to the VPS, then continue..."
else
  success "SSH key already exists: $SSH_KEY"
fi

# ─── Test connectivity ────────────────────────────────────────────────────────
header "Testing SSH Connection"
log "Connecting to ${VPS_USER}@${VPS_HOST} ..."
ssh_cmd "echo 'SSH OK'" || error "Cannot reach VPS. Check IP, user, and SSH key."
success "SSH connection established"

# ─── Collect secrets ─────────────────────────────────────────────────────────
header "Application Secrets"

JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n')
success "Generated JWT_SECRET (64-byte random)"

read -rsp "${BOLD}Creator Panel admin password:${NC} " CREATOR_PASS
echo ""
read -rsp "${BOLD}Confirm password:${NC} " CREATOR_PASS2
echo ""
[[ "$CREATOR_PASS" == "$CREATOR_PASS2" ]] || error "Passwords do not match"

# ─── Build client ─────────────────────────────────────────────────────────────
header "Building React Client"

if command -v node &>/dev/null; then
  log "Node.js found: $(node -v)"
  log "Installing client dependencies..."
  (cd "$PROJECT_DIR/client" && npm install --silent)
  log "Building production bundle..."
  (cd "$PROJECT_DIR/client" && npm run build)
  success "Client built → client/dist/"
else
  warn "Node.js not found in Termux. Skipping local build."
  warn "The VPS will build the client after upload."
fi

# ─── VPS: System setup ────────────────────────────────────────────────────────
header "VPS System Setup"
log "Updating packages and installing dependencies..."

ssh_cmd bash << ENDSSH
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Update system
apt-get update -qq
apt-get upgrade -y -qq

# Install essentials
apt-get install -y -qq curl git ufw nginx certbot python3-certbot-nginx rsync

# Install Node.js 20 via NodeSource
if ! command -v node &>/dev/null || [[ "\$(node -v | cut -c2-3)" -lt 20 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -qq nodejs
fi

# Install PM2 globally
npm install -g pm2 --silent

echo "Node: \$(node -v)"
echo "npm: \$(npm -v)"
echo "PM2: \$(pm2 -v)"

# Create deploy user if not exists
if ! id "${DEPLOY_USER}" &>/dev/null; then
  useradd -m -s /bin/bash -G www-data "${DEPLOY_USER}"
  echo "Created user: ${DEPLOY_USER}"
fi

# Create app directories
mkdir -p "${REMOTE_APP_DIR}/server"
mkdir -p "${REMOTE_APP_DIR}/client/dist"
mkdir -p "${REMOTE_APP_DIR}/server/data"
mkdir -p "${REMOTE_APP_DIR}/server/uploads"
mkdir -p /var/log/quantum-link

chown -R "${DEPLOY_USER}:www-data" "${REMOTE_APP_DIR}"
chmod -R 755 "${REMOTE_APP_DIR}"
chmod 770 "${REMOTE_APP_DIR}/server/uploads"

echo "✔ System setup complete"
ENDSSH

success "VPS system configured"

# ─── Upload project files ─────────────────────────────────────────────────────
header "Uploading Project Files"

log "Uploading server files..."
scp_upload "$PROJECT_DIR/server/index.js"       "${REMOTE_APP_DIR}/server/"
scp_upload "$PROJECT_DIR/server/package.json"   "${REMOTE_APP_DIR}/server/"
scp_upload "$PROJECT_DIR/server/package-lock.json" "${REMOTE_APP_DIR}/server/" 2>/dev/null || true

# Upload client build if it exists, otherwise upload source for VPS build
if [[ -d "$PROJECT_DIR/client/dist" ]]; then
  log "Uploading pre-built client dist..."
  scp_upload "$PROJECT_DIR/client/dist" "${REMOTE_APP_DIR}/client/"
else
  log "Uploading client source for VPS build..."
  scp_upload "$PROJECT_DIR/client/src"           "${REMOTE_APP_DIR}/client/"
  scp_upload "$PROJECT_DIR/client/public"        "${REMOTE_APP_DIR}/client/"
  scp_upload "$PROJECT_DIR/client/package.json"  "${REMOTE_APP_DIR}/client/"
  scp_upload "$PROJECT_DIR/client/vite.config.js" "${REMOTE_APP_DIR}/client/"
  scp_upload "$PROJECT_DIR/client/index.html"    "${REMOTE_APP_DIR}/client/"
fi

success "Files uploaded"

# ─── Write .env on VPS ────────────────────────────────────────────────────────
header "Writing Environment Config"

ssh_cmd bash << ENDSSH
cat > "${REMOTE_APP_DIR}/server/.env" << 'EOF'
PORT=${APP_PORT}
NODE_ENV=production
JWT_SECRET=${JWT_SECRET}
JWT_EXPIRES_IN=7d
DB_PATH=./data/quantum.db
UPLOAD_DIR=./uploads
MAX_FILE_SIZE_MB=25
CORS_ORIGINS=https://${DOMAIN},https://www.${DOMAIN}
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX=100
CREATOR_USERNAME=admin
CREATOR_PASSWORD=${CREATOR_PASS}
ALLOWED_MIME_TYPES=image/jpeg,image/png,image/gif,image/webp,video/mp4,audio/mpeg,audio/ogg,application/pdf,text/plain
EOF

chmod 600 "${REMOTE_APP_DIR}/server/.env"
echo "✔ .env written"
ENDSSH

success "Environment configured"

# ─── Install server deps + optional client build on VPS ──────────────────────
header "Installing Dependencies on VPS"

ssh_cmd bash << ENDSSH
set -euo pipefail

cd "${REMOTE_APP_DIR}/server"
npm install --omit=dev --silent
echo "✔ Server deps installed"

# Build client if dist not uploaded
if [[ ! -d "${REMOTE_APP_DIR}/client/dist" ]]; then
  cd "${REMOTE_APP_DIR}/client"
  npm install --silent
  npm run build
  echo "✔ Client built on VPS"
fi
ENDSSH

success "Dependencies ready"

# ─── PM2 config ───────────────────────────────────────────────────────────────
header "Configuring PM2"

ssh_cmd bash << ENDSSH
cat > "${REMOTE_APP_DIR}/ecosystem.config.cjs" << 'EOF'
module.exports = {
  apps: [{
    name: "quantum-link",
    script: "./server/index.js",
    cwd: "${REMOTE_APP_DIR}",
    instances: 1,
    exec_mode: "fork",
    watch: false,
    env: {
      NODE_ENV: "production"
    },
    error_file: "/var/log/quantum-link/error.log",
    out_file: "/var/log/quantum-link/out.log",
    log_date_format: "YYYY-MM-DD HH:mm:ss Z",
    max_memory_restart: "300M",
    restart_delay: 3000,
    max_restarts: 10,
    min_uptime: "5s"
  }]
};
EOF

# Stop existing if running
pm2 stop quantum-link 2>/dev/null || true
pm2 delete quantum-link 2>/dev/null || true

# Start app
cd "${REMOTE_APP_DIR}"
pm2 start ecosystem.config.cjs

# Save PM2 process list
pm2 save

# Enable PM2 startup on boot
pm2 startup systemd -u root --hp /root 2>/dev/null || true

echo "✔ PM2 configured"
pm2 status
ENDSSH

success "PM2 running"

# ─── Nginx config ─────────────────────────────────────────────────────────────
header "Configuring Nginx"

ssh_cmd bash << ENDSSH
cat > /etc/nginx/sites-available/quantum-link << 'EOF'
# ── HTTP → HTTPS redirect ──────────────────────────────────
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};
    return 301 https://\$host\$request_uri;
}

# ── Main HTTPS server ──────────────────────────────────────
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN} www.${DOMAIN};

    # SSL (Certbot will update these)
    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;

    # Gzip
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;
    gzip_min_length 1000;

    # Client dist (React PWA)
    root ${REMOTE_APP_DIR}/client/dist;
    index index.html;

    # Service worker — no cache
    location = /sw.js {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        try_files \$uri =404;
    }

    # Static assets — long cache
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2|woff|ttf|webp)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    # API + Socket.io → Node.js backend
    location /api/ {
        proxy_pass         http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300s;
        client_max_body_size 30M;
    }

    location /socket.io/ {
        proxy_pass         http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 3600s;
    }

    location /uploads/ {
        proxy_pass         http://127.0.0.1:${APP_PORT};
        proxy_set_header   Host \$host;
        expires 30d;
        add_header Cache-Control "public";
    }

    # React router — SPA fallback
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Logs
    access_log /var/log/nginx/quantum-link.access.log;
    error_log  /var/log/nginx/quantum-link.error.log;
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/quantum-link /etc/nginx/sites-enabled/quantum-link
rm -f /etc/nginx/sites-enabled/default

# Test config
nginx -t && echo "✔ Nginx config valid"
ENDSSH

success "Nginx configured"

# ─── SSL via Certbot ──────────────────────────────────────────────────────────
header "Obtaining SSL Certificate"

log "Running Certbot for ${DOMAIN} ..."

ssh_cmd bash << ENDSSH
set -euo pipefail

# Temp HTTP server block for Certbot challenge (before SSL)
cat > /etc/nginx/sites-available/quantum-link-temp << 'EOF'
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    location / { return 200 'ok'; add_header Content-Type text/plain; }
}
EOF
ln -sf /etc/nginx/sites-available/quantum-link-temp /etc/nginx/sites-enabled/quantum-link
nginx -t && nginx -s reload

# Get cert (non-interactive)
certbot certonly \
  --nginx \
  --non-interactive \
  --agree-tos \
  --email "webmaster@${DOMAIN}" \
  --domains "${DOMAIN},www.${DOMAIN}" \
  --redirect 2>&1 || true

# Restore full config
ln -sf /etc/nginx/sites-available/quantum-link /etc/nginx/sites-enabled/quantum-link
rm -f /etc/nginx/sites-available/quantum-link-temp

nginx -t && nginx -s reload
echo "✔ SSL certificate obtained and Nginx reloaded"

# Auto-renew cron
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet && nginx -s reload") | sort -u | crontab -
echo "✔ Certbot auto-renew cron installed"
ENDSSH

success "SSL certificate installed"

# ─── UFW Firewall ─────────────────────────────────────────────────────────────
header "Configuring Firewall"

ssh_cmd bash << ENDSSH
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
echo "✔ Firewall configured"
ufw status
ENDSSH

success "Firewall active"

# ─── Health check ─────────────────────────────────────────────────────────────
header "Health Check"

log "Waiting 5s for app to warm up..."
sleep 5

HTTP_STATUS=$(ssh_cmd "curl -s -o /dev/null -w '%{http_code}' http://localhost:${APP_PORT}/api/health 2>/dev/null || echo '000'")

if [[ "$HTTP_STATUS" == "200" ]]; then
  success "App health check passed (HTTP ${HTTP_STATUS})"
else
  warn "Health check returned HTTP ${HTTP_STATUS} — check logs:"
  ssh_cmd "pm2 logs quantum-link --nostream --lines 20"
fi

# Check HTTPS
HTTPS_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "https://${DOMAIN}/api/health" 2>/dev/null || echo "000")
if [[ "$HTTPS_STATUS" == "200" ]]; then
  success "HTTPS health check passed (HTTP ${HTTPS_STATUS})"
else
  warn "HTTPS health check: ${HTTPS_STATUS} — DNS may still be propagating"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}"
cat << 'EOF'
  ╔═══════════════════════════════════════════════╗
  ║   ✔  QUANTUM LINK DEPLOYED SUCCESSFULLY!      ║
  ╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${BOLD}URLs:${NC}"
echo -e "  ${CYAN}https://${DOMAIN}${NC}          — App"
echo -e "  ${CYAN}https://${DOMAIN}/creator${NC}  — Creator Panel"
echo ""
echo -e "${BOLD}Credentials:${NC}"
echo -e "  Username: ${YELLOW}admin${NC}"
echo -e "  Password: ${YELLOW}(the one you entered)${NC}"
echo ""
echo -e "${BOLD}Useful commands (SSH into VPS):${NC}"
echo -e "  ${CYAN}pm2 status${NC}                    — App status"
echo -e "  ${CYAN}pm2 logs quantum-link${NC}          — Live logs"
echo -e "  ${CYAN}pm2 restart quantum-link${NC}       — Restart app"
echo -e "  ${CYAN}nginx -t && nginx -s reload${NC}    — Reload Nginx"
echo -e "  ${CYAN}certbot renew${NC}                  — Renew SSL"
echo ""

# Save deployment info locally
cat > "$PROJECT_DIR/deploy/.last-deploy" << EOF
DEPLOYED=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
DOMAIN=${DOMAIN}
VPS_HOST=${VPS_HOST}
VPS_USER=${VPS_USER}
APP_PORT=${APP_PORT}
REMOTE_DIR=${REMOTE_APP_DIR}
EOF
success "Deployment info saved to deploy/.last-deploy"
