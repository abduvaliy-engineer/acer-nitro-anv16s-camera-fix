#!/bin/bash
# Add the camera fix to Omarchy's boot command line (run with sudo).
set -euo pipefail

CONF=/etc/limine-entry-tool.d/zz-acer-camera-gpio11.conf
PARAM="gpiolib_acpi.ignore_interrupt=AMDI0030:00@11"

if ((EUID != 0)); then
  echo "Run with sudo." >&2
  exit 1
fi

if command -v snapper >/dev/null; then
  snapper -c root create -c number -d "before acer camera fix"
fi

cat > "$CONF" <<EOF
# Acer Nitro ANV16S-41: leave GPIO 11 as the firmware set it so the internal camera keeps power.
KERNEL_CMDLINE[default]+=" $PARAM"
EOF

limine-update

for uki in /boot/EFI/Linux/*.efi; do
  [ -e "$uki" ] || continue
  if objcopy -O binary --only-section=.cmdline "$uki" /dev/stdout 2>/dev/null | tr -d '\0' | grep -q "$PARAM"; then
    echo "$(basename "$uki"): fix included"
  else
    echo "$(basename "$uki"): fix NOT included" >&2
  fi
done

echo "Done. Reboot to turn the camera on."
