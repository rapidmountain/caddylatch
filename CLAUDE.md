# CaddyLatch — Project Context for Claude Code

## What is CaddyLatch?
An on-demand access controller for Caddy edge proxies with WireGuard tunnels. Default state: locked — services are unreachable from the public internet. CaddyLatch opens access on demand, scoped by IP, country, and time, then locks itself automatically.

It controls two things on the edge VPS:
1. **WireGuard tunnel** — up when open, down when locked
2. **Caddy geo/IP filter** — dynamically written, blocks everything when locked

## Architecture
- **Python 3.10+ backend** (stdlib only, no pip dependencies): Core daemon with JSON API
- **Web UI** (`web/`): HTML frontend for controlling the latch
- **Systemd integration** (`systemd/`): Service unit for the daemon
- **Caddy integration**: Generates dynamic filter snippets imported by the Caddyfile
- **WireGuard integration**: Controls `wg-quick` systemd units
- **MaxMind GeoLite2-Country**: Geo-filtering database

## API
All endpoints are JSON, no authentication — access is network-restricted (Tailscale/localhost).

Core: GET /health, /status, /stats | POST /enable, /disable, /extend, /update-filters
IP Lists: GET /ip-lists | PUT /ip-lists/{name} | DELETE /ip-lists/{name}

## Deployment Target
- Runs on an edge VPS (not on AshNet directly)
- Installed to `/opt/caddylatch`
- Config at `/etc/caddylatch/caddylatch.conf`
- Caddy filter output: `/etc/caddy/filter-caddylatch.caddy`
- Notifications via ntfy
- Dead man's switch via Healthchecks.io

## Coding Conventions
- Python 3.10+, stdlib only — no external dependencies
- Shell scripts: bash, POSIX-friendly where possible
- Commit messages: descriptive, reference issue numbers
- Web UI: vanilla HTML/JS (no frameworks)

## GitHub Workflow
- **main** branch: stable, deployable
- **dev** branch: active development, Claude Code works here
- **Feature branches**: task/issue-{number} for individual issues
- Determine branch strategy by checking the Issue labels:
  - bug label → commit directly to dev
  - enhancement label → create branch task/issue-{number}, then PR to dev
- Squash merge dev → main when ready for deployment

## GitHub Project: "CaddyLatch Backlog"
Project Reference: GitHub Project #3

Columns: Backlog → Refined → Ready for sprint → In progress → In review → Blocked → Done

Use the gh CLI to interact with the project board:
- gh project item-list to find items
- gh project item-edit to move cards between columns
- gh issue view <number> to read full requirements before starting work

**When moving project cards: always verify the move succeeded by checking the item status after the command. gh project item-edit returns no output on both success and failure — never assume it worked without checking.**

To move a card:
1. Run gh project item-edit with --id, --project-id, --field-id, and --single-select-option-id
2. Immediately verify: gh project item-list 3 --owner rapidmountain --format json and check the item's status field
3. If the status does not match the intended column, diagnose and retry with corrected syntax

Blocked — items that cannot proceed due to external dependencies. Include a comment explaining what is blocking and a link to the external issue.

When told to work on issues:
1. Read the full issue description with gh issue view <number>
2. Check the issue labels to determine branch strategy (bug → dev, enhancement → new branch)
3. Move the issue card to "In progress" and verify the move succeeded
4. Implement the fix/feature
5. Commit referencing the issue (e.g., "Fix timer persistence (#3)")
6. Push
7. For enhancements: create a PR from the feature branch to dev
8. Merge the feature branch into dev: checkout dev, merge the branch, commit, and push dev. Do not leave feature branches unmerged.
9. Move issue card to "In review" and verify the move succeeded
10. Leave a comment on the issue with: (a) what was changed and which files were modified, (b) clear validation steps the reviewer can follow to verify the fix works correctly
11. Work on issues one at a time, in the order given

## Labels
- bug — something broken → work directly on dev
- enhancement — new functionality or improvement → create feature branch
- documentation — docs changes
- duplicate — duplicate issue
- priority: high — urgent
- priority: low — can wait

## Install & Test
```bash
sudo bash install.sh
sudo systemctl enable --now caddylatch
sudo systemctl reload caddy
```

## Verification
Before moving any issue to "In review":
1. Python syntax check: `python3 -m py_compile caddylatch`
2. No hardcoded credentials or paths that should be configurable
3. All API responses must be valid JSON
