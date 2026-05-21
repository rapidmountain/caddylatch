#!/usr/bin/env bash
#
# uninstall.sh — Remove CaddyLatch cleanly
#
# Removes agent files, systemd unit, filter file, state, and logs.
# Does NOT modify the Caddyfile or WireGuard config.
#
set -euo pipefail

EXECUTABLE_DST="/usr/local/sbin/caddylatch"
CONFIG_DIR="/etc/caddylatch"
SERVICE_DST="/etc/systemd/system/caddylatch.service"
STATE_DIR="/var/lib/caddylatch"
LOG_DIR="/var/log/caddylatch"
CADDY_FILTER="/etc/caddy/filter-caddylatch.caddy"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Must be run as root"
    exit 1
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       CaddyLatch Uninstaller         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

read -rp "This will remove CaddyLatch and all its files. Continue? [y/N]: " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

# --- Stop service ---
if systemctl is-active --quiet caddylatch 2>/dev/null; then
    info "Stopping caddylatch service..."
    systemctl stop caddylatch
fi

if systemctl is-enabled --quiet caddylatch 2>/dev/null; then
    info "Disabling caddylatch service..."
    systemctl disable caddylatch
fi

# --- Remove files ---
info "Removing executable symlink..."
rm -f "$EXECUTABLE_DST"

info "Removing systemd unit..."
rm -f "$SERVICE_DST"
systemctl daemon-reload

info "Removing Caddy filter file..."
rm -f "$CADDY_FILTER"

info "Removing state directory..."
rm -rf "$STATE_DIR"

info "Removing log directory..."
rm -rf "$LOG_DIR"

# --- Config ---
echo ""
read -rp "Remove config directory ${CONFIG_DIR}? [y/N]: " config_choice
if [[ "$config_choice" == "y" || "$config_choice" == "Y" ]]; then
    info "Removing config..."
    rm -rf "$CONFIG_DIR"
else
    info "Keeping config at ${CONFIG_DIR}"
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Uninstall complete             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""
echo "Reminders:"
echo "  - Replace 'import /etc/caddy/filter-caddylatch.caddy' in your Caddyfile"
echo "    with your original (geo_filter) snippet"
echo "  - Reload Caddy: sudo systemctl reload caddy"
echo "  - Decide whether to re-enable WireGuard:"
echo "    sudo systemctl enable --now wg-quick@wg0"
echo ""
