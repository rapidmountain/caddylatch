#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then error "Must be run as root"; exit 1; fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       CaddyLatch Installer           ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# Directories
info "Creating directories..."
mkdir -p "${CONFIG_DIR}" "${STATE_DIR}" "${LOG_DIR}"
chmod 750 "${CONFIG_DIR}" "${STATE_DIR}" "${LOG_DIR}"

# Config merge
config_merge() {
    local template="$1" existing="$2"
    trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; echo "$v"; }

    declare -A tmpl_keys exist_keys exist_values
    while IFS= read -r line; do
        local lt; lt="$(trim "$line")"
        [[ -z "$lt" || "$lt" == \#* ]] && continue
        if [[ "$lt" == *=* ]]; then
            local k; k="$(trim "${lt%%=*}")"
            local v; v="$(trim "${lt#*=}")"
            tmpl_keys["$k"]="$v"
        fi
    done < "$template"

    while IFS= read -r line; do
        local lt; lt="$(trim "$line")"
        [[ -z "$lt" || "$lt" == \#* ]] && continue
        if [[ "$lt" == *=* ]]; then
            local k; k="$(trim "${lt%%=*}")"
            local v; v="$(trim "${lt#*=}")"
            exist_keys["$k"]=1
            exist_values["$k"]="$v"
        fi
    done < "$existing"

    local new_keys=() removed_keys=()
    for k in "${!tmpl_keys[@]}"; do
        [[ -z "${exist_keys[$k]+x}" ]] && new_keys+=("$k")
    done
    for k in "${!exist_keys[@]}"; do
        [[ -z "${tmpl_keys[$k]+x}" ]] && removed_keys+=("$k")
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
        for k in "${new_keys[@]}"; do echo -e "    + ${k}=${tmpl_keys[$k]}"; done
    fi
    if [[ ${#removed_keys[@]} -gt 0 ]]; then
        echo -e "  ${RED}Removed settings:${NC}"
        for k in "${removed_keys[@]}"; do echo -e "    - ${k}=${exist_values[$k]}"; done
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
            local tmp; tmp="$(mktemp)"
            while IFS= read -r line; do
                local lt; lt="$(trim "$line")"
                if [[ -z "$lt" || "$lt" == \#* ]]; then echo "$line" >> "$tmp"; continue; fi
                if [[ "$lt" == *=* ]]; then
                    local k; k="$(trim "${lt%%=*}")"
                    if [[ -n "${exist_values[$k]+x}" ]]; then
                        echo "${k}=${exist_values[$k]}" >> "$tmp"
                    else
                        echo "$line" >> "$tmp"
                    fi
                else
                    echo "$line" >> "$tmp"
                fi
            done < "$template"
            cp "$tmp" "$existing"; rm -f "$tmp"
            info "Config merged successfully."
            ;;
        2) warn "Overwriting..."; cp "$template" "$existing"; info "Config overwritten." ;;
        3) info "Keeping existing config unchanged." ;;
        *) warn "Invalid choice — keeping existing config." ;;
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

# Executable
info "Symlinking executable..."
chmod +x "$EXECUTABLE_SRC"
ln -sf "$EXECUTABLE_SRC" "$EXECUTABLE_DST"

# Systemd
info "Installing systemd service..."
cp "$SERVICE_SRC" "$SERVICE_DST"
systemctl daemon-reload

# Caddy filter file
if [[ ! -f "$CADDY_FILTER" ]]; then
    info "Creating locked filter file: ${CADDY_FILTER}"
    cat > "$CADDY_FILTER" << 'EOF'
# Managed by CaddyLatch — do not edit manually.
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

# Check Caddyfile
CADDYFILE="/etc/caddy/Caddyfile"
if [[ -f "$CADDYFILE" ]] && grep -q "(geo_filter)" "$CADDYFILE"; then
    echo ""
    warn "Your Caddyfile contains a (geo_filter) snippet definition."
    echo "  CaddyLatch manages geo_filter dynamically via ${CADDY_FILTER}."
    echo "  Replace the (geo_filter) snippet in ${CADDYFILE} with:"
    echo ""
    echo -e "       ${CYAN}import /etc/caddy/filter-caddylatch.caddy${NC}"
    echo ""
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Installation complete          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Edit ${CONFIG_DST} — set listen_host, ntfy settings"
echo "  2. Update Caddy: import /etc/caddy/filter-caddylatch.caddy"
echo "  3. Start: sudo systemctl enable --now caddylatch"
echo "  4. Verify: curl -s http://<tailscale-ip>:8450/health"
echo ""
