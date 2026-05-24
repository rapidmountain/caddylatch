#!/usr/bin/env bash
set -euo pipefail

EXECUTABLE_DST="/usr/local/sbin/caddylatch"
CONFIG_DIR="/etc/caddylatch"
SERVICE_DST="/etc/systemd/system/caddylatch.service"
STATE_DIR="/var/lib/caddylatch"
LOG_DIR="/var/log/caddylatch"
CADDY_FILTER="/etc/caddy/filter-caddylatch.caddy"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

if [[ $EUID -ne 0 ]]; then echo -e "${RED}[ERROR]${NC} Must be run as root"; exit 1; fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       CaddyLatch Uninstaller         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

read -rp "Remove CaddyLatch and all its files? [y/N]: " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "Aborted." && exit 0

systemctl is-active --quiet caddylatch 2>/dev/null && { info "Stopping service..."; systemctl stop caddylatch; }
systemctl is-enabled --quiet caddylatch 2>/dev/null && { info "Disabling service..."; systemctl disable caddylatch; }

info "Removing executable symlink..."; rm -f "$EXECUTABLE_DST"
info "Removing systemd unit..."; rm -f "$SERVICE_DST"; systemctl daemon-reload
info "Removing Caddy filter file..."; rm -f "$CADDY_FILTER"
info "Removing state directory..."; rm -rf "$STATE_DIR"
info "Removing log directory..."; rm -rf "$LOG_DIR"

echo ""
read -rp "Remove config directory ${CONFIG_DIR}? [y/N]: " cc
[[ "$cc" == "y" || "$cc" == "Y" ]] && { info "Removing config..."; rm -rf "$CONFIG_DIR"; } || info "Keeping config."

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Uninstall complete             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""
echo "Reminders:"
echo "  - Restore (geo_filter) snippet in your Caddyfile"
echo "  - Reload Caddy: sudo systemctl reload caddy"
echo "  - Re-enable WireGuard if needed: sudo systemctl enable --now wg-quick@wg0"
echo ""
