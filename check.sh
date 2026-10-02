#!/bin/bash
# Show whether this laptop has the missing-camera problem and whether the fix is active.

model=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
bios=$(cat /sys/class/dmi/id/bios_version 2>/dev/null)
echo "Model: ${model:-unknown} (BIOS ${bios:-unknown})"
[ "$model" = "Nitro ANV16S-41" ] || echo "  This fix was only tested on the Nitro ANV16S-41."

if grep -qo 'gpiolib_acpi.ignore_interrupt=[^ ]*AMDI0030:00@11' /proc/cmdline; then
  echo "Fix: active"
else
  echo "Fix: not active"
fi

if lsusb 2>/dev/null | grep -q '0408:4035'; then
  echo "Camera: found on USB"
  ls /dev/video* 2>/dev/null | sed 's/^/  /'
else
  echo "Camera: not found on USB"
fi
