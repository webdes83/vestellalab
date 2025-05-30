# Proxmox Automation Scripts

🇬🇧 [English](README.md) | 🇰🇷 [한국어](README.ko.md)

This repository contains useful scripts for automating various tasks in Proxmox environments.

## Available Scripts

### `proxmox/xterm_setup.sh`

Automates the setup of serial console (`xterm.js`) access for Proxmox VMs.

#### Usage

```bash
curl -fsSL https://raw.githubusercontent.com/webdes83/vestellalab/refs/heads/main/proxmox/xterm_setup.sh | bash -s -- <VMID>
```

Replace `<VMID>` with your target virtual machine ID.

#### What it does:

- Checks if the VM is running.
- Verifies `qemu-guest-agent` is installed.
- Appends `console=ttyS0` to `/etc/default/grub` if missing.
- Runs `update-grub`.
- Enables `serial-getty@ttyS0.service`.
- Adds `serial0: socket` to VM config.
- Reboots the VM.

---

---

### `proxmox/auto_note_network.sh`

Automatically updates the Proxmox LXC/VM Notes (description) with network information.

- Supports both LXC and VM (auto-detects by ID)
- Only updates the fixed `[Auto] Network Info` section at the top, preserving all user content below
- For VM: Also displays any custom routes, addresses, or non-standard network settings in `/etc/NetworkManager/system-connections/*`
- Diff & strikethrough shown if the section changes

**Usage:**
```bash
curl -fsSL https://raw.githubusercontent.com/webdes83/vestellalab/refs/heads/main/proxmox/auto_note_network.sh | bash -s -- <VMID|CTID>
```

### Contributing
Feel free to submit issues or pull requests to enhance the scripts.

### License
MIT License
