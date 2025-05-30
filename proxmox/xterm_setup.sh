#!/bin/bash

VMID="$1"

if [ -z "$VMID" ]; then
    echo "Usage: xterm_setup.sh <VMID>"
    exit 1
fi

# Check if VM is running
VM_STATE=$(qm list | awk -v id="$VMID" '$1 == id { print $3 }')
if [ "$VM_STATE" != "running" ]; then
    echo "[❌] VM $VMID is not running. Please start the VM first."
    exit 1
fi

# Check if qemu-guest-agent is running
qm guest exec "$VMID" -- bash -c "which qemu-ga" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "[⚠️] qemu-guest-agent not installed or not running on VM $VMID"
    echo "Please install qemu-guest-agent manually."
    exit 1
else
    echo "[✅] qemu-guest-agent is installed on VM $VMID"
fi

# Check and modify /etc/default/grub if needed
qm guest exec "$VMID" -- bash -c "grep -q 'console=ttyS0' /etc/default/grub"
if [ $? -ne 0 ]; then
    qm guest exec "$VMID" -- bash -c "sed -i 's/^GRUB_CMDLINE_LINUX=\"\(.*\)\"/GRUB_CMDLINE_LINUX=\"\1 console=ttyS0\"/' /etc/default/grub"
    echo "[✅] console=ttyS0 added to GRUB_CMDLINE_LINUX"

    qm guest exec "$VMID" -- bash -c "update-grub"
    echo "[✅] grub updated"
else
    echo "[✅] console=ttyS0 already present in GRUB configuration"
fi

# Enable serial-getty
qm guest exec "$VMID" -- bash -c "systemctl enable serial-getty@ttyS0.service"
if [ $? -eq 0 ]; then
    echo "[✅] Enabled serial-getty@ttyS0.service"
else
    echo "[❌] Failed to enable serial-getty@ttyS0.service"
    exit 1
fi

# Check serial socket before configuring
if qm config "$VMID" | grep -q "serial0: socket"; then
    echo "[❌] VM $VMID already has serial0 socket configured. Skipping."
else
    qm set "$VMID" --serial0 socket
    if [ $? -eq 0 ]; then
        echo "[✅] Serial socket configured for VM $VMID"
    else
        echo "[❌] Failed to set serial socket for VM $VMID"
        exit 1
    fi
fi

# Reboot VM using qm reboot
qm reboot "$VMID"
if [ $? -eq 0 ]; then
    echo "[✅] VM $VMID is rebooting via qm reboot"
else
    echo "[❌] Failed to reboot VM $VMID via qm reboot"
fi
