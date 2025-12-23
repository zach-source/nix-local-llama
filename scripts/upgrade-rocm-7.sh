#!/usr/bin/env bash
# Upgrade ROCm from 6.4 to 7.1.1 for AMD Strix Halo (gfx1151)
#
# This script upgrades ROCm to enable rocWMMA support for better flash attention performance.
# Run with: sudo ./upgrade-rocm-7.sh
#
# After upgrade, rebuild llama.cpp with:
#   ENABLE_ROCWMMA=1 ./scripts/build-llama-uma.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[ROCM]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

ROCM_VERSION="7.1.1"
# Note: amdgpu driver is built into kernel 6.17+, no separate driver repo needed

log "=== ROCm Upgrade Script ==="
log "Upgrading to ROCm ${ROCM_VERSION}"
echo

# Step 1: Backup current config
log "Step 1: Backing up current ROCm configuration..."
if [[ -f /etc/apt/sources.list.d/rocm.list ]]; then
    cp /etc/apt/sources.list.d/rocm.list /etc/apt/sources.list.d/rocm.list.bak
    log "  Backed up to /etc/apt/sources.list.d/rocm.list.bak"
fi

# Step 2: Update GPG key
log "Step 2: Updating ROCm GPG key..."
mkdir -p /etc/apt/keyrings
wget -q https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor > /etc/apt/keyrings/rocm.gpg
log "  GPG key updated"

# Step 3: Update repository
log "Step 3: Updating ROCm repository to ${ROCM_VERSION}..."
tee /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} noble main
# amdgpu driver is built into kernel 6.17, no separate repo needed
EOF
log "  Repository updated"

# Step 4: Update package lists
log "Step 4: Updating package lists..."
apt update

# Step 5: Upgrade ROCm packages
log "Step 5: Upgrading ROCm packages..."
apt install --upgrade -y \
    rocm-core \
    rocm-dev \
    rocm-llvm \
    hip-dev \
    hip-runtime-amd \
    hipblas \
    hipblas-dev \
    hipblaslt \
    hipblaslt-dev \
    rocblas \
    rocblas-dev \
    rocsolver \
    rocsolver-dev

# Step 6: Install rocWMMA (if available)
log "Step 6: Checking for rocWMMA..."
if apt-cache show rocwmma-dev 2>/dev/null | grep -q "Package:"; then
    log "  Installing rocWMMA..."
    apt install -y rocwmma-dev
else
    warn "  rocWMMA package not found in repository"
    warn "  You may need to build it from source for gfx1151 support"
fi

# Step 7: Verify installation
log "Step 7: Verifying installation..."
echo
rocm_version=$(cat /opt/rocm/.info/version 2>/dev/null || echo "unknown")
log "  ROCm version: ${rocm_version}"

if command -v hipcc &>/dev/null; then
    hipcc_version=$(hipcc --version 2>&1 | head -1)
    log "  hipcc: ${hipcc_version}"
fi

if command -v rocminfo &>/dev/null; then
    log "  GPU detection:"
    rocminfo 2>/dev/null | grep -E "(Name:|Marketing Name:|gfx)" | head -5 | sed 's/^/    /'
fi

echo
log "=== Upgrade Complete ==="
echo
log "Next steps:"
echo "  1. Reboot if kernel modules were updated"
echo "  2. Rebuild llama.cpp with rocWMMA support:"
echo "     cd ~/workspaces/local-llama"
echo "     ENABLE_ROCWMMA=1 ./scripts/build-llama-uma.sh"
echo
log "If rocWMMA compilation fails, you may need to build it from source:"
echo "  git clone https://github.com/ROCm/rocWMMA.git"
echo "  cd rocWMMA"
echo "  cmake -B build -DROCWMMA_BUILD_TESTS=OFF -DGPU_TARGETS=gfx1151"
echo "  cmake --build build && sudo cmake --install build"
