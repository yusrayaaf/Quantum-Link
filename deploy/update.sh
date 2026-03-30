#!/data/data/com.termux/files/usr/bin/bash
# ─── Quantum Link — Fast Update Script ───────────────────────────────────────
# Pushes code changes to VPS without full re-setup.
# Usage: ./update.sh [--host 1.2.3.4] [--domain example.com]

set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'; BOLD='\033[1m'
log()     { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
success() { echo -e "${GREEN}✔${NC} $*"; }

DOMAIN=""; VPS_HOST=""; VPS_USER="root"
SSH_KEY="$HOME/.ssh/quantum_deploy"
REMOTE_APP_DIR="/var/www/quantum-link"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case $1 in
    --domain) DOMAIN="$2"; shift 2 ;;
    --host)   VPS_HOST="$2"; shift 2 ;;
    --user)   VPS_USER="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Load last deploy config if exists
LAST="$PROJECT_DIR/deploy/.last-deploy"
if [[ -f "$LAST" ]]; then
  source "$LAST"
  VPS_HOST="${VPS_HOST:-$VPS_HOST}"
  DOMAIN="${DOMAIN:-$DOMAIN}"
fi

[[ -z "$VPS_HOST" ]] && read -rp "VPS IP: " VPS_HOST
[[ -z "$DOMAIN" ]]   && read -rp "Domain: " DOMAIN

ssh_cmd() { ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${VPS_USER}@${VPS_HOST}" "$@"; }

echo -e "\n${BOLD}Quantum Link — Update Deploy${NC}\n"

# Build client
log "Building client..."
(cd "$PROJECT_DIR/client" && npm run build --silent)
success "Client built"

# Upload server
log "Uploading server/index.js..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$PROJECT_DIR/server/index.js" "${VPS_USER}@${VPS_HOST}:${REMOTE_APP_DIR}/server/"

# Upload client dist
log "Uploading client dist..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -r "$PROJECT_DIR/client/dist/." "${VPS_USER}@${VPS_HOST}:${REMOTE_APP_DIR}/client/dist/"

# Restart PM2
log "Restarting app..."
ssh_cmd "pm2 restart quantum-link"

sleep 2
STATUS=$(ssh_cmd "curl -s -o /dev/null -w '%{http_code}' http://localhost:3001/api/health" 2>/dev/null || echo "000")
[[ "$STATUS" == "200" ]] && success "Update complete — app healthy (HTTP $STATUS)" || echo -e "${YELLOW}App returned HTTP $STATUS — check pm2 logs${NC}"
