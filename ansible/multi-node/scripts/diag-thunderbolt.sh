#!/usr/bin/env bash
# Diagnostic script for Thunderbolt controller detection
# Run on both halo0 and halo1
set -euo pipefail

echo "=== halo diagnostics ==="
echo "Kernel:    $(uname -r)"
echo
echo "--- Thunderbolt sysfs ---"
ls -la /sys/class/thunderbolt/ 2>&1 || echo "empty or missing"
echo
echo "--- lspci: Thunderbolt/USB4 ---"
lspci 2>/dev/null | grep -iE 'thunderbolt|usb.*(40|10)' || echo "none found"
echo
echo "--- lspci: USB controllers ---"
lspci 2>/dev/null | grep -iE 'usb.*(controller|xhci)' || echo "none found"
echo
echo "--- Kernel modules: thunderbolt ---"
lsmod | grep thunderbolt || echo "none loaded"
echo
echo "--- lspci: full GPU/APC summary ---"
lspci 2>/dev/null | grep -iE 'amd|vga|3d|usb|x86|thunderbolt' || echo "none"
