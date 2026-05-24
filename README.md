# CaddyLatch

On-demand access controller for Caddy edge proxies with WireGuard tunnels.

**Default state: locked.** Your services are unreachable from the public internet. CaddyLatch opens access on demand — scoped by IP, country, and time — then locks itself automatically.

## What it does

CaddyLatch controls two things on your edge VPS:

1. **WireGuard tunnel** — up when open, down when locked
2. **Caddy geo/IP filter** — dynamically written, blocks everything when locked

When you open the latch, traffic matching your specified countries and IPs flows through. When the timer expires (or you close it manually), both layers lock down.

## Requirements

- **Caddy** with [caddy-maxmind-geolocation](https://github.com/porech/caddy-maxmind-geolocation) plugin
- **WireGuard** managed by `wg-quick` systemd units
- **MaxMind GeoLite2-Country** database
- **Python 3.10+** (stdlib only, no pip dependencies)

## Install

```bash
git clone https://github.com/yourorg/caddylatch.git /opt/caddylatch
cd /opt/caddylatch
sudo bash install.sh
```

Edit `/etc/caddylatch/caddylatch.conf`, then update your Caddyfile to replace the static `(geo_filter)` snippet with:

```
import /etc/caddy/filter-caddylatch.caddy
```

Start:

```bash
sudo systemctl enable --now caddylatch
sudo systemctl reload caddy
```

## API

All endpoints are JSON. No authentication — access is network-restricted (Tailscale/localhost).

### Core

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check |
| `GET` | `/status` | Current state + WireGuard status |
| `GET` | `/stats` | Operational stats (uptime, WG transfer, etc.) |
| `POST` | `/enable` | Open the latch |
| `POST` | `/disable` | Close the latch |
| `POST` | `/extend` | Add time to current session |
| `POST` | `/update-filters` | Change filters mid-session |

### IP Lists

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/ip-lists` | Get all saved IP lists |
| `PUT` | `/ip-lists/{name}` | Create or update a list |
| `DELETE` | `/ip-lists/{name}` | Delete a list |

### POST /enable

```json
{
  "allowed_countries": ["SE", "DK"],
  "all_countries": false,
  "allowed_ips": ["203.0.113.10/32"],
  "allowed_ip_lists": ["Work IPs"],
  "duration_minutes": 120
}
```

- `all_countries: true` — disables geo filtering entirely
- `allowed_ip_lists` — references saved IP lists by name, resolved at enable time
- `duration_minutes: 0` — no timer, stays open until manual disable
- `duration_minutes: null` — uses configured default

### PUT /ip-lists/{name}

```json
{
  "ips": ["10.0.1.0/24", "10.0.2.0/24"]
}
```

Creates the list if it doesn't exist, updates it if it does.

## Safety features

- **Auto-close timer** — locks after configured duration
- **Max duration cap** — cannot extend beyond limit
- **Reboot persistence** — remembers state; expired-while-offline = immediate lock
- **Double kill switch** — WireGuard down AND Caddy filters locked
- **Notifications** — ntfy on every state change + periodic reminders
- **Healthchecks.io** — dead man's switch

## Uninstall

```bash
cd /opt/caddylatch
sudo bash uninstall.sh
```

## License

MIT
