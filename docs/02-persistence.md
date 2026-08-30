# Making things survive a reboot

This is the hard part, and the part with a real chance of bricking the router.
Everything else in this repository depends on it.

## Every documented hook is a decoy

Search the internet and you will find these recommended for Asuswrt. On this
firmware, all of them are **present but inert**:

| hook | what happens |
|---|---|
| `script_usbmount` nvram | accepted, stored, never read by anything |
| `/jffs/scripts/*` | the directory convention exists; stock `rc` never executes it |
| `/etc/init.d/` | present, never traversed at boot |
| `services-start`, `post-mount` etc. | Merlin features. This is not Merlin. |

`script_usbmount` was tested three separate ways before being ruled out. It is
a recurring pattern in this firmware: ASUS ships the *presentation layer* of a
feature — the nvram variable, sometimes even a GUI field — without the code
that consumes it. Do not assume a setting does anything just because it exists
and persists.

**Asuswrt-Merlin does not support the GT-AC5300.** If you came here expecting
`/jffs/scripts/`, that is why it does not work.

## What does work: wrapping a binary that `rc` executes

`rc` — ASUS's init and service manager — runs a fixed set of binaries at boot.
Replace one with a shell script and you have your hook.

**The candidate must be a real file, not a symlink.** Most daemons in `/sbin`
are symlinks to `/sbin/rc`:

    # readlink -f /sbin/netool
    /sbin/rc

Writing a wrapper there does not replace `netool`. It **replaces `rc`**, which
is init. The router will not boot, and there is no recovery short of firmware
restore mode. Check every candidate:

    readlink -f /usr/sbin/infosvr        # must print itself, not /sbin/rc

`/usr/sbin/infosvr` is a real ELF binary and a good choice for a second reason:
it is the ASUS LAN discovery service on UDP 9999, it has a long CVE history,
and nothing respawns it. You want it dead anyway.

## Doing it

    # 1. VERIFY it is not a symlink. Do not skip this.
    readlink -f /usr/sbin/infosvr

    # 2. Keep the original somewhere writable
    cp /usr/sbin/infosvr /jffs/infosvr.orig

    # 3. The rootfs is read-only; remount, replace, remount back
    mount -o remount,rw /
    cp /path/to/infosvr-wrapper.sh /usr/sbin/infosvr
    chmod 755 /usr/sbin/infosvr
    mount -o remount,ro /

    # 4. Confirm before you reboot
    head -1 /usr/sbin/infosvr          # should be #!/bin/sh
    sh -n /usr/sbin/infosvr            # syntax check

The wrapper (`scripts/infosvr-wrapper.sh`) launches your boot script in the
background and exits. It does **not** exec the original binary — the whole
point is that `infosvr` should not run.

## Restoring

    mount -o remount,rw /
    cp /jffs/infosvr.orig /usr/sbin/infosvr
    chmod 755 /usr/sbin/infosvr
    mount -o remount,ro /

Keep this command somewhere you can find it without the router.

## Design the chain so it fails safe

The wrapper calls `/jffs/killsvc.sh` guarded with `[ -x ]`, and `killsvc.sh`
launches the portal the same way. Deleting either file cleanly disables that
stage — no editing the rootfs, no reboot loop. Build every stage that way: the
recovery path should be `rm`, not "boot into recovery mode".

## Does a firmware upgrade survive this?

No. A firmware flash rewrites the rootfs, so your wrapper is gone and
`/usr/sbin/infosvr` is the real binary again. `/jffs` normally survives, so the
scripts remain, but nothing invokes them until you redo this step.

Given the final firmware is already installed, that mostly matters if you ever
restore in order to recover from a mistake.
