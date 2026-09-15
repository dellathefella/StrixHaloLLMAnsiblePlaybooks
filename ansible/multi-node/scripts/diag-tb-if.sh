#!/bin/bash
echo "--- ip link show thunderbolt0 ---"
ip -br link show thunderbolt0 2>&1
echo
echo "--- ip addr show thunderbolt0 ---"
ip addr show thunderbolt0 2>&1
echo
echo "--- ethtool ---"
ethtool thunderbolt0 2>&1 || true
echo
echo "--- ls net sysfs ---"
ls -la /sys/devices/pci0000:00/0000:00:08.3/0000:c6:00.6/domain1/1-0/1-2/1-2.0/net/
echo
echo "--- domain0 (c6:00.5) ---"
ls -la /sys/devices/pci0000:00/0000:00:08.3/0000:c6:00.5/domain0/ 2>&1
echo
echo "--- domain1 (c6:00.6) ---"
ls -la /sys/devices/pci0000:00/0000:00:08.3/0000:c6:00.6/domain1/ 2>&1
echo
echo "--- all tb* interfaces ---"
ip -br link show | grep -i tb || echo "(none)"
echo
echo "--- thunderbolt configfs ---"
ls /sys/kernel/config/thunderbolt/ 2>&1 || echo "(none)"
echo
echo "--- /sys/bus/thunderbolt ---"
ls /sys/bus/thunderbolt/ 2>&1
echo
echo "--- domains under /sys/bus/thunderbolt ---"
find /sys/bus/thunderbolt -name "domain*" -type d 2>/dev/null | head -20
