#!/bin/bash
# Diagnostic script for Thunderbolt/USB4 on Strix Halo nodes
set -euo pipefail

echo "============================================"
echo " halo0 (192.168.7.145) — TB/USB4 diagnostics"
echo "============================================"
echo
echo "Kernel: $(uname -r)"
echo
echo "--- dmesg: USB4/Thunderbolt/TypeC ---"
dmesg 2>/dev/null | grep -iE 'usb4|thunderbolt|typec|tcpci' || echo "(none)"
echo
echo "--- sysfs: /sys/class/thunderbolt/ ---"
ls -la /sys/class/thunderbolt/ 2>&1 || echo "(missing)"
echo
echo "--- sysfs: /sys/class/typec/ ---"
ls -la /sys/class/typec/ 2>&1 || echo "(missing)"
echo
echo "--- sysfs: /sys/bus/usb4/ ---"
ls -la /sys/bus/usb4/ 2>&1 || echo "(missing)"
echo
echo "--- Kernel modules: thunderbolt ---"
lsmod | grep thunderbolt || echo "(not loaded)"
echo
echo "--- modinfo thunderbolt ---"
modinfo thunderbolt 2>&1 | head -15 || echo "(not found)"
echo
echo "--- lspci: USB4 Host Routers ---"
lspci -vvv -s c6:00.5 2>/dev/null || echo "(c6:00.5 not found)"
echo
echo "--- lspci: USB4 detail ---"
lspci -nn | grep -iE 'usb4|thunderbolt' || echo "(none)"
echo
echo "--- BIOS version ---"
sudo dmidecode -s bios-version 2>/dev/null || echo "(unavailable)"
echo
echo "--- PCI device c6:00.5 uevent ---"
cat /sys/bus/pci/devices/0000:c6:00.5/uevent 2>&1 || echo "(not accessible)"
echo
echo "--- PCI device c6:00.6 uevent ---"
cat /sys/bus/pci/devices/0000:c6:00.6/uevent 2>&1 || echo "(not accessible)"
