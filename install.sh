#!/usr/bin/env bash
#
# install.sh — Install or upgrade CaddyLatch
#
# Creates directories, symlinks executable, installs systemd unit,
# and manages config with smart merge on upgrades.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Paths
EXECUTABLE_SRC="${SCRIPT_DIR}/caddylatch"
EXECUTABLE_DST="/usr/local/sbin/caddylatch"
CONFIG_TEMPLATE="${SCRIPT_DIR}/caddylatch.conf.template"
CONFIG_DIR="/etc/caddylatch"
CONFIG_DST="${CONFIG_DIR}/caddylatch.conf"
SERVICE_SRC="${SCRIPT_DIR}/systemd/caddylatch.service"
SERVICE_DST="/etc/systemd/system/caddylatch.service"
STATE_DIR="/var/lib/caddylatch"
LOG_DIR="/var/log/caddylatch"
CADDY_FILTER="/etc/caddy/filter-caddylatch.caddy"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
    error "Must be run as root"
    exit 1
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       CaddyLatch Installer           ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# --- Directories ---
info "Creating directories..."
mkdir -p "${CONFIG_DIR}"
mkdir -p "${STATE_DIR}"
mkdir -p "${LOG_DIR}"
chmod 750 "${CONFIG_DIR}"
chmod 750 "${STATE_DIR}"
chmod 750 "${LOG_DIR}"

# --- Config management ---
config_merge() {
    local template="$1"
    local existing="$2"

    # Parse keys from template
    declare -A tmpl_keys
    while IFS= read -r line; do
        line_trimmed="$(echo "$line" | xargs)"
        [[ -z "$line_trimmed" || "$line_trimmed" == \#* ]] && continue
        if [[ "$line_trimmed" == *=* ]]; then
            key="${line_trimmed%%=*}"
            key="$(echo "$key" | xargs)"
            val="${line_trimmed#*=}"
            val="$(echo "$val" | xargs)"
            tmpl_keys["$key"]="$val"
        fi
    done < "$template"

    # Parse keys from existing config
    declare -A exist_keys
    declare -A exist_values
    while IFS= read -r line; do
        line_trimmed="$(echo "$line" | xargs)"
        [[ -z "$line_trimmed" || "$line_trimmed" == \#* ]] && continue
        if [[ "$line_trimmed" == *=* ]]; then
            key="${line_trimmed%%=*}"
            key="$(echo "$key" | xargs)"
            val="${line_trimmed#*=}"
            val="$(echo "$val" | xargs)"
            exist_keys["$key"]=1
            exist_values["$key"]="$val"
        fi
    done < "$existing"

    # Find new keys (in template, not in existing)
    local new_keys=()
    for key in "${!tmpl_keys[@]}"; do
        if [[ -z "${exist_keys[$key]+x}" ]]; then
            new_keys+=("$key")
        fi
    done

    # Find removed keys (in existing, not in template)
    local removed_keys=()
    for key in "${!exist_keys[@]}"; do
        if [[ -z "${tmpl_keys[$key]+x}" ]]; then
            removed_keys+=("$key")
        fi
    done

    if [[ ${#new_keys[@]} -eq 0 && ${#removed_keys[@]} -eq 0 ]]; then
        info "Config is up to date — no schema changes."
        return 0
    fi

    echo ""
    echo -e "${CYAN}Config schema changes detected:${NC}"
    echo ""

    if [[ ${#new_keys[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}New settings:${NC}"
        for key in "${new_keys[@]}"; do
            echo -e "    + ${key}=${tmpl_keys[$key]}"
        done
    fi

    if [[ ${#removed_keys[@]} -gt 0 ]]; then
        echo -e "  ${RED}Removed settings:${NC}"
        for key in "${removed_keys[@]}"; do
            echo -e "    - ${key}=${exist_values[$key]}"
        done
    fi

    echo ""
    echo "Options:"
    echo "  1) Merge — add new settings with defaults, remove obsolete, keep your values"
    echo "  2) Overwrite — replace with new template (LOSES your customizations)"
    echo "  3) Skip — keep existing unchanged (review changes above and edit manually)"
    echo ""
    read -rp "Choose [1/2/3]: " choice

    case "$choice" in
        1)
            info "Merging config..."
            local tmp_config
            tmp_config="$(mktemp)"

            while IFS= read -r line; do
                line_trimmed="$(echo "$line" | xargs)"
                if [[ -z "$line_trimmed" || "$line_trimmed" == \#* ]]; then
                    echo "$line" >> "$tmp_config"
                    continue
                fi
                if [[ "$line_trimmed" == *=* ]]; then
                    key="${line_trimmed%%=*}"
                    key="$(echo "$key" | xargs)"
                    if [[ -n "${exist_values[$key]+x}" ]]; then
                        echo "${key}=${exist_values[$key]}" >> "$tmp_config"
                    else
                        echo "$line" >> "$tmp_config"
                    fi
                else
                    echo "$line" >> "$tmp_config"
                fi
            done < "$template"

            cp "$tmp_config" "$existing"
            rm -f "$tmp_config"
            info "Config merged successfully."
            ;;
        2)
            warn "Overwriting config with template..."
            cp "$template" "$existing"
            info "Config overwritten."
            ;;
        3)
            info "Keeping existing config unchanged."
            ;;
        *)
            warn "Invalid choice — keeping existing config."
            ;;
    esac
}

if [[ -f "$CONFIG_DST" ]]; then
    info "Existing config found at ${CONFIG_DST}"
    config_merge "$CONFIG_TEMPLATE" "$CONFIG_DST"
else
    info "Installing default config to ${CONFIG_DST}"
    cp "$CONFIG_TEMPLATE" "$CONFIG_DST"
fi
chmod 600 "$CONFIG_DST"

# --- Executable ---
info "Symlinking executable..."
chmod +x "$EXECUTABLE_SRC"
ln -sf "$EXECUTABLE_SRC" "$EXECUTABLE_DST"

# --- Systemd ---
info "Installing systemd service..."
cp "$SERVICE_SRC" "$SERVICE_DST"
systemctl daemon-reload

# --- Caddy filter file ---
if [[ ! -f "$CADDY_FILTER" ]]; then
    info "Creating locked filter file: ${CADDY_FILTER}"
    cat > "$CADDY_FILTER" << 'EOF'
# Managed by CaddyLatch — do not edit manually.
# This file is regenerated on every state change.

# STATE: LOCKED — CaddyLatch has not been started yet
(geo_filter) {
    @geo_blocked {
        not remote_ip 127.0.0.1/32
    }
    handle @geo_blocked {
        abort
    }
}
EOF
fi

# --- Check for existing geo_filter in Caddyfile ---
echo ""
CADDYFILE="/etc/caddy/Caddyfile"
if [[ -f "$CADDYFILE" ]]; then
    if grep -q "(geo_filter)" "$CADDYFILE"; then
        warn "Your Caddyfile contains a (geo_filter) snippet definition."
        echo ""
        echo "  CaddyLatch manages geo_filter dynamically via ${CADDY_FILTER}."
        echo "  You need to:"
        echo "    1. Remove the (geo_filter) snippet from ${CADDYFILE}"
        echo "    2. Add this import line in its place:"
        echo ""
        echo -e "       ${CYAN}import /etc/caddy/filter-caddylatch.caddy${NC}"
        echo ""
        echo "  All site blocks that 'import geo_filter' will continue working"
        echo "  unchanged — CaddyLatch provides the same snippet name."
        echo ""
    fi
fi

echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Installation complete          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Edit ${CONFIG_DST}"
echo "     - Set listen_host to your Tailscale IP"
echo "     - Set ntfy_url and ntfy_topic"
echo "     - Set healthchecks_url (optional)"
echo ""
echo "  2. Update Caddy to use CaddyLatch's filter:"
echo "     - Remove (geo_filter) snippet from Caddyfile"
echo "     - Add: import /etc/caddy/filter-caddylatch.caddy"
echo "     - Reload: sudo systemctl reload caddy"
echo ""
echo "  3. Start CaddyLatch:"
echo "     sudo systemctl enable --now caddylatch"
echo ""
echo "  4. Verify:"
echo "     curl -s http://<tailscale-ip>:8450/health"
echo "     curl -s http://<tailscale-ip>:8450/status"
echo ""
