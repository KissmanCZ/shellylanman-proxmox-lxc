Validation and Proxmox test plan
1. Static validation
Run from the repository root:
```bash
bash -n ct/shellylanman.sh
bash -n install/shellylanman-install.sh
shellcheck ct/shellylanman.sh install/shellylanman-install.sh
python3 -m json.tool json/shellylanman.json >/dev/null
```
Review ShellCheck findings involving Community Scripts Core-provided variables/functions rather than suppressing diagnostics globally.
2. Test with a disposable Proxmox VE host
Clone KissmanCZ/shellylanman-proxmox-lxc and `community-scripts/core` side by side:
```text
/opt/community-scripts/
├── core/
└── shellylanman-proxmox-lxc/
    ├── ct/
    ├── install/
    ├── json/
    └── docs/
```
Run on a disposable Proxmox VE host, not on a production node:
```bash
cd /opt/community-scripts/shellylanman-proxmox
dev_mode=keep,logs,net,timing bash ct/shellylanman.sh
```
Confirm the generated container is Debian 13, unprivileged, with 2 vCPU, 2 GiB RAM and 10 GiB disk. Keep it after installation so failures can be inspected.
3. Verify inside the LXC
```bash
systemctl is-enabled shellylanman
systemctl is-active shellylanman
systemctl status shellylanman --no-pager
journalctl -u shellylanman -b --no-pager
ss -lntup | grep ':3082'
SHELLYLANMAN_DATA=/opt/shellylanman_data /usr/local/bin/shellylanman -healthcheck
```
Open `http://<LXC-IP>:3082`, complete first-run setup, set a UI password, and check the About page reports the expected release version.
4. Verify persistence and restart behavior
Add a Shelly device and let it be discovered.
Save a setting and, if possible, a device backup.
Restart the service and reboot the LXC.
Confirm settings, credentials, archive and backups remain in `/opt/shellylanman_data`.
Confirm that `/opt/shellylanman_data/shellylanman.env` remains mode `0600`.
5. Verify network discovery
Start with the LXC on the same VLAN as one or more Shelly devices.
Confirm mDNS multicast discovery works.
Test IP-range scanning for devices on a routed VLAN.
Repeat with the Proxmox firewall enabled and verify the necessary multicast and TCP traffic is not blocked.
Confirm TCP/3082 is reachable only from the intended management network.
6. Verify update and rollback
Record the installed app version and binary checksum.
Run the CT script's update action when a newer upstream release exists.
Confirm the source archive is deployed, the frontend and Go checks complete, and the binary is rebuilt.
Confirm the service returns healthy before the previous binary is removed.
In a disposable test only, simulate a failed new binary/service start and confirm the previous binary is restored and the service starts again.
Confirm `/opt/shellylanman_data` remains untouched throughout the update.
7. Architecture coverage
The metadata declares amd64 and arm64 based on upstream's multi-architecture build and the native Go/Node toolchains. Test both architectures separately before marking arm64 as actually tested in a future pull request. Do not claim an architecture was tested when it was only inferred to be supported.
8. Before a DevScripts pull request
Re-read the current `community-scripts/DevScripts/AGENTS.md`, `.github/agents/pve-script-creator.agent.md`, and pull-request template.
Change `_CS_DEFAULT_URL` to the DevScripts raw base URL when preparing the PR.
Verify the current app eligibility requirements (age, maintenance, forge stars, official release tarballs).
Check JSON metadata fields, category, resources, update handler and architectures against the current schema.
Run the DevScripts validation/CI checks and include actual Proxmox test results.
Do not claim the installer is fully tested until the disposable-LXC tests have passed.
