#!/bin/bash
echo "=== dmesg USB4/Thunderbolt ==="
dmesg 2>/dev/null | grep -iE "usb4|thunderbolt|typec|tcpci"
echo
echo "=== sysfs TB ==="
ls -la /sys/class/thunderbolt/ 2>&1
echo
echo "=== sysfs typec ==="
ls /sys/class/typec/ 2>&1
echo
echo "=== sysfs usb4 ==="
ls /sys/bus/usb4/ 2>&1
echo
echo "=== modinfo thunderbolt ==="
modinfo thunderbolt 2>&1 | head -15
echo
echo "=== lspci USB4 detail ==="
lspci -vvv -s c6:00.5 2>/dev/null | head -20
echo
echo "=== BIOS version ==="
sudo dmidecode -s bios-version 2>/dev/null || echo "unavailable"
echo
echo "=== sysfs devices c6:00.5 ==="
ls /sys/bus/pci/devices/0000:c6:00.5/ 2>&1
echo
echo "=== uevent for c6:00.5 ==="
cat /sys/bus/pci/devices/0000:c6:00.5/uevent 2>&1
