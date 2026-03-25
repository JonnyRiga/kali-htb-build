#!/usr/bin/env bash
# bootstrap.sh — One-command setup for a fresh Kali VM
# Usage: ./bootstrap.sh [--tags tag1,tag2] [--check]
#
# Installs Ansible via pipx, pulls Galaxy collections, then runs the playbook.
# Any arguments are forwarded to ansible-playbook.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. Ensure pipx is available ──────────────────────────────────────────────
if ! command -v pipx &>/dev/null; then
    info "Installing pipx via apt..."
    sudo apt-get update -qq && sudo apt-get install -y -qq pipx
    pipx ensurepath
    export PATH="$HOME/.local/bin:$PATH"
fi

# ── 2. Ensure Ansible is installed via pipx ──────────────────────────────────
if ! command -v ansible-playbook &>/dev/null; then
    info "Installing Ansible via pipx..."
    pipx install --include-deps ansible
    export PATH="$HOME/.local/bin:$PATH"
else
    info "Ansible already installed: $(ansible --version | head -1)"
fi

# ── 3. Install Galaxy collection dependencies ───────────────────────────────
info "Installing Ansible Galaxy collections..."
ansible-galaxy collection install -r "$SCRIPT_DIR/requirements.yml" --force-with-deps

# ── 4. Run the playbook ─────────────────────────────────────────────────────
info "Running playbook..."
echo ""

# Forward all script arguments to ansible-playbook (e.g. --tags, --check)
ansible-playbook "$SCRIPT_DIR/site.yml" -K "$@"

echo ""
info "Done. Log out and back in for group changes (docker) to take effect."
