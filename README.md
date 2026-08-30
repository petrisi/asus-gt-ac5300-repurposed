# Repurposing the ASUS GT-AC5300

Getting a root shell on a GT-AC5300, permanently silencing the vendor
call-home services, and turning it into something useful.

This router is end-of-life. The final firmware (`3.0.0.4.386_51582`) shipped in
2022 and there will be no more. That is exactly what makes it interesting: a
quad-core box with 1 GB of RAM and eight gigabit ports, obsolete as a router,
perfectly capable as an appliance.

Everything here was worked out on stock firmware. **No custom firmware, no
bootloader unlock, no soldering, no opening the case.** Asuswrt-Merlin does not
support this model, so all of this runs on what ASUS shipped.

<img width="1085" height="1866" alt="image" src="https://github.com/user-attachments/assets/0853a9c7-aaf3-45b0-9699-7796d33ed7df" />

## What you get

- A root shell that survives reboots
- The ASUS and Trend Micro call-home daemons stopped permanently — not paused,
  not firewalled, actually stopped and kept stopped
- A dependency-free status dashboard (`docs/05-dashboard.md`)
- Entware, so you have a real package manager (`docs/04-usb-and-entware.md`)
- A BitTorrent seedbox with the RPC locked down (`docs/06-bittorrent.md`)
- Optional long-term metric history via rrdtool (`docs/07-rrd-history.md`)

## Start here

| | |
|---|---|
| [00-hardware.md](docs/00-hardware.md) | what the box is, and the one architectural quirk that will bite you |
| [01-getting-shell.md](docs/01-getting-shell.md) | SSH, key types, and making the key survive a reboot |
| [02-persistence.md](docs/02-persistence.md) | **making anything survive a reboot — the hard part** |
| [03-disable-telemetry.md](docs/03-disable-telemetry.md) | **stopping the call-home services for good** |
| [04-usb-and-entware.md](docs/04-usb-and-entware.md) | storage and a package manager |
| [05-dashboard.md](docs/05-dashboard.md) | the status portal |
| [06-bittorrent.md](docs/06-bittorrent.md) | Transmission |
| [07-rrd-history.md](docs/07-rrd-history.md) | long-term history |
| [08-exposure.md](docs/08-exposure.md) | if it faces the internet |
| [10-wl-commands.md](docs/10-wl-commands.md) | the radio control surface: 638 commands, tiered by what is safe to call |
| [11-acsd-channel-selection.md](docs/11-acsd-channel-selection.md) | why one radio changes channel every 15 minutes, and how to audit its choices |
| [wl-tier-a-catalog.md](reference/wl-tier-a-catalog.md) | catalogue of all 476 safely-readable wl commands, by function |
| [wl-tier-bcd-catalog.md](reference/wl-tier-bcd-catalog.md) | the 160 wl commands that act, transmit or persist — and what each one costs |
| [99-gotchas.md](docs/99-gotchas.md) | **the platform traps — read this before debugging anything** |

Set your values in [CONFIG.md](CONFIG.md) first.

## Read this before you start

**You can brick this router.** One step in `02-persistence.md` involves
replacing a binary in the read-only root filesystem. There is a specific,
plausible mistake there that overwrites the init binary and leaves you with a
box that will not boot. The guide tells you how to check for it. Do the check.

Nothing here is reversible from the GUI. Recovery means the firmware restore
mode, which means losing your configuration.

This is your own hardware. Disabling telemetry on a device you own is
unremarkable; if you are doing it to someone else's, that is between you and
them.

The BitTorrent section assumes you are distributing things you have the right
to distribute — Linux images and similar. The tooling does not care what you
point it at; the law does.

## Scope

One model, one firmware build. Much of it — the persistence hooks, the
Entware target, the busybox limitations — applies to other Broadcom-based
Asuswrt routers of the same era, but none of that has been verified here.

MIT licensed. No warranty, in the legal sense and the practical one.
