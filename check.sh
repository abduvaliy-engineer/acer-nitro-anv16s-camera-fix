#!/bin/bash
# Show whether this laptop has the missing-camera problem and whether the fix is active.

model=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
bios=$(cat /sys/class/dmi/id/bios_version 2>/dev/null)
echo "Model: ${model:-unknown} (BIOS ${bios:-unknown})"
case "$model" in
  *ANV16S-41*|*AN16S-61*) ;;
  *) echo "  This fix was only tested on the Nitro ANV16S-41 and AN16S-61." ;;
esac

if grep -qo 'gpiolib_acpi.ignore_interrupt=[^ ]*AMDI0030:00@11' /proc/cmdline; then
  echo "Fix: active"
else
  echo "Fix: not active"
fi

# Known internal cameras: Quanta 0408:4035 / 0408:4059, Chicony 04f2:b831.
# Also match the "User Facing" name in case Acer ships another vendor.
cam=$(lsusb 2>/dev/null | grep -iE '0408:(4035|4059)|04f2:b831|User Facing' | head -n1)
if [[ -n $cam ]]; then
  echo "Camera: found on USB"
  echo "  ${cam#*ID }"
  ls /dev/video* 2>/dev/null | sed 's/^/  /'
else
  echo "Camera: not found on USB"
fi
