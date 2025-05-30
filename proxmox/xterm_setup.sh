#!/bin/bash

VMID="$1"

if [ -z "$VMID" ]; then
    echo "Usage: $0 <VMID>"
    exit 1
fi

# Check serial socket
if qm config "$VMID" | grep -q "serial0: socket"; then
    echo "[❌] VM $VMID already has serial0 socket configured. Exiting."
    exit 1
fi

# Configure serial0 socket
qm set "$VMID" --serial0 socket
if [ $? -eq 0 ]; then
    echo "[✅] Serial socket configured for VM $VMID"
else
    echo "[❌] Failed to set serial socket for VM $VMID"
    exit 1
fi

# Check if qemu-guest-agent is running
qm guest exec "$VMID" "which" "qemu-ga" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "[⚠️] qemu-guest-agent not installed or not running on VM $VMID"
    echo "Please install qemu-guest-agent manually."
    exit 1
else
    echo "[✅] qemu-guest-agent is installed on VM $VMID"
fi

# Check and modify /etc/default/grub if needed
qm guest exec "$VMID" grep -q "console=ttyS0" /etc/default/grub
if [ $? -ne 0 ]; then
    qm guest exec "$VMID" sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 console=ttyS0"/' /etc/default/grub
    echo "[✅] console=ttyS0 added to GRUB_CMDLINE_LINUX"

    qm guest exec "$VMID" update-grub
    echo "[✅] grub updated"
else
    echo "[✅] console=ttyS0 already present in GRUB configuration"
fi

# Enable serial-getty
qm guest exec "$VMID" systemctl enable serial-getty@ttyS0.service
if [ $? -eq 0 ]; then
    echo "[✅] Enabled serial-getty@ttyS0.service"
else
    echo "[❌] Failed to enable serial-getty@ttyS0.service"
    exit 1
fi

# Reboot VM
qm guest exec "$VMID" reboot

if [ $? -eq 0 ]; then
    echo "[✅] VM $VMID is rebooting"
else
    echo "[❌] Failed to reboot VM $VMID"
fi