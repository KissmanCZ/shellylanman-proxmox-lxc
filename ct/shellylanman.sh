#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/KissmanCZ/shellylanman-proxmox-lxc/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2026 Jan Pichrt
# Author: Jan Pichrt (KissmanCZ)
# License: MIT
# Source: https://github.com/wimmme/shellylanman

APP="ShellyLanMan"
var_tags="${var_tags:-network;home-automation;shelly}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_arm64="${var_arm64:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /usr/local/bin/shellylanman || ! -d /opt/shellylanman ]]; then
    msg_error "No ShellyLanMan installation found!"
    exit 1
  fi

  if check_for_gh_release "shellylanman" "wimmme/shellylanman"; then
    create_backup /opt/shellylanman_data/shellylanman.env
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "shellylanman" "wimmme/shellylanman" "tarball"
    restore_backup

    NODE_VERSION="26" setup_nodejs
    setup_go

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
    rm -f /usr/local/bin/shellylanman.new
    $STD env CGO_ENABLED=0 go build -trimpath \
      -ldflags="-s -w -X github.com/wimmme/shellylanman/internal/version.Version=${APP_VERSION}" \
      -o /usr/local/bin/shellylanman.new ./cmd/shellylanman
    chmod 0755 /usr/local/bin/shellylanman.new
    msg_ok "Built ShellyLanMan ${APP_VERSION}"

    msg_info "Stopping ShellyLanMan"
    systemctl stop shellylanman
    msg_ok "Stopped ShellyLanMan"

    msg_info "Activating the ShellyLanMan update"
    rm -f /usr/local/bin/shellylanman.previous
    if ! mv -f /usr/local/bin/shellylanman /usr/local/bin/shellylanman.previous; then
      systemctl start shellylanman || true
      msg_error "Could not preserve the previous ShellyLanMan binary; update cancelled."
      exit 1
    fi
    if ! mv -f /usr/local/bin/shellylanman.new /usr/local/bin/shellylanman; then
      mv -f /usr/local/bin/shellylanman.previous /usr/local/bin/shellylanman || true
      systemctl start shellylanman || true
      msg_error "Could not activate the new ShellyLanMan binary; the previous binary was restored."
      exit 1
    fi

    systemctl start shellylanman || true
    HEALTHY=0
    for attempt in $(seq 1 30); do
      if SHELLYLANMAN_DATA=/opt/shellylanman_data /usr/local/bin/shellylanman -healthcheck; then
        HEALTHY=1
        break
      fi
      sleep 1
    done

    if (( HEALTHY == 1 )); then
      rm -f /usr/local/bin/shellylanman.previous
      msg_ok "Updated ShellyLanMan successfully to ${APP_VERSION}."
    else
      systemctl stop shellylanman || true
      mv -f /usr/local/bin/shellylanman.previous /usr/local/bin/shellylanman
      systemctl start shellylanman || true
      msg_error "ShellyLanMan update failed; the previous binary was restored."
      exit 1
    fi
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}ShellyLanMan setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${LOCAL_IP}:3082${CL}"
