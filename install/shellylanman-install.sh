#!/usr/bin/env bash
# Copyright (c) 2026 Jan Pichrt
# Author: Jan Pichrt (KissmanCZ)
# License: MIT
# Source: https://github.com/wimmme/shellylanman

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing ShellyLanMan build dependencies"
$STD apt install -y --no-install-recommends build-essential tzdata
msg_ok "Installed ShellyLanMan build dependencies"

NODE_VERSION="26" setup_nodejs
setup_go

fetch_and_deploy_gh_release "shellylanman" "wimmme/shellylanman" "tarball"

msg_info "Building the ShellyLanMan frontend"
cd /opt/shellylanman/web
$STD npm ci --no-audit --no-fund
$STD npm run typecheck
$STD npm test
$STD npm run build
msg_ok "Built the ShellyLanMan frontend"

msg_info "Checking and building ShellyLanMan"
cd /opt/shellylanman
rm -rf internal/web/dist
install -d -m 0755 internal/web/dist
cp -a web/dist/. internal/web/dist/

UNFORMATTED="$(gofmt -l .)"
if [[ -n "$UNFORMATTED" ]]; then
  printf '%s\n' "$UNFORMATTED"
  msg_error "ShellyLanMan Go source is not gofmt-formatted."
  exit 1
fi

$STD go mod download
$STD go vet ./...
$STD go test -race -count=1 ./...

APP_VERSION="$(cat ~/.shellylanman)"
APP_VERSION="${APP_VERSION#v}"
$STD env CGO_ENABLED=0 go build -trimpath \
  -ldflags="-s -w -X github.com/wimmme/shellylanman/internal/version.Version=${APP_VERSION}" \
  -o /usr/local/bin/shellylanman ./cmd/shellylanman
chmod 0755 /usr/local/bin/shellylanman
msg_ok "Built ShellyLanMan ${APP_VERSION}"

msg_info "Creating the ShellyLanMan data directory and configuration"
install -d -m 0700 /opt/shellylanman_data
cat <<'EOF_CONFIG' >/opt/shellylanman_data/shellylanman.env
# ShellyLanMan runtime configuration.
SHELLYLANMAN_DATA=/opt/shellylanman_data
# Optional: uncomment to pin the web UI/API port (otherwise it defaults to 3082
# and can be changed in Settings -> General -> Ports).
# SHELLYLANMAN_PORT=3082
# Optional: comma-separated host names allowed behind a reverse proxy.
# SHELLYLANMAN_ORIGINS=shelly.example.net
# Forgotten UI password: set to 1 for one start, restart the service, then remove.
# SHELLYLANMAN_RESET_PASSWORD=1
EOF_CONFIG
chmod 0600 /opt/shellylanman_data/shellylanman.env
msg_ok "Created the ShellyLanMan data directory and configuration"

msg_info "Creating the ShellyLanMan service"
cat <<'EOF_SERVICE' >/etc/systemd/system/shellylanman.service
[Unit]
Description=ShellyLanMan - Shelly LAN management
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/shellylanman
EnvironmentFile=/opt/shellylanman_data/shellylanman.env
ExecStart=/usr/local/bin/shellylanman
Restart=on-failure
RestartSec=5s
TimeoutStopSec=20s
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/shellylanman_data
RestrictSUIDSGID=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
EOF_SERVICE
systemctl enable -q --now shellylanman
msg_ok "Created and started the ShellyLanMan service"

msg_info "Checking ShellyLanMan health"
HEALTHY=0
for attempt in $(seq 1 30); do
  if SHELLYLANMAN_DATA=/opt/shellylanman_data /usr/local/bin/shellylanman -healthcheck; then
    HEALTHY=1
    break
  fi
  sleep 1
done

if (( HEALTHY != 1 )); then
  journalctl -u shellylanman --no-pager -n 80
  msg_error "ShellyLanMan did not become healthy."
  exit 1
fi
msg_ok "ShellyLanMan is healthy"

cat <<'EOF_MOTD' >/etc/motd
ShellyLanMan is installed.

Web UI:        http://<container-ip>:3082 (default port)
Service:       systemctl status shellylanman
Logs:          journalctl -u shellylanman -f
Configuration: /opt/shellylanman_data/shellylanman.env
Data:          /opt/shellylanman_data

Security: the UI password is off by default. Set one in Settings -> Security
before allowing access beyond a trusted LAN. Do not expose this service directly
to the internet.

mDNS discovery needs multicast traffic to pass between this LXC and Shelly devices.
For initial setup, place the LXC on the same VLAN as the Shelly devices. For routed
VLANs, configure an mDNS reflector or use IP-range discovery.
EOF_MOTD

motd_ssh
customize
cleanup_lxc
