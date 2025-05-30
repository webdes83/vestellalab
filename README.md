# Proxmox Automation Scripts

This repository contains useful scripts for automating various tasks in Proxmox environments.

## Available Scripts

### `proxmox/xterm_setup.sh`

Automates the setup of serial console (`xterm.js`) access for Proxmox VMs.

#### Usage

Run the following command in your Proxmox shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/webdes83/vestellalab/refs/heads/main/proxmox/xterm_setup.sh)" <VMID>
```

Replace `<VMID>` with the ID of your virtual machine.

#### What it does:

- Checks and sets up serial socket for VM.
- Verifies installation of `qemu-guest-agent`.
- Updates GRUB configuration to include `console=ttyS0`.
- Enables `serial-getty@ttyS0.service`.
- Reboots the VM.

### Contributing

Contributions to improve or add new scripts are welcome. Feel free to submit issues or pull requests.

### License

This project is licensed under the MIT License.
