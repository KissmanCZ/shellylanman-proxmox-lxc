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

setup_deb_based() {
  if [[ ! -d /opt || -L /opt ]]; then
    msg_error "The /opt directory is missing or is a symbolic link. Installation cancelled."
    exit 1
  fi
  if [[ ! -d /usr/local/bin || -L /usr/local/bin || ! -d /etc/systemd/system || -L /etc/systemd/system ]]; then
    msg_error "A required system directory is missing or is a symbolic link. Installation cancelled."
    exit 1
  fi
  for target in \
    /opt/shellylanman \
    /opt/shellylanman_data \
    /usr/local/bin/shellylanman \
    /etc/systemd/system/shellylanman.service; do
    if [[ -e "$target" || -L "$target" ]]; then
      msg_error "Refusing to overwrite an existing path: ${target}. Use a fresh LXC or inspect the existing installation first."
      exit 1
    fi
  done
  if systemctl cat shellylanman.service >/dev/null 2>&1; then
    msg_error "A ShellyLanMan systemd unit already exists. Installation cancelled to protect the existing service."
    exit 1
  fi

  msg_info "Installing ShellyLanMan build dependencies"
  $STD env DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends build-essential tzdata
  msg_ok "Installed ShellyLanMan build dependencies"

  fetch_and_deploy_gh_release "shellylanman" "wimmme/shellylanman" "tarball" "latest" "/opt/shellylanman"

  if [[ ! -d /opt/shellylanman || -L /opt/shellylanman || ! -d /opt/shellylanman/web || -L /opt/shellylanman/web || ! -f /opt/shellylanman/go.mod || ! -f /opt/shellylanman/web/package-lock.json ]]; then
    msg_error "The downloaded ShellyLanMan source archive is incomplete."
    exit 1
  fi

  NODE_VERSION="26" setup_nodejs
  GO_VERSION="$(awk '$1 == "go" { print $2; exit }' /opt/shellylanman/go.mod)"
  if [[ ! "$GO_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    msg_error "Could not determine a valid Go version from the upstream go.mod."
    exit 1
  fi
  GO_VERSION="$GO_VERSION" setup_go

  msg_info "Building the ShellyLanMan frontend"
  cd /opt/shellylanman/web
  $STD npm ci --no-audit --no-fund
  $STD npm run typecheck
  $STD npm test
  $STD npm run build
  msg_ok "Built the ShellyLanMan frontend"

  msg_info "Checking and building ShellyLanMan"
  cd /opt/shellylanman
  if [[ -L internal || -L internal/web || -L internal/web/dist || -L web/dist ]]; then
    msg_error "A symbolic link was found in a build asset path. Installation cancelled."
    exit 1
  fi
  if [[ ! -d web/dist || -L web/dist || ( -e internal/web/dist && ! -d internal/web/dist ) ]]; then
    msg_error "The built frontend or Go embed destination is missing or unsafe. Installation cancelled."
    exit 1
  fi
  install -d -m 0755 internal/web/dist
  cp -a -- web/dist/. internal/web/dist/

  UNFORMATTED="$(gofmt -l .)"
  if [[ -n "$UNFORMATTED" ]]; then
    printf '%s\n' "$UNFORMATTED"
    msg_error "ShellyLanMan Go source is not gofmt-formatted."
    exit 1
  fi

  $STD go mod download
  $STD go vet ./...
  $STD go test -race -count=1 ./...

  if [[ ! -f "$HOME/.shellylanman" || -L "$HOME/.shellylanman" ]]; then
    msg_error "The Community Scripts release helper did not create a safe application version file."
    exit 1
  fi
  APP_VERSION="$(<"$HOME/.shellylanman")"
  APP_VERSION="${APP_VERSION#v}"
  if [[ ! "$APP_VERSION" =~ ^[0-9A-Za-z.+_-]+$ ]]; then
    msg_error "The upstream release version contains unsupported characters. Installation cancelled."
    exit 1
  fi

  BUILD_BINARY="$(mktemp /usr/local/bin/.shellylanman.new.XXXXXX)"
  $STD env CGO_ENABLED=0 go build -trimpath \
    -ldflags="-s -w -X github.com/wimmme/shellylanman/internal/version.Version=${APP_VERSION}" \
    -o "$BUILD_BINARY" ./cmd/shellylanman
  chmod 0755 "$BUILD_BINARY"
  if [[ -e /usr/local/bin/shellylanman || -L /usr/local/bin/shellylanman ]]; then
    msg_error "The ShellyLanMan executable path unexpectedly exists. Installation cancelled rather than overwriting it."
    exit 1
  fi
  mv -T -- "$BUILD_BINARY" /usr/local/bin/shellylanman
  msg_ok "Built ShellyLanMan ${APP_VERSION}"

  msg_info "Creating the ShellyLanMan data directory and configuration"
  install -d -o root -g root -m 0700 /opt/shellylanman_data
  cat <<'EOF_CONFIG' >/opt/shellylanman_data/shellylanman.env
# ShellyLanMan runtime configuration.
SHELLYLANMAN_DATA=/opt/shellylanman_data
# Optional: uncomment to pin the web UI/API port (otherwise it defaults to 3082).
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
WorkingDirectory=/opt/shellylanman_data
EnvironmentFile=/opt/shellylanman_data/shellylanman.env
ExecStart=/usr/local/bin/shellylanman
Restart=on-failure
RestartSec=5s
TimeoutStopSec=20s
UMask=0077
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF_SERVICE
  systemctl enable -q --now shellylanman
  msg_ok "Created and started the ShellyLanMan service"

  msg_info "Checking ShellyLanMan health"
  HEALTHY=0
  for attempt in $(seq 1 30); do
    if systemctl is-active --quiet shellylanman && SHELLYLANMAN_DATA=/opt/shellylanman_data /usr/local/bin/shellylanman -healthcheck; then
      HEALTHY=1
      break
    fi
    sleep 1
  done

  if ((HEALTHY != 1)); then
    journalctl -u shellylanman --no-pager -n 80
    msg_error "ShellyLanMan did not become healthy."
    exit 1
  fi
  msg_ok "ShellyLanMan is healthy"
}

run_os_setup
motd_ssh
customize
cleanup_lxc
