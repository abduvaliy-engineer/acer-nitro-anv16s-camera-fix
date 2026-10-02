#!/bin/bash
# Remove the Acer Nitro ANV16S-41 camera fix from the kernel command line.
#
#   sudo ./uninstall.sh
#   ./uninstall.sh --dry-run
set -euo pipefail

PARAM="gpiolib_acpi.ignore_interrupt=AMDI0030:00@11"
LIMINE_DROPIN=/etc/limine-entry-tool.d/zz-acer-camera-gpio11.conf

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

say() { printf '%s\n' "$*"; }
run() {
  if ((DRY_RUN)); then say "  would run: $*"; else "$@"; fi
}

# Remove PARAM (and the space before it) from every line of FILE that has it.
strip_from() {
  local file=$1
  [ -f "$file" ] && grep -q "$PARAM" "$file" || return 0
  say "  removing the option from $file"
  run sed -i -E "s| ?${PARAM}||g" "$file"
}

if ((!DRY_RUN)) && ((EUID != 0)); then
  say "Run with sudo, or use --dry-run to only see what would change."
  exit 1
fi

if [ -f "$LIMINE_DROPIN" ] && command -v limine-update >/dev/null; then
  say "Boot setup: Limine (limine-entry-tool)"
  run rm -f "$LIMINE_DROPIN"
  run limine-update

elif command -v kernelstub >/dev/null; then
  say "Boot setup: kernelstub (Pop!_OS)"
  run kernelstub -d "$PARAM"

elif command -v grubby >/dev/null; then
  say "Boot setup: grubby (Fedora and relatives)"
  run grubby --update-kernel=ALL --remove-args="$PARAM"

elif [ -f /etc/default/grub ]; then
  say "Boot setup: GRUB"
  strip_from /etc/default/grub
  if command -v update-grub >/dev/null; then
    run update-grub
  elif command -v grub2-mkconfig >/dev/null; then
    run grub2-mkconfig -o /boot/grub2/grub.cfg
  elif command -v grub-mkconfig >/dev/null; then
    run grub-mkconfig -o /boot/grub/grub.cfg
  fi

elif [ -f /etc/kernel/cmdline ]; then
  say "Boot setup: /etc/kernel/cmdline"
  strip_from /etc/kernel/cmdline
  if command -v reinstall-kernels >/dev/null; then
    run reinstall-kernels
  elif command -v mkinitcpio >/dev/null; then
    run mkinitcpio -P
  elif command -v dracut >/dev/null; then
    run dracut --regenerate-all --force
  elif command -v update-initramfs >/dev/null; then
    run update-initramfs -u -k all
  fi

else
  say "Boot setup: systemd-boot entries / rEFInd"
  for f in /boot/loader/entries/*.conf /efi/loader/entries/*.conf /boot/refind_linux.conf; do
    strip_from "$f"
  done
fi

if ((DRY_RUN)); then
  say "Dry run only, nothing was changed."
else
  say "Removed. Reboot to apply."
fi
