# USB storage and Entware

Entware gives you `opkg` and a few thousand packages. It lives entirely on a
USB stick, which is the right place for it — `/jffs` is small NAND you will
never reflash.

## Format the stick

ext4. The firmware ships drivers for NTFS, HFS+ and FAT, but ext4 is the one
with working permissions and no licensing oddities.

    # find it
    blkid
    # partition and format (destructive)
    mkfs.ext4 -L ROUTERDATA /dev/sda1

Label it. The scripts here resolve the volume by label, because `/dev/sda1` is
not stable once a second disk appears.

## Install Entware — the right target

**`armv7sf-k3.2`. Not aarch64.**

The kernel reports `aarch64` and it is telling the truth, but the userland is
32-bit ARM, soft-float. Install the 64-bit target and you get binaries that
will not execute. See `00-hardware.md`.

    mkdir -p /tmp/mnt/ROUTERDATA/entware
    mount -o bind /tmp/mnt/ROUTERDATA/entware /opt
    wget -O - https://bin.entware.net/armv7sf-k3.2/installer/generic.sh | sh

`/opt` must be a bind mount from the stick — that path is baked into every
Entware package. The bind has to be re-established at every boot;
`scripts/portal/start.sh` does it in `ensure_opt()`.

## The trap that will cost you an evening

**Every Entware binary fails when launched from `rc`, silently.**

`rc` exports `LD_LIBRARY_PATH` pointing at the firmware's own libraries.
Entware binaries carry a `DT_RUNPATH`, but an inherited `LD_LIBRARY_PATH` wins
over `DT_RUNPATH`, so they load the wrong libc and die. Worse, `rc.func`
discards stderr, so there is no message at all — just a service that never
starts.

Unset it before launching anything from `/opt`:

    (
      unset LD_LIBRARY_PATH LD_PRELOAD
      /opt/bin/whatever
    )

Every script in this repository that touches `/opt` does this. If you write
your own, do it too. Interactive SSH sessions do not inherit the variable,
which is exactly why something works by hand and fails at boot.

## Useful packages

    opkg update
    opkg install htop tcpdump nmap rrdtool screen irssi
    opkg install binutils     # objdump/readelf, if you want to inspect firmware

## A note on `$HOME`

`/root` is a symlink to `/tmp/home/root`, which is tmpfs. Anything that writes
configuration to `$HOME` — irssi, screen, ssh — loses it on reboot. Point such
tools at the USB volume explicitly:

    irssi --home=/tmp/mnt/ROUTERDATA/irssi
