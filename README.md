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

### mDNS configuration in LXC

> [!IMPORTANT]
> **Select the network interface explicitly when running ShellyLanMan inside an LXC container.**
>
> Automatic interface selection using **All devices** may fail to initialize mDNS discovery in an LXC, even when the container's network interface supports multicast.
>
> To configure mDNS:
>
> 1. Open **Settings → Network** in ShellyLanMan.
> 2. Find the network interface selection setting.
> 3. Change it from **All devices** to the actual LXC network interface, normally `eth0`.
> 4. Save the setting and run a device rescan.
>
> This was confirmed to resolve the mDNS discovery issue in a Debian 13 unprivileged Proxmox LXC installation.

To identify the network interface inside the container, run:

```bash
ip -br link
```

Example output:

```text
lo       UNKNOWN
eth0     UP
```

Select `eth0` in ShellyLanMan's network settings.

**There is no need to enable privileged mode, host networking, or change the Proxmox container configuration to resolve this particular interface-selection issue.**

### Security

> [!CAUTION]
> **Authentication is disabled by default!**
>
> ShellyLanMan may be accessible to anyone who can reach its web interface until authentication is configured. Set a password immediately after installation, before allowing access from other networks.

#### Initial security setup

1. Open ShellyLanMan in your browser.
2. Navigate to **Settings → Security**.
3. Configure a strong, unique password.
4. Save the settings.
5. Verify that authentication is required when accessing the application.

> [!WARNING]
> **Do not expose ShellyLanMan directly to the public internet.**
>
> ShellyLanMan provides access to your local Shelly devices and their management functionality. Restrict access to trusted networks and users.

#### Remote access

For remote access, use a reverse proxy with HTTPS/TLS and appropriate access controls.

Recommended precautions:

- Use a strong, unique application password.
- Use HTTPS instead of unencrypted HTTP when accessing the application remotely.
- Restrict access through your firewall or reverse proxy.
- Do not forward TCP port `3082` directly from the internet.
- Keep ShellyLanMan and its dependencies updated.

When accessing ShellyLanMan through a reverse proxy, configure the permitted host names using `SHELLYLANMAN_ORIGINS` in:

```text
/opt/shellylanman_data/shellylanman.env
```

Restart the service after changing the environment configuration.

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

The installer targets Debian 13 containers on Proxmox VE. Builds are performed natively inside the target container. The installer currently targets AMD64. ARM64 installation is disabled until it has been validated.

Test the installer in a disposable container and keep a Proxmox backup before production use.

## Project links

- [ShellyLanMan upstream project](https://github.com/wimmme/shellylanman)
- [Installer source code](https://github.com/KissmanCZ/shellylanman-proxmox-lxc)
- [Issue tracker](https://github.com/KissmanCZ/shellylanman-proxmox-lxc/issues)

## License

This installer repository is licensed under the MIT License. See [LICENSE](LICENSE) for details.

This license applies only to the original installation scripts, configuration files, and documentation maintained in this repository. ShellyLanMan is a separate upstream project and remains subject to its own license.

Third-party components remain subject to their respective licenses.

This project is community-maintained and is not affiliated with or endorsed by the ShellyLanMan upstream authors or Proxmox.
