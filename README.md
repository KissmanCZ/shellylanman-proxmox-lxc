# ShellyLanMan — Proxmox VE LXC installer

A third-party, bare-metal Debian LXC installer for [ShellyLanMan](https://github.com/wimmme/shellylanman). It does **not** install Docker or run a Docker container.

Maintained by [Jan Pichrt (@KissmanCZ)](https://github.com/KissmanCZ). Repository: [KissmanCZ/shellylanman-proxmox-lxc](https://github.com/KissmanCZ/shellylanman-proxmox-lxc).

> **Status:** experimental community installer. Bash syntax and metadata validation are checked, but the full installation has not yet been run on a real Proxmox VE host. Test on a disposable host before relying on it in production.

## What it installs

- Debian 13, unprivileged LXC by default.
- ShellyLanMan built from the official GitHub release source archive.
- Node.js 26 and the current stable Go toolchain installed **inside the LXC** with Community Scripts Core helpers. Nothing is installed on the Proxmox host.
- The upstream frontend checks/build (`npm ci`, typecheck, tests, build), followed by Go formatting, vet, race-enabled tests and a static Linux binary build.
- A systemd service named `shellylanman`, running as root inside the unprivileged LXC in line with the current Community Scripts service convention (the container's root is user-namespace mapped on the Proxmox host).
- Persistent application data and runtime configuration in `/opt/shellylanman_data`.
- Default web UI/API port TCP 3082. ShellyLanMan can change its port in Settings → General → Ports unless `SHELLYLANMAN_PORT` is pinned in the environment file.
- Release-aware updates via Community Scripts Core helpers. The updater rebuilds the app, checks its health and restores the previous binary if the new one fails.

## Install from GitHub

Repository URL: [github.com/KissmanCZ/shellylanman-proxmox-lxc](https://github.com/KissmanCZ/shellylanman-proxmox-lxc). Once you create the repository, push these files to its `main` branch. Keep `ct/`, `install/` and `json/` at the repository root.

After pushing the repository to GitHub, run the following command on the Proxmox VE host to launch the LXC installer:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/KissmanCZ/shellylanman-proxmox-lxc/main/ct/shellylanman.sh)"
```

The CT script fetches its installer and shared Community Scripts Core components from the configured raw GitHub URL. The Proxmox host is used only to create/manage the LXC; Go, Node.js and the ShellyLanMan build dependencies are installed inside the container.

## Runtime and build provenance

The build follows the upstream `Dockerfile` and `go.mod`:

- Node.js 26, as in the upstream frontend build stage.
- Go 1.27 is the minimum declared by upstream `go.mod`; the Community Scripts `setup_go` helper installs the current stable Go toolchain.
- The frontend is built into `web/dist`, then copied to `internal/web/dist` for Go's embedded web assets.
- The Go test stage runs `gofmt`, `go vet`, and `go test -race`; `build-essential` supplies the C toolchain required by the race detector.
- The final Go binary is built with `CGO_ENABLED=0` and the release version is embedded using the upstream `internal/version.Version` variable.

Sources: upstream [Dockerfile](https://github.com/wimmme/shellylanman/blob/main/Dockerfile), [go.mod](https://github.com/wimmme/shellylanman/blob/main/go.mod), and [web/package.json](https://github.com/wimmme/shellylanman/blob/main/web/package.json).

## Network and security

- Attach the LXC to a Proxmox bridge/VLAN that can reach the Shelly devices. For the first test, put it in the same VLAN so mDNS discovery does not depend on an mDNS reflector.
- If Shelly devices are on routed VLANs, configure an mDNS reflector or use the application's IP-range discovery mode. Network equipment and Proxmox firewall rules can filter multicast.
- UI authentication is off by default. Set a password in **Settings → Security** immediately. Do not expose the service directly to the internet; use a reverse proxy with TLS and authentication for remote access.
- Reverse-proxy host names can be allowed with `SHELLYLANMAN_ORIGINS` in `/opt/shellylanman_data/shellylanman.env`. Restart the service after changing the file.

## Managing the service

Run inside the LXC:

```bash
systemctl status shellylanman
journalctl -u shellylanman -f
systemctl restart shellylanman
SHELLYLANMAN_DATA=/opt/shellylanman_data /usr/local/bin/shellylanman -healthcheck
```

Runtime configuration: `/opt/shellylanman_data/shellylanman.env`  
Persistent application state: `/opt/shellylanman_data`  
Source used for builds: `/opt/shellylanman`  
Binary: `/usr/local/bin/shellylanman`

The Go and Node.js toolchains are retained inside the LXC so the update action can rebuild later releases. Proxmox host packages are not modified by the app installer; only the normal LXC creation process runs on the host.

## Community Scripts alignment

The repository is structured around the current Community Scripts Core/DevScripts model:

- `ct/shellylanman.sh`: Core bootstrap, container defaults, and `update_script()`.
- `install/shellylanman-install.sh`: in-container installation using `FUNCTIONS_FILE_PATH`, `setup_nodejs`, `setup_go`, and `fetch_and_deploy_gh_release`.
- `json/shellylanman.json`: website metadata, including category, resources, config path, and supported architectures.

For testing from your own repository, `_CS_DEFAULT_URL` must point to your raw GitHub repository. For a future DevScripts pull request, follow the then-current instructions and point the script source at DevScripts; do not submit a new script directly to the ProxmoxVE repository.

**Acceptance is separate from technical compatibility.** The current DevScripts policy requires the upstream application to be at least six months old, actively maintained, have 600+ stars on its forge, and publish official release tarballs. Re-check these thresholds when preparing a PR; a correctly structured installer does not waive them.

The script enables `arm64` because upstream builds multi-architecture images and this installer builds Go and Node.js natively in the target LXC. The arm64 path still needs a real Proxmox/Incus smoke test before claiming it has been tested.

See [`docs/TESTING.md`](docs/TESTING.md) before using the script on a production node.
