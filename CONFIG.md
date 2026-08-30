# Values you must set

Every script in this repository is written against these. Change them once,
here, and grep for them before you run anything.

| value | default | where |
|---|---|---|
| USB volume label | `ROUTERDATA` | `USB_LABEL` in `scripts/portal/start.sh`, `rrd_feeder.sh`, `rrd_export.sh` |
| Dashboard port | `8080` | `PORT` in `scripts/portal/start.sh` |
| BitTorrent peer port | `51413` | `BT_PORT` in `scripts/portal/start.sh`, `rrd_feeder.sh` |
| Portal directory | `/jffs/portal` | `PORTAL` in `scripts/portal/start.sh` |
| Runtime directory | `/tmp/portal` | `RUN`, everywhere |

## Why the dashboard is not on port 80

ASUS's own `httpd` already owns port 80 on the LAN address and on loopback.
Binding there fights the GUI. 8080 is arbitrary but free.

## Why the USB volume is found by label, not device node

`/dev/sda1` is not stable if you ever attach a second disk. The scripts resolve
the label through `blkid`, then cache the mountpoint — see the
`blkid`/`ubi_open_volume` entry in `docs/99-gotchas.md` for why they only probe
when the volume is actually missing.

## Interface names on this model

    eth0    WAN
    br0     LAN bridge (includes all wired ports and all three radios)
    eth6    2.4 GHz radio
    eth7    5 GHz-1 radio
    eth8    5 GHz-2 radio

These differ between models. Check `nvram get wl_ifnames` before assuming.
