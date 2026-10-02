#!/bin/bash
# Add the Acer Nitro ANV16S-41 camera fix to the kernel command line.
# Works out which boot setup the system uses and changes it the way that setup expects.
#
#   sudo ./install.sh            apply the fix
#   ./install.sh --dry-run       only show what would be changed
#   sudo ./install.sh --force    apply on a model other than the ANV16S-41
set -euo pipefail

PARAM="gpiolib_acpi.ignore_interrupt=AMDI0030:00@11"
LIMINE_DROPIN=/etc/limine-entry-tool.d/zz-acer-camera-gpio11.conf
MODEL="Nitro ANV16S-41"

DRY_RUN=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
run() {
  if ((DRY_RUN)); then say "  would run: $*"; else "$@"; fi
}

# Append PARAM inside the quotes of KEY="..." in FILE, unless it is already there.
add_to_quoted_var() {
  local file=$1 key=$2
  if grep -q "^${key}=.*${PARAM}" "$file"; then
    say "  $file already has the option"
    return
  fi
  if ! grep -q "^${key}=" "$file"; then
    run sh -c "printf '%s\n' '${key}=\"${PARAM}\"' >> '$file'"
    return
  fi
  run cp -a "$file" "$file.bak-camera-fix"
  run sed -i -E "s|^(${key}=\")([^\"]*)\"|\1\2 ${PARAM}\"|; s|^(${key}=\") |\1|" "$file"
}

regenerate_grub() {
  if command -v update-grub >/dev/null; then
    run update-grub
  elif command -v grub2-mkconfig >/dev/null; then
    local out=/boot/grub2/grub.cfg
    [ -e /boot/efi/EFI/fedora/grub.cfg ] && [ ! -e "$out" ] && out=/boot/efi/EFI/fedora/grub.cfg
    run grub2-mkconfig -o "$out"
  elif command -v grub-mkconfig >/dev/null; then
    run grub-mkconfig -o /boot/grub/grub.cfg
  else
    say "  Could not find a GRUB config generator. Regenerate your GRUB config by hand."
  fi
}

rebuild_images() {
  if command -v reinstall-kernels >/dev/null; then
    run reinstall-kernels
  elif command -v mkinitcpio >/dev/null; then
    run mkinitcpio -P
  elif command -v dracut >/dev/null; then
    run dracut --regenerate-all --force
  elif command -v update-initramfs >/dev/null; then
    run update-initramfs -u -k all
  else
    say "  Rebuild your kernel images so they pick up /etc/kernel/cmdline."
  fi
}

model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
if [ "$model" != "$MODEL" ] && ((!FORCE)); then
  say "This laptop is \"${model:-unknown}\", not the $MODEL."
  say "The fix may be wrong for it. Use --force to apply anyway."
  exit 1
fi

if ((!DRY_RUN)) && ((EUID != 0)); then
  say "Run with sudo, or use --dry-run to only see what would change."
  exit 1
fi

if grep -q "$PARAM" /proc/cmdline; then
  say "The fix is already active in the running kernel."
fi

if command -v snapper >/dev/null && snapper list-configs 2>/dev/null | grep -q '^root'; then
  run snapper -c root create -c number -d "before acer camera fix"
fi

if [ -d /etc/limine-entry-tool.d ] && command -v limine-update >/dev/null; then
  say "Boot setup: Limine (limine-entry-tool)"
  if ((DRY_RUN)); then
    say "  would write $LIMINE_DROPIN"
  else
    printf '# Acer Nitro ANV16S-41 camera fix\nKERNEL_CMDLINE[default]+=" %s"\n' "$PARAM" > "$LIMINE_DROPIN"
  fi
  run limine-update

elif command -v kernelstub >/dev/null; then
  say "Boot setup: kernelstub (Pop!_OS)"
  run kernelstub -a "$PARAM"

elif command -v grubby >/dev/null; then
  say "Boot setup: grubby (Fedora and relatives)"
  run grubby --update-kernel=ALL --args="$PARAM"

elif [ -f /etc/default/grub ]; then
  say "Boot setup: GRUB"
  add_to_quoted_var /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT
  regenerate_grub

elif [ -f /etc/kernel/cmdline ]; then
  say "Boot setup: /etc/kernel/cmdline (systemd-boot or unified kernel images)"
  if grep -q "$PARAM" /etc/kernel/cmdline; then
    say "  /etc/kernel/cmdline already has the option"
  else
    run cp -a /etc/kernel/cmdline /etc/kernel/cmdline.bak-camera-fix
    run sed -i "1s|\$| $PARAM|" /etc/kernel/cmdline
  fi
  rebuild_images

elif compgen -G "/boot/loader/entries/*.conf" >/dev/null || compgen -G "/efi/loader/entries/*.conf" >/dev/null; then
  say "Boot setup: systemd-boot entries"
  for entry in /boot/loader/entries/*.conf /efi/loader/entries/*.conf; do
    [ -f "$entry" ] || continue
    if grep -q "^options.*$PARAM" "$entry"; then
      say "  $entry already has the option"
    else
      run cp -a "$entry" "$entry.bak-camera-fix"
      run sed -i -E "s|^(options[[:space:]].*)$|\1 $PARAM|" "$entry"
    fi
  done

elif [ -f /boot/refind_linux.conf ]; then
  say "Boot setup: rEFInd"
  if grep -q "$PARAM" /boot/refind_linux.conf; then
    say "  /boot/refind_linux.conf already has the option"
  else
    run cp -a /boot/refind_linux.conf /boot/refind_linux.conf.bak-camera-fix
    run sed -i -E "s|^(\"[^\"]*\"[[:space:]]+\")([^\"]*)\"|\1\2 $PARAM\"|" /boot/refind_linux.conf
  fi

else
  say "Could not recognise how this system sets the kernel command line."
  say "Add this option by hand with your boot loader's tools, then reboot:"
  say "  $PARAM"
  exit 1
fi

if ((DRY_RUN)); then
  say "Dry run only, nothing was changed."
else
  say "Done. Reboot, then run ./check.sh to confirm the camera is back."
fi
