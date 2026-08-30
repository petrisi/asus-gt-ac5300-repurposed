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

- no `mac80211`, so no `iw` and none of the standard Linux wireless tooling
- `wl` is the only interface to the radios
- `wl` ioctls can block indefinitely during DFS events — always bound them

## `wl` documents far less than it implements

    wl -h            usage plus ~180 command descriptions
    wl cmds          a much longer list, ~650 entries
    wl -h <cmd>      per-command help, including for undocumented ones

Roughly **470 commands are absent from `wl -h`** but present in `cmds` and
carrying built-in help. Some are genuinely useful — `bss_peer_info` returns
per-client RSSI, TX/RX rate, rateset and age in a single call, which is far
richer than `assoclist`.

**Presence in the list does not mean the driver supports it.** `sar_limit` and
`rrm_nbr_list` both exist and both return `wl: Unsupported`. The command table
is generic across Broadcom's product range and this firmware implements a
subset. Treat the list as candidates to test, not as capabilities.

## Monitor mode: present, and non-functional

Worth stating carefully, because the obvious inference from "FullMAC, no
mac80211" is that monitor mode does not exist. It does exist. It just does not
work.

The entire control surface is there:

    wl -i eth6 monitor 1                    # accepted, reads back 1
    wl -i eth6 monitor_promisc_level 0xf    # promisc + ctrl + fcs
    ip link show prism0                     # appears, link/ieee802.11/prism
    tcpdump -i prism0 -L                    # offers PRISM_HEADER

A `prism0` interface is created, comes up, and tcpdump correctly identifies it
as *802.11 plus Prism header*. Everything looks right.

**No frames are ever delivered to it.** Measured at the driver level:

    prism0 rx_packets after 30s : 0
    eth6   rx_packets same window: 1612

Tested with every promisc bit set, and with `monitor` set to 1, 2 and 3 — the
ioctl accepts 2 and 3 although the help documents only 0 and 1, and neither
even creates the interface. No driver errors are logged. The radio is plainly
receiving; the frames simply never reach the monitor path.

So the practical answer is unchanged — **this box cannot be used as a wireless
sniffer** — but the reason is not that the feature is missing. It is another
instance of the pattern in `99-gotchas.md`: the presentation layer shipped
without the datapath behind it.

Enabling and disabling it is harmless. The AP kept running throughout and no
client dropped, which is consistent with "active monitor mode (interface still
operates)". Revert with `wl -i <if> monitor 0`.

As an AP, a server, or a wired appliance the box is excellent.
