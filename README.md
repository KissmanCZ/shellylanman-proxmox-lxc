# ShellyLanMan for Proxmox VE

A community-maintained installer for running [ShellyLanMan](https://github.com/wimmme/shellylanman) in a native Debian LXC container on Proxmox VE.

The installer builds ShellyLanMan from its upstream source and runs it as a systemd service. **Docker is not used**, and Go, Node.js, and the application build dependencies are installed inside the LXC—not on the Proxmox host.

Maintained by [Jan Pichrt (@KissmanCZ)](https://github.com/KissmanCZ).

## Installation

Run the following command from the Proxmox VE shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/KissmanCZ/shellylanman-proxmox-lxc/main/ct/shellylanman.sh)"
```

The installer creates a Debian 13 LXC and builds the application inside it. Review the container settings presented by the installer before confirming creation.

### Default container configuration

| Setting | Default |
|---|---:|
| Operating system | Debian 13 |
| Container | Unprivileged LXC |
| CPU | 2 cores |
| Memory | 4 GB |
| Disk | 16 GB |
| Web interface | TCP 3082 |

The application service runs as root inside the unprivileged LXC, following the Community Scripts convention. Proxmox maps the container UID into an unprivileged host UID range; this does not grant the service root privileges on the Proxmox host.

The container needs network access to the Shelly devices it will manage. Its IP address is displayed when installation completes.

## Accessing ShellyLanMan

Open the web interface at:

```text
http://<container-ip>:3082
```

The default port is `3082`. **Settings → General → Ports** displays the active port and how it is configured. To change it, set `SHELLYLANMAN_PORT` in `/opt/shellylanman_data/shellylanman.env` and restart the service.

### Network discovery

ShellyLanMan uses local-network discovery to find Shelly devices. For the simplest setup, connect the LXC to the same VLAN as the devices.

For devices on other VLANs or subnets, configure an mDNS reflector where required, or use ShellyLanMan's IP-range discovery. Ensure that multicast and the required device-management traffic are permitted by the network and Proxmox firewall rules.

### Security

UI authentication is disabled by default. Set a password in **Settings → Security** before making the interface available beyond a trusted management network.

Do not expose the service directly to the public internet. For remote access, use a reverse proxy with HTTPS and appropriate access controls. When accessing ShellyLanMan through a reverse proxy, configure the permitted host names with `SHELLYLANMAN_ORIGINS` in the runtime environment file, then restart the service.

## Service management

Run these commands inside the LXC:

```bash
# Check service status
systemctl status shellylanman

# Follow service logs
journalctl -u shellylanman -f

# Restart the service
systemctl restart shellylanman

# Run the application's health check
SHELLYLANMAN_DATA=/opt/shellylanman_data /usr/local/bin/shellylanman -healthcheck
```

## Files and persistent data

| Path | Purpose |
|---|---|
| `/opt/shellylanman` | ShellyLanMan source tree used for builds |
| `/usr/local/bin/shellylanman` | Compiled application binary |
| `/opt/shellylanman_data` | Persistent application data |
| `/opt/shellylanman_data/shellylanman.env` | Runtime environment configuration |
| `/etc/systemd/system/shellylanman.service` | systemd service definition |

Application data and runtime configuration are kept separately from the source tree, so rebuilding or updating the application does not replace them.

## Updates

The Proxmox container script includes an update action. It checks the upstream ShellyLanMan release, retrieves the source, rebuilds the frontend and Go application inside the LXC, and performs a health check before completing the binary replacement. If the new binary does not become healthy, the previous binary is restored. A successful update retains a uniquely named previous binary under `/usr/local/bin/shellylanman.previous.*` for manual recovery.

The Go and Node.js toolchains are retained inside the container for subsequent source builds. No application build toolchain is installed on the Proxmox host.

## Compatibility

The installer targets Debian 13 containers on Proxmox VE. Builds are performed natively inside the target container. The installer currently targets AMD64. ARM64 installation is disabled until it has been validated. Test the installer in a disposable container and keep a Proxmox backup before production use.

## Project links

- [ShellyLanMan upstream project](https://github.com/wimmme/shellylanman)
- [Installer source code](https://github.com/KissmanCZ/shellylanman-proxmox-lxc)
- [Issue tracker](https://github.com/KissmanCZ/shellylanman-proxmox-lxc/issues)

## License

This installer repository is licensed under the MIT License. ShellyLanMan is a separate upstream project and remains subject to its own license.

This project is community-maintained and is not affiliated with or endorsed by the ShellyLanMan upstream authors or Proxmox.
