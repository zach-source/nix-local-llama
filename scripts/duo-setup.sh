#!/usr/bin/env bash
# Duo Setup Script for Ubuntu with Push Authentication
# Configures Duo 2FA for SSH with push notifications
#
# Prerequisites:
#   1. Create Duo account: https://signup.duo.com/
#   2. Create "Unix Application" in Duo Admin Panel
#   3. Get: Integration Key, Secret Key, API Hostname
#
# Usage: sudo ./duo-setup.sh <integration_key> <secret_key> <api_host>

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[DUO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    cat << EOF
Usage: sudo $0 <integration_key> <secret_key> <api_host>

Get these credentials from Duo Admin Panel:
  1. Go to: https://admin.duosecurity.com
  2. Applications → Protect an Application
  3. Search for "Unix Application"
  4. Click "Protect"
  5. Copy the Integration Key, Secret Key, and API Hostname

Example:
  sudo $0 DIXXXXXXXXXXXXXXXXXX sXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX api-XXXXXXXX.duosecurity.com

EOF
    exit 1
}

# Check root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

# Check arguments
if [[ $# -lt 3 ]]; then
    usage
fi

IKEY="$1"
SKEY="$2"
HOST="$3"

# Validate inputs
if [[ ! "$IKEY" =~ ^DI[A-Z0-9]{18}$ ]]; then
    warn "Integration key doesn't match expected format (DIXXXXXXXXXXXXXXXXXX)"
fi

if [[ ! "$HOST" =~ ^api-.*\.duosecurity\.com$ ]]; then
    warn "API host doesn't match expected format (api-XXXXXXXX.duosecurity.com)"
fi

log "=== Duo 2FA Setup ==="
log "API Host: $HOST"

# Install duo-unix if not present
if ! command -v login_duo &>/dev/null; then
    log "Installing duo-unix..."

    # Add Duo repository
    curl -s https://duo.com/DUO-GPG-PUBLIC-KEY.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/duo.gpg

    # Detect Ubuntu version and use appropriate repo
    CODENAME=$(lsb_release -cs)
    case "$CODENAME" in
        noble|questing|oracular)
            echo "deb [arch=amd64] https://pkg.duosecurity.com/Ubuntu noble main" > /etc/apt/sources.list.d/duosecurity.list
            ;;
        jammy)
            echo "deb [arch=amd64] https://pkg.duosecurity.com/Ubuntu jammy main" > /etc/apt/sources.list.d/duosecurity.list
            ;;
        *)
            warn "Unknown Ubuntu version: $CODENAME, using noble"
            echo "deb [arch=amd64] https://pkg.duosecurity.com/Ubuntu noble main" > /etc/apt/sources.list.d/duosecurity.list
            ;;
    esac

    apt-get update
    apt-get install -y duo-unix
fi

log "Configuring Duo PAM..."

# Create pam_duo.conf
cat > /etc/duo/pam_duo.conf << EOF
[duo]
; Duo integration key
ikey = ${IKEY}
; Duo secret key
skey = ${SKEY}
; Duo API host
host = ${HOST}

; Failmode: safe = allow login if Duo unreachable, secure = deny
failmode = safe

; Send command info in push notification
pushinfo = yes

; Auto-push (send push automatically without prompting)
autopush = yes

; Number of prompts before failing
prompts = 1

; Groups to require 2FA (empty = all users)
; groups = sudo,admin

; HTTP proxy (if needed)
; http_proxy = http://proxy.example.com:8080
EOF

chmod 600 /etc/duo/pam_duo.conf
log "Created /etc/duo/pam_duo.conf"

# Create login_duo.conf (same settings, different owner)
cat > /etc/duo/login_duo.conf << EOF
[duo]
ikey = ${IKEY}
skey = ${SKEY}
host = ${HOST}
failmode = safe
pushinfo = yes
autopush = yes
prompts = 1
EOF

chmod 600 /etc/duo/login_duo.conf
chown sshd:root /etc/duo/login_duo.conf 2>/dev/null || chown root:root /etc/duo/login_duo.conf
log "Created /etc/duo/login_duo.conf"

# Configure PAM for SSH
log "Configuring PAM for SSH..."

PAM_SSHD="/etc/pam.d/sshd"
if [[ -f "$PAM_SSHD" ]]; then
    cp "$PAM_SSHD" "${PAM_SSHD}.pre-duo.bak"

    if ! grep -q "pam_duo.so" "$PAM_SSHD"; then
        # Add Duo after common-auth
        if grep -q "@include common-auth" "$PAM_SSHD"; then
            sed -i '/@include common-auth/a auth required pam_duo.so' "$PAM_SSHD"
        else
            # Fallback: add after pam_unix
            sed -i '/pam_unix.so/a auth required pam_duo.so' "$PAM_SSHD"
        fi
        log "Added pam_duo.so to $PAM_SSHD"
    else
        warn "pam_duo.so already configured in $PAM_SSHD"
    fi
else
    error "PAM SSH config not found: $PAM_SSHD"
    exit 1
fi

# Configure sshd_config
log "Configuring SSH daemon..."

SSHD_CONFIG="/etc/ssh/sshd_config"
if [[ -f "$SSHD_CONFIG" ]]; then
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.pre-duo.bak"

    # Enable keyboard-interactive authentication
    if grep -q "^KbdInteractiveAuthentication" "$SSHD_CONFIG"; then
        sed -i 's/^KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' "$SSHD_CONFIG"
    elif grep -q "^#KbdInteractiveAuthentication" "$SSHD_CONFIG"; then
        sed -i 's/^#KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' "$SSHD_CONFIG"
    else
        echo "KbdInteractiveAuthentication yes" >> "$SSHD_CONFIG"
    fi

    # Enable ChallengeResponseAuthentication (older SSH versions)
    if grep -q "^ChallengeResponseAuthentication" "$SSHD_CONFIG"; then
        sed -i 's/^ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' "$SSHD_CONFIG"
    fi

    # Enable PAM
    if grep -q "^UsePAM" "$SSHD_CONFIG"; then
        sed -i 's/^UsePAM.*/UsePAM yes/' "$SSHD_CONFIG"
    elif grep -q "^#UsePAM" "$SSHD_CONFIG"; then
        sed -i 's/^#UsePAM.*/UsePAM yes/' "$SSHD_CONFIG"
    else
        echo "UsePAM yes" >> "$SSHD_CONFIG"
    fi

    # Configure authentication methods (pubkey + 2FA, or password + 2FA)
    if ! grep -q "^AuthenticationMethods" "$SSHD_CONFIG"; then
        # Require both SSH key AND Duo 2FA
        echo "AuthenticationMethods publickey,keyboard-interactive" >> "$SSHD_CONFIG"
    fi

    log "Updated $SSHD_CONFIG"
else
    error "SSH config not found: $SSHD_CONFIG"
    exit 1
fi

# Validate sshd config
log "Validating SSH configuration..."
if sshd -t 2>&1; then
    log "SSH configuration is valid"
else
    error "SSH configuration validation failed!"
    error "Restoring backups..."
    cp "${SSHD_CONFIG}.pre-duo.bak" "$SSHD_CONFIG"
    cp "${PAM_SSHD}.pre-duo.bak" "$PAM_SSHD"
    exit 1
fi

# Restart SSH
log "Restarting SSH service..."
systemctl restart sshd || systemctl restart ssh

echo
log "=== Duo Setup Complete ==="
echo
log "IMPORTANT: Keep this session open until you verify 2FA works!"
echo
log "Next steps:"
echo "  1. Open a NEW terminal window"
echo "  2. SSH to this machine: ssh $(whoami)@$(hostname)"
echo "  3. You'll receive an enrollment link (first time) or push notification"
echo "  4. Install Duo Mobile app and scan the QR code"
echo "  5. Approve the push notification"
echo
log "If you get locked out, restore with:"
echo "  sudo cp ${SSHD_CONFIG}.pre-duo.bak ${SSHD_CONFIG}"
echo "  sudo cp ${PAM_SSHD}.pre-duo.bak ${PAM_SSHD}"
echo "  sudo systemctl restart sshd"
echo
warn "Test in a new session before closing this one!"
