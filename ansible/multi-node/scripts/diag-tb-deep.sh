#!/bin/bash
# Deep dive into TypeC/USB4 port state on Strix Halo
set -euo pipefail

echo "============================================"
echo " TypeC port details (halo0)"
echo "============================================"
echo
echo "--- port0 state ---"
cat /sys/class/typec/port0/port_mode 2>&1 || true
cat /sys/class/typec/port0/srp_capable 2>&1 || true
cat /sys/class/typec/port0/vconn_src 2>&1 || true
cat /sys/class/typec/port0/sbu_pull 2>&1 || true
echo
echo "--- port1 state (has cable/partner) ---"
cat /sys/class/typec/port1/port_mode 2>&1 || true
cat /sys/class/typec/port1/srp_capable 2>&1 || true
cat /sys/class/typec/port1/vconn_src 2>&1 || true
cat /sys/class/typec/port1/sbu_pull 2>&1 || true
cat /sys/class/typec/port1/power_role 2>&1 || true
cat /sys/class/typec/port1/data_role 2>&1 || true
echo
echo "--- port1-cable attributes ---"
cat /sys/class/typec/port1/port1-cable/cable_mode 2>&1 || true
cat /sys/class/typec/port1/port1-cable/cable_orientation 2>&1 || true
cat /sys/class/typec/port1/port1-cable/pwr_opmode 2>&1 || true
cat /sys/class/typec/port1/port1-cable/usbc_power_role 2>&1 || true
cat /sys/class/typec/port1/port1-cable/usbc_data_role 2>&1 || true
echo
echo "--- port1-partner attributes ---"
cat /sys/class/typec/port1/port1-partner/descriptor 2>&1 || true
cat /sys/class/typec/port1/port1-partner/usb4_descriptor 2>&1 || true
cat /sys/class/typec/port1/port1-partner/svids 2>&1 || true
cat /sys/class/typec/port1/port1-partner/modes 2>&1 || true
echo
echo "--- USB4 device c6:00.5 details ---"
lspci -vvv -s c6:00.5 2>/dev/null | grep -A 5 'Capabilities\|Kernel' || true
echo
echo "--- USB4 device c6:00.6 details ---"
lspci -vvv -s c6:00.6 2>/dev/null | grep -A 5 'Capabilities\|Kernel' || true
echo
echo "--- Check for USB4 sysfs ---"
find /sys -name "*usb4*" -type d 2>/dev/null || echo "none"
echo
echo "--- Check for thunderbolt sysfs anywhere ---"
find /sys -name "*thunderbolt*" -type d 2>/dev/null | head -20 || echo "none"
echo
echo "--- Kernel messages (last 100 lines) ---"
dmesg 2>/dev/null | tail -100 | grep -iE 'usb|thunder|typec|pci|amd|cxl' || echo "(no matches in tail)"
echo
echo "--- modprobe.d for thunderbolt ---"
cat /etc/modules-load.d/*.conf 2>/dev/null || echo "none"
cat /etc/modprobe.d/*.conf 2>/dev/null | grep -i thunderbolt || echo "(no thunderbolt modprobe.d)"
echo
echo "--- UEFI variables ---"
ls /sys/firmware/efi/efivars/ | grep -i usb4 || echo "(no USB4 efi vars)"
ls /sys/firmware/efi/efivars/ | grep -i thund || echo "(no thunderbolt efi vars)"
