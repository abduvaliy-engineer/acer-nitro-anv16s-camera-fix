#!/bin/bash
# Remove the camera fix from Omarchy's boot command line (run with sudo).
set -euo pipefail

if ((EUID != 0)); then
  echo "Run with sudo." >&2
  exit 1
fi

rm -f /etc/limine-entry-tool.d/zz-acer-camera-gpio11.conf
limine-update
echo "Removed. Reboot to apply."
