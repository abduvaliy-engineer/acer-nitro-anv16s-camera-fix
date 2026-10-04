# Acer Nitro ANV16S-41: internal camera fix for Linux

On the Acer Nitro ANV16S-41 (Ryzen 7 260, BIOS V1.14) the built-in camera works on Windows but is
missing on Linux. `lsusb` doesn't list it, there is no `/dev/video0`, and no camera app can find it.
Newer kernels don't help.

This repo has a one-line fix and scripts to apply and undo it.

## Fixed in the Linux kernel

The fix has been accepted into the kernel as a quirk for this model:
[gpiolib: acpi: Ignore GPIO 11 interrupt on Acer Nitro V 16S AI](https://git.kernel.org/pub/scm/linux/kernel/git/andy/linux-gpio-intel.git/commit/?h=fixes&id=6da1f3437435c82eaa15b121022474bb358ffe20)
(commit `6da1f3437435`, [mailing list discussion](https://lore.kernel.org/all/20261002101800.51506-1-abduvaliy.hbai@gmail.com/)).

Once your distro ships a kernel that includes it, the camera works without the boot option below.
Until then, use the boot option. Check whether your kernel already has the quirk:

```
journalctl -k -b | grep "Ignoring interrupt on pin 11"
```

If that line appears **without** the boot option in `/proc/cmdline`, your kernel has the fix and you
can remove the option with `sudo ./uninstall.sh`. Keeping it does no harm either.

## The short version

Add this to your kernel command line and reboot:

```
gpiolib_acpi.ignore_interrupt=AMDI0030:00@11
```

After the reboot the camera shows up:

```
$ lsusb | grep 0408
Bus 003 Device 002: ID 0408:4035 Quanta Computer, Inc. ACER HD User Facing
```

Tested and working on:

- Omarchy (Arch Linux), Limine boot loader
- Ubuntu, GRUB boot loader

## What is going on

The camera is a normal USB webcam. Linux already has the driver for it (`uvcvideo`). The problem is
power.

1. When the laptop turns on, the BIOS switches the camera on through a pin on the AMD chipset
   (GPIO 11). The pin is set to "output, high", and that keeps the camera powered.
2. The BIOS also lists the same pin in its table of wake-up/event pins (`_AEI` in ACPI). The handler
   it attaches to that event does nothing.
3. At boot, Linux sets up every pin in that table as an input so it can listen for events. Turning
   GPIO 11 into an input switches its output off, and the camera loses power a moment after boot.
4. Windows doesn't change the pin, so the camera keeps working there.

The boot option tells Linux to skip GPIO 11 when it sets up those event pins. The pin stays exactly
as the BIOS left it, the same as on Windows. Nothing is written to the hardware, and the only thing
you lose is an event whose handler was empty anyway.

## Check that this is your problem

Run `./check.sh`. It prints your laptop model, whether the camera is on the USB bus, and whether the
fix is active. You need all of these for this fix to apply:

- the model is `Nitro ANV16S-41`
- `lsusb` has no `0408:4035` device
- the boot log has no `ACER HD User Facing` line

Other Acer models may have the same problem on a different pin. Don't apply this fix to them
blindly.

## Apply the fix

```
git clone https://github.com/abduvaliy-engineer/acer-nitro-anv16s-camera-fix
cd acer-nitro-anv16s-camera-fix
./install.sh --dry-run    # shows what it would change, changes nothing
sudo ./install.sh
```

Reboot afterwards, then run `./check.sh`.

The script works out how your distro sets the kernel command line and uses that distro's own tool:

| Your system has | Typical distros | What the script does |
|---|---|---|
| `limine-entry-tool` | Omarchy, CachyOS with Limine | adds a file to `/etc/limine-entry-tool.d/`, runs `limine-update` |
| `kernelstub` | Pop!_OS | `kernelstub -a` |
| `grubby` | Fedora, RHEL, Nobara | `grubby --update-kernel=ALL --args` |
| `/etc/default/grub` | Ubuntu, Mint, Debian, Arch with GRUB, openSUSE | adds the option to `GRUB_CMDLINE_LINUX_DEFAULT`, regenerates the GRUB config |
| `/etc/kernel/cmdline` | systemd-boot with unified kernel images | adds the option, rebuilds the kernel images |
| `/boot/loader/entries/` | plain systemd-boot | adds the option to each entry's `options` line |
| `/boot/refind_linux.conf` | rEFInd | adds the option to each line |

Before editing a file it saves a copy next to it ending in `.bak-camera-fix`. If snapper is set up,
it also takes a snapshot first. It refuses to run on other laptop models unless you pass `--force`.

To undo it:

```
sudo ./uninstall.sh
```

### Doing it by hand

If the script can't recognise your setup, add `gpiolib_acpi.ignore_interrupt=AMDI0030:00@11` to the
kernel command line with your boot loader's usual method and reboot. On GRUB, for example: add it
inside the quotes of `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, then run `sudo update-grub`
(Ubuntu, Mint, Debian) or `sudo grub2-mkconfig -o /boot/grub2/grub.cfg` (Fedora).

## Confirm it worked

```
$ cat /proc/cmdline | grep -o 'gpiolib_acpi[^ ]*'
gpiolib_acpi.ignore_interrupt=AMDI0030:00@11

$ journalctl -k -b | grep "pin 11"
amd_gpio AMDI0030:00: Ignoring interrupt on pin 11

$ ls /dev/video*
/dev/video0  /dev/video1
```

## Technical details

- Camera: Quanta/SunplusIT USB `0408:4035`, on the second AMD xHCI controller (`1022:15ba`, PCI
  `65:00.4`), USB2 port 1, ACPI path `\_SB.PCI0.GP17.XHC1.RHUB.PRT1.CAM0`.
- GPIO 11 of `AMDI0030` reads `0x00447a00` after Linux claims it: output value 1, output enable 0,
  drive strength set, line low. It is the only pin in the bank in that state.
- `\_SB.GPIO._AEI` lists pin `0x0B` as `GpioInt (Edge, ActiveLow, ExclusiveAndWake)`. The matching
  `_EVT` case only calls a debug method.
- gpiolib-acpi requests `_AEI` pins as inputs, which clears the output enable bit.
- With the controller kept from Linux at boot (`pci-stub.ids=1022:15ba`), the camera port shows
  `CSC=1, CCS=0`: the camera was connected during boot and dropped off.
- The parameter `gpiolib_acpi.ignore_interrupt` is in mainline Linux, so no custom kernel is needed.

The kernel fix ([commit `6da1f3437435`](https://git.kernel.org/pub/scm/linux/kernel/git/andy/linux-gpio-intel.git/commit/?h=fixes&id=6da1f3437435c82eaa15b121022474bb358ffe20))
adds this DMI quirk to `drivers/gpio/gpiolib-acpi-quirks.c`, next to the existing one for the
Acer Nitro V 14 on the same pin:

```c
	{
		/*
		 * GPIO 11 is the power enable of the internal USB camera.
		 * The firmware drives it high but also lists it in _AEI with
		 * an empty handler. Requesting it as an input turns the camera
		 * off, so it never enumerates.
		 * Found in BIOS V1.14
		 */
		.matches = {
			DMI_MATCH(DMI_SYS_VENDOR, "Acer"),
			DMI_MATCH(DMI_PRODUCT_FAMILY, "Acer Nitro V 16S AI"),
		},
		.driver_data = &(struct acpi_gpiolib_dmi_quirk) {
			.ignore_interrupt = "AMDI0030:00@11",
		},
	},
```

The full ACPI dump of this laptop (BIOS V1.14) used for the kernel review is attached to the
[acpidump-v1.14 release](https://github.com/abduvaliy-engineer/acer-nitro-anv16s-camera-fix/releases/tag/acpidump-v1.14).

## License

MIT
