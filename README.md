# CaddyLatch

On-demand access controller for Caddy edge proxies with WireGuard tunnels.

**Default state: locked.** Your services are unreachable from the public internet. CaddyLatch opens access on demand — scoped by IP, country, and time — then locks itself automatically.

## What it does

CaddyLatch controls two things on your edge VPS:

1. **WireGuard tunnel** — up when open, down when locked
2. **Caddy geo/IP filter** — dynamically written, blocks everything when locked

When you open the latch, traffic matching your specified countries and IPs flows through. When the timer expires (or you close it manually), both layers lock down. Your services disappear from the internet.

## Requirements

- **Caddy** with [caddy-maxmind-geolocation](https://github.com/porech/caddy-maxmind-geolocation) plugin
- **WireGuard** managed by `wg-quick` systemd units
- **MaxMind GeoLite2-Country** database (for geo filtering)
- **Python 3.10+** (stdlib only, no pip dependencies)

## Architecture

```
You (phone/laptop)                   Edge VPS                    Home
     │                                  │                          │
     │  toggle via web app              │                          │
     │  or curl (Tailscale)             │                          │
     ├──────────────────────►  CaddyLatch API (:8450)              │
     │                          │  start/stop WireGuard            │
     │                          │  write Caddy filters             │
     │                          │  enforce timer                   │
     │                          │                                  │
     │                        Caddy (geo + IP filter)              │
Work laptop ──────────────►     │                                  │
     (when latch is open)       ├──── WireGuard tunnel ──────────► Caddy (home)
                                │                                  │  ──► services
```

- **Control plane:** Tailscale (or any trusted network) — API never publicly exposed
- **Data plane:** WireGuard — only active when latch is open
- Home-side WireGuard stays always-on; CaddyLatch on the VPS is the sole gatekeeper

## Install

```bash
git clone https://github.com/yourorg/caddylatch.git /opt/caddylatch
cd /opt/caddylatch
sudo ./install.sh
```

Edit `/etc/caddylatch/caddylatch.conf`:
```
listen_host=100.x.x.x          # Your Tailscale IP
ntfy_url=https://ntfy.example.com
ntfy_topic=caddylatch
```

Update your Caddyfile — replace the static `(geo_filter)` snippet with:
```
import /etc/caddy/filter-caddylatch.caddy
```

All site blocks that `import geo_filter` continue working unchanged.

Start it:
```bash
sudo systemctl enable --now caddylatch
sudo systemctl reload caddy
```

## API

All endpoints are JSON. No authentication — access is network-restricted (Tailscale/localhost).

### GET /health
Health check. Always returns `200`.

### GET /status
Current latch state including WireGuard status.

### POST /enable
Open the latch.
```json
{
  "allowed_ips": ["203.0.113.10/32"],
  "allowed_countries": ["SE", "DK"],
  "duration_minutes": 120
}
```
Both `allowed_ips` and `allowed_countries` are optional, but at least one is required. If both are specified, traffic must match **both** (allowed country AND allowed IP).

### POST /disable
Close the latch immediately.

### POST /extend
Add time to the current session.
```json
{
  "additional_minutes": 60
}
```

### POST /update-filters
Change allowed IPs/countries without restarting the timer.
```json
{
  "allowed_ips": ["203.0.113.10/32", "203.0.113.11/32"],
  "allowed_countries": ["SE"]
}
```

## Safety features

- **Auto-close timer** — the latch locks itself after the configured duration
- **Max duration cap** — cannot extend beyond `max_duration_minutes`
- **Reboot persistence** — remembers state across restarts; if timer expired while offline, locks immediately on startup
- **Notifications** — ntfy alerts on every state change + periodic "still open" reminders
- **Healthchecks.io** — dead man's switch; alerts if the agent stops running
- **Double kill switch** — WireGuard down AND Caddy filters locked when disabled

## Uninstall

```bash
cd /opt/caddylatch
sudo ./uninstall.sh
```

Restore your original `(geo_filter)` snippet in the Caddyfile and reload Caddy.

## License

MIT
