#!/usr/bin/env bash
# bootstrap.sh — One-command setup for a fresh Kali VM
# Usage: ./bootstrap.sh [--tags tag1,tag2] [--check]
#
# Asks for sudo password once, uses it for the full apt upgrade AND Ansible
# (via ANSIBLE_BECOME_PASS) so you are never prompted twice.
# DO NOT run as root (sudo ./bootstrap.sh) — dotfiles would deploy to /root.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Guard: refuse to run as root ─────────────────────────────────────────────
if [[ "$EUID" -eq 0 ]]; then
    error "Do not run this script as root (sudo ./bootstrap.sh)."$'\n'"       Run as your normal user: ./bootstrap.sh"
fi

# ── 0. Prompt for sudo password once ─────────────────────────────────────────
echo -ne "${YELLOW}[sudo]${NC} password for ${USER}: "
read -rs BECOME_PASS
echo ""

# Validate the password immediately so we fail fast, not halfway through
if ! echo "$BECOME_PASS" | sudo -S true 2>/dev/null; then
    error "Incorrect sudo password."
fi

# Keep sudo session alive in the background for the duration of the script
(while true; do echo "$BECOME_PASS" | sudo -S -v 2>/dev/null; sleep 50; done) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; unset BECOME_PASS' EXIT

# ── 1. Full system update/upgrade ────────────────────────────────────────────
info "Running apt update + full-upgrade..."
echo "$BECOME_PASS" | sudo -S apt-get update -qq
echo "$BECOME_PASS" | sudo -S apt-get full-upgrade -y

# ── 2. Ensure pipx is available ──────────────────────────────────────────────
if ! command -v pipx &>/dev/null; then
    info "Installing pipx via apt..."
    echo "$BECOME_PASS" | sudo -S apt-get install -y -qq pipx
    pipx ensurepath
    export PATH="$HOME/.local/bin:$PATH"
fi

# ── 3. Ensure Ansible is installed via pipx ──────────────────────────────────
if ! command -v ansible-playbook &>/dev/null; then
    info "Installing Ansible via pipx..."
    pipx install --include-deps ansible
    export PATH="$HOME/.local/bin:$PATH"
else
    info "Ansible already installed: $(ansible --version | head -1)"
fi

# ── 4. Install Galaxy collection dependencies ────────────────────────────────
info "Installing Ansible Galaxy collections..."
ansible-galaxy collection install -r "$SCRIPT_DIR/requirements.yml" --force-with-deps

# ── 5. Run the playbook (password passed via env — no -K prompt) ─────────────
info "Running playbook..."
echo ""

export ANSIBLE_BECOME_PASS="$BECOME_PASS"
ansible-playbook "$SCRIPT_DIR/site.yml" "$@"

echo ""
info "Done. Log out and back in for group changes (docker) to take effect."
