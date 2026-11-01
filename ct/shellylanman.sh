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
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_arm64="${var_arm64:-no}"

header_info "$APP"
variables
color
catch_errors

update_deb_based() {
  ensure_profile_loaded

  if [[ ! -d /opt || -L /opt || ! -d /opt/shellylanman || -L /opt/shellylanman ]]; then
    msg_error "ShellyLanMan source directory is missing or is not a real directory. Update cancelled."
    exit 1
  fi
  if mountpoint -q /opt/shellylanman || findmnt -rn -o TARGET | grep -Eq '^/opt/shellylanman(/|$)'; then
    msg_error "A mount point exists at or below the ShellyLanMan source path. Update cancelled to protect mounted data."
    exit 1
  fi
  if [[ ! -d /opt/shellylanman_data || -L /opt/shellylanman_data || ! -f /opt/shellylanman_data/shellylanman.env || -L /opt/shellylanman_data/shellylanman.env ]]; then
    msg_error "ShellyLanMan data directory or environment file is missing or unsafe. Update cancelled."
    exit 1
  fi
  if [[ ! -f /usr/local/bin/shellylanman || -L /usr/local/bin/shellylanman || ! -x /usr/local/bin/shellylanman ]]; then
    msg_error "ShellyLanMan executable is missing or is not a regular executable file. Update cancelled."
    exit 1
  fi
  if [[ ! -d /usr/local/bin || -L /usr/local/bin || ! -d "$HOME" || -L "$HOME" || ! -f "$HOME/.shellylanman" || -L "$HOME/.shellylanman" ]]; then
    msg_error "ShellyLanMan binary or release metadata paths are missing or unsafe. Update cancelled."
    exit 1
  fi
  if [[ ! -f /etc/systemd/system/shellylanman.service || -L /etc/systemd/system/shellylanman.service ]]; then
    msg_error "ShellyLanMan systemd service file is missing or unsafe. Update cancelled."
    exit 1
  fi
  if ! systemctl is-active --quiet shellylanman; then
    msg_error "ShellyLanMan service is not active. Start or repair it before updating."
    exit 1
  fi
  if ! SHELLYLANMAN_DATA=/opt/shellylanman_data /usr/local/bin/shellylanman -healthcheck; then
    msg_error "ShellyLanMan currently fails its health check. The update was not started."
    exit 1
  fi

  if check_for_gh_release "shellylanman" "wimmme/shellylanman"; then
    INSTALLED_VERSION="$(<"$HOME/.shellylanman")"
    if [[ ! "$INSTALLED_VERSION" =~ ^[0-9A-Za-z.+_-]+$ ]]; then
      msg_error "The installed ShellyLanMan release marker is invalid. Update cancelled."
      exit 1
    fi

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "shellylanman" "wimmme/shellylanman" "tarball" "latest" "/opt/shellylanman"

    if [[ ! -f "$HOME/.shellylanman" || -L "$HOME/.shellylanman" ]]; then
      msg_error "The Community Scripts release helper did not create a safe application version file."
      exit 1
    fi
    RELEASE_MARKER="$(<"$HOME/.shellylanman")"
    # Restore the installed release marker atomically so a failed build remains retryable.
    VERSION_RESTORE="$(mktemp "$HOME/.shellylanman.restore.XXXXXX")"
    printf '%s' "$INSTALLED_VERSION" >"$VERSION_RESTORE"
    chmod 0600 "$VERSION_RESTORE"
    if ! mv -fT -- "$VERSION_RESTORE" "$HOME/.shellylanman"; then
      msg_error "Could not restore the installed release marker. Update cancelled."
      exit 1
    fi

    if [[ ! -d /opt/shellylanman || -L /opt/shellylanman || ! -f /opt/shellylanman/go.mod || ! -f /opt/shellylanman/web/package-lock.json ]]; then
      msg_error "The downloaded ShellyLanMan source archive is incomplete. The running binary was not changed."
      exit 1
    fi
    if [[ ! "$RELEASE_MARKER" =~ ^v?[0-9A-Za-z.+_-]+$ ]]; then
      msg_error "The upstream release marker contains unsupported characters. Update cancelled."
      exit 1
    fi
    APP_VERSION="${RELEASE_MARKER#v}"
    if [[ ! "$APP_VERSION" =~ ^[0-9A-Za-z.+_-]+$ ]]; then
      msg_error "The upstream release version contains unsupported characters. Update cancelled."
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
      msg_error "A symbolic link was found in a build asset path. Update cancelled."
      exit 1
    fi
    if [[ ! -d web/dist || -L web/dist || ( -e internal/web/dist && ! -d internal/web/dist ) ]]; then
      msg_error "The built frontend or Go embed destination is missing or unsafe. Update cancelled."
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

    BUILD_BINARY="$(mktemp /usr/local/bin/.shellylanman.new.XXXXXX)"
    $STD env CGO_ENABLED=0 go build -trimpath \
      -ldflags="-s -w -X github.com/wimmme/shellylanman/internal/version.Version=${APP_VERSION}" \
      -o "$BUILD_BINARY" ./cmd/shellylanman
    chmod 0755 "$BUILD_BINARY"
    msg_ok "Built ShellyLanMan ${APP_VERSION}"

    ROLLBACK_BINARY="$(mktemp /usr/local/bin/shellylanman.previous.XXXXXX)"
    if ! cp -a -- /usr/local/bin/shellylanman "$ROLLBACK_BINARY"; then
      msg_error "Could not preserve the current ShellyLanMan binary. The running installation was not changed."
      exit 1
    fi

    msg_info "Activating the ShellyLanMan update"
    if ! systemctl stop shellylanman; then
      msg_error "Could not stop ShellyLanMan. The existing binary was not changed."
      exit 1
    fi
    if ! mv -fT -- "$BUILD_BINARY" /usr/local/bin/shellylanman; then
      systemctl start shellylanman || true
      msg_error "Could not activate the new ShellyLanMan binary. The previous binary remains in place."
      exit 1
    fi

    if ! systemctl start shellylanman; then
      RESTORE_BINARY="$(mktemp /usr/local/bin/.shellylanman.restore.XXXXXX)"
      if ! cp -a -- "$ROLLBACK_BINARY" "$RESTORE_BINARY" || ! mv -fT -- "$RESTORE_BINARY" /usr/local/bin/shellylanman; then
        msg_error "ShellyLanMan failed to start and automatic binary restoration failed. The previous binary is retained at ${ROLLBACK_BINARY}."
        exit 1
      fi
      systemctl start shellylanman || { msg_error "The previous ShellyLanMan binary was restored, but its service did not start. Check the service journal."; exit 1; }
      msg_error "The new ShellyLanMan service failed to start. The previous binary was restored."
      exit 1
    fi

    HEALTHY=0
    for attempt in $(seq 1 30); do
      if systemctl is-active --quiet shellylanman && SHELLYLANMAN_DATA=/opt/shellylanman_data /usr/local/bin/shellylanman -healthcheck; then
        HEALTHY=1
        break
      fi
      sleep 1
    done

    if ((HEALTHY != 1)); then
      if ! systemctl stop shellylanman; then
        msg_error "The new ShellyLanMan binary failed its health check and the service could not be stopped. The previous binary is retained at ${ROLLBACK_BINARY}."
        exit 1
      fi
      RESTORE_BINARY="$(mktemp /usr/local/bin/.shellylanman.restore.XXXXXX)"
      if ! cp -a -- "$ROLLBACK_BINARY" "$RESTORE_BINARY" || ! mv -fT -- "$RESTORE_BINARY" /usr/local/bin/shellylanman; then
        msg_error "ShellyLanMan update failed and the previous binary could not be restored. The backup is retained at ${ROLLBACK_BINARY}."
        exit 1
      fi
      systemctl start shellylanman || { msg_error "The previous ShellyLanMan binary was restored, but its service did not start. Check the service journal."; exit 1; }
      msg_error "ShellyLanMan update failed its health check. The previous binary was restored."
      exit 1
    fi

    VERSION_MARKER="$(mktemp "$HOME/.shellylanman.new.XXXXXX")"
    printf '%s' "$RELEASE_MARKER" >"$VERSION_MARKER"
    chmod 0600 "$VERSION_MARKER"
    if ! mv -fT -- "$VERSION_MARKER" "$HOME/.shellylanman"; then
      msg_error "ShellyLanMan is healthy, but its release marker could not be updated. The update will be retried on the next run."
      exit 1
    fi
    msg_ok "Updated ShellyLanMan successfully to ${APP_VERSION}. The previous binary is retained at ${ROLLBACK_BINARY}."
  fi
}

function update_script() {
  header_info
  ensure_profile_loaded
  check_container_storage
  check_container_resources
  run_os_update
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}ShellyLanMan setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3082${CL}"
