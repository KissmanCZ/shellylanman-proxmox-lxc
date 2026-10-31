# ShellyLanMan for Proxmox VE

A community-maintained installer for running [ShellyLanMan](https://github.com/wimmme/shellylanman) directly in a Proxmox VE LXC container.

ShellyLanMan is built from its upstream source code and runs as a native Linux service. No Docker installation or Docker container is required.

**Maintainer:** [Jan Pichrt (@KissmanCZ)](https://github.com/KissmanCZ)  
**Upstream project:** [wimmme/shellylanman](https://github.com/wimmme/shellylanman)  
**Repository:** [KissmanCZ/shellylanman-proxmox-lxc](https://github.com/KissmanCZ/shellylanman-proxmox-lxc)

---

## Features

- Native ShellyLanMan installation in a Debian 13 LXC container.
- Builds the application from the official upstream source code.
- Go and Node.js toolchains installed inside the container.
- Systemd service management.
- Persistent application data and configuration.
- Integrated application update and recovery mechanism.
- Support for AMD64 and ARM64 architectures.
- Proxmox Community Scripts Core integration.

## Installation

Run the following command in the Proxmox VE host shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/KissmanCZ/shellylanman-proxmox-lxc/main/ct/shellylanman.sh)"
