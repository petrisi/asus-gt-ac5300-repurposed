# The hardware

| | |
|---|---|
| SoC | Broadcom BCM4908, 4× Cortex-A53 |
| RAM | 1 GB |
| Flash | NAND; UBI-backed read-only rootfs, plus a writable JFFS2 partition |
| Radios | tri-band — 2.4 GHz + two independent 5 GHz |
| Wired | 8× gigabit LAN, 1× gigabit WAN |
| Firmware | `3.0.0.4.386_51582` is the last one, kernel 4.1.27 |

## The quirk that will bite you

**The kernel is 64-bit. The userland is 32-bit.**

    # uname -m
    aarch64
    # readelf -h /usr/sbin/bsd | grep Class
    Class:  ELF32

Two consequences, and both cost real debugging time if you meet them cold:

**Pick the right Entware target.** `armv7sf-k3.2`, not `aarch64`. The kernel
will happily tell you it is 64-bit; installing the 64-bit target gives you
binaries that will not run. See `04-usb-and-entware.md`.

**Shell arithmetic silently overflows at 2³¹.** busybox `ash` truncates to
zero with no error:

    # rx=18821963980
    # echo $((rx + 1))
    1

Interface byte counters pass 2³¹ within days of uptime. Anything doing shell
arithmetic on them produces zeroes that look like idle links. Do the maths in
`awk`, which uses doubles. This is the single most expensive trap on the
platform — `99-gotchas.md` has the full list.

## Storage layout

    /              ubifs, read-only        the firmware
    /jffs          jffs2, writable, 64 MB  where your stuff goes
    /tmp           tmpfs                   volatile, cleared on reboot
    /tmp/mnt/<label>                       USB volumes

`/jffs` is the only writable persistent storage without a USB stick, and it is
NAND that will never be reflashed again — so avoid writing to it on a timer.
Two of the scripts here deliberately keep their state in `/tmp` and only touch
`/jffs` when a value actually changes.

## The wireless driver

`dhd.ko`, Broadcom's **FullMAC** driver. The 802.11 state machine runs on the
radio firmware, not in Linux. That means:

- no `mac80211`, so no `iw`, no monitor mode, no packet injection
- `wl` is the only interface to the radios
- `wl` ioctls can block indefinitely during DFS events — always bound them

If you were hoping to use this as a wireless sniffer, that is where the idea
ends. As an AP, a server, or a wired appliance it is excellent.
