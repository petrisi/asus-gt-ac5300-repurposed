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

**No frames are ever delivered to it.** Measured at the driver level, on every
radio:

    radio         monitor iface   frames captured   radio rx, same window
    eth6 2.4 GHz  prism0          0                 1612
    eth7 5 GHz-1  prism1          0                  457
    eth8 5 GHz-2  prism2          0                  509

Each radio gets its own correctly-indexed monitor device, so the plumbing is
wired up per-radio — the missing piece is only the datapath.

Tested with every promisc bit set (`promisc ctrl fcs`); on each radio
individually and with all three enabled simultaneously; and with `monitor` set
to 1, 2 and 3 — the ioctl accepts 2 and 3 although the help documents only 0
and 1, and neither even creates the interface. No driver errors are logged. The
radios are plainly receiving; the frames simply never reach the monitor path.

So the practical answer is unchanged — **this box cannot be used as a wireless
sniffer** — but the reason is not that the feature is missing. It is another
instance of the pattern in `99-gotchas.md`: the presentation layer shipped
without the datapath behind it.

### Where exactly the path breaks, and whether it can be fixed

Short answer: **the dongle firmware is built without monitor support, and there
is no host-side setting that changes that.**

The host driver is not the problem. `dhd.ko` contains the entire receive path —
`dhd_add_monitor_if`, `dhd_del_monitor_if`, `dhd_rx_mon_pkt`,
`netdev_monitor_ops`, and strings for both `prism` and `radiotap`. It creates
the interface correctly, one per radio.

The firmware is the problem, and it says so twice.

**The capability string omits it.** `wl -i <if> cap` lists what the firmware
advertises, and there is no `monitor` entry:

    160 802.11d 802.11h ampdu ampdu_rx ampdu_tx amsdurx amsdutx anqpo ap
    bcm_dcs bgdfs bsstrans cac ccx cptlv-4 cqa dfrts dwds dyn160 led mbss8 mfp
    multi-user-beamformee multi-user-beamformer p2po probresp_mac_filter
    proptxstatus pspretend psr psta radio_pwrsave rm rxchain_pwrsave
    single-user-beamformee single-user-beamformer sta stbc-rx-1ss stbc-tx toe
    traffic-mgmt traffic-mgmt-dwm txpwrcache vht-prop-rates wds wet wme wnm

**The firmware build name omits it too.** Broadcom names these images after
their compiled-in feature set, and the string is embedded in `dhd.ko`:

    4366c0-roml/pcie-ag-splitrx-fdap-mbss-mfp-wnm-osen-wl11k-wl11u-txbf-pktctx-
    amsdutx-ampduretry-chkd2hdma-proptxstatus-11nprop-obss-dbwsw-ringer-
    dmaindex16-bgdfs-stamon-hostpmac-murx-splitassoc-hostmemucode-dyn160-dhdhdr

No `monitor`, and no `wltest`/`mfgtest` either. So the dongle never emits
monitor packets, `dhd_rx_mon_pkt` is never called, and `prism0` stays empty.

No host-side knob overrides this. `monitor_type`, `monitor_format` and a
`dhd`-level `monitor` iovar are all absent or `Unsupported`; `promisc` and
`allmulti` are already 1 and make no difference.

**Could you replace the firmware?** In principle. In practice, no:

- the image is embedded in `dhd.ko` (1.75 MB); the `firmware_path` module
  parameter exists but is empty
- Broadcom does not publish alternative 4366c0 builds, and a monitor-enabled
  one is not available anywhere public
- driver and firmware are version-locked — this pairs dhd `1.363.45.84015` with
  firmware `10.10.122.20`
- a mismatch traps the dongle, and `/usr/sbin/dhd_monitor` (a crash watchdog,
  unrelated to packet monitoring) responds by restarting wireless — so a bad
  blob gives you a reboot loop, not a diagnostic

**What the firmware does offer** is `stamon`, exposed as `wl sta_monitor`. It is
per-station statistics rather than frame capture, so it is not a sniffing
substitute — and in testing it produced no usable data either.

Registration is genuinely implemented: `add` with a malformed address returns
`Bad Argument`, and `del` of an address that was never added returns
`Not Found`, so the driver validates input and tracks list membership.

But `sta_monitor counters` only ever reports a single figure, `stamon cnt=N`,
and it stayed at `0` for a registered, associated, actively transmitting station
across 60 seconds — during which that station's `sta_info` packet count rose by
several hundred. A stale value of 23 was observed once, left over from earlier
monitor-mode experiments; it was static, `reset_cnts` cleared it, and it did not
resume counting when monitor mode was re-enabled.

One case could not be tested: a station transmitting on the monitored channel
that is *not* associated to this radio, which is what STA monitor is arguably
designed for. Scanning is rejected while the interface is an AP, and there were
no cached results to supply a neighbouring address. So it is not established
whether the counter is unfed, or simply had nothing in scope to count.

If you need frames off the air, use a USB adapter with a `mac80211` driver.
That is its own project on this platform, and worth checking module
availability before committing to it.

Enabling and disabling it is harmless. Testing included radios carrying live
clients, and not one dropped — the "active monitor mode (interface still
operates)" claim holds. Revert with `wl -i <if> monitor 0`; the prism device
disappears with it.

As an AP, a server, or a wired appliance the box is excellent.
