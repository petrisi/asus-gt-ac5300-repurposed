# Stopping the call-home services

Stock firmware runs a set of daemons that report to ASUS and Trend Micro. Some
have GUI toggles that work. Several have no switch at all, and one respawns
itself when killed.

None of this needs the internet blocked at a firewall. The goal is that the
processes are not running.

## What is actually running

Worth surveying before you remove anything:

    ps w
    nvram show 2>/dev/null | grep -iE "^(TM_|bwdpi|ahs|asd)" | sort

The ones this repository targets:

| process | what it is |
|---|---|
| `ahs` | ASUS Home Security telemetry |
| `asd` | ASUS Security Daemon — **respawns when killed** |
| `conn_diag` | connection diagnostics reporting |
| `nt_center`, `nt_monitor`, `nt_actMail` | notification centre + outbound mail |
| `vis-dcon`, `vis-datacollector` | traffic analyser data collection |
| `infosvr` | LAN discovery, UDP 9999, CVE history |
| `netool` | network tools daemon |
| `lld2d` | Microsoft link-layer topology responder |
| `usbmuxd` | iOS tethering helper |
| `wpsaide` | WPS button helper |

**Leave `eapd` alone.** It is the WPA authenticator. Kill it and your Wi-Fi
stops authenticating clients.

Think before removing `disk_monitor` too — it participates in USB hotplug
handling, so if you use USB storage you probably want it.

## `asd` needs two things, not one

Killing `asd` alone achieves nothing; a watchdog restarts it. There is an
undocumented nvram flag that stops the respawn:

    nvram set no_asd=1
    nvram commit

With that set, `killall asd` sticks. **Both halves are required** — the flag
alone does not stop a running instance, and the kill alone does not prevent
the restart.

## Sweep repeatedly, not once

Services come up staggered across the first couple of minutes of boot, so a
single kill at boot misses whatever starts later. `scripts/killsvc.sh` sweeps
every 30 seconds, six times, then logs the final state to `/jffs/killsvc.log`
so you can confirm what actually died.

Install it, make it executable, and let the boot wrapper from
`02-persistence.md` invoke it.

    cp killsvc.sh /jffs/killsvc.sh
    chmod 755 /jffs/killsvc.sh

## The firmware update check

Separately from the daemons, the box polls ASUS for firmware roughly every 90
seconds via `/usr/sbin/webs_update.sh`. Stubbing it stops the polling:

    cp /usr/sbin/webs_update.sh /jffs/webs_update.sh.orig
    mount -o remount,rw /
    printf '#!/bin/sh\nexit 0\n' > /usr/sbin/webs_update.sh
    chmod 755 /usr/sbin/webs_update.sh
    mount -o remount,ro /

The check then fails cleanly and logs one line per attempt instead of making a
request. **Only do this if you have accepted that you will never flash again** —
you are disabling the mechanism that tells you an update exists.

Related: `HMA: Download version info failed` in the log after this is not an
error, it is the blocking working.

## Confirming it worked

After a reboot:

    cat /jffs/killsvc.log        # per-process final state
    ps w | grep -cE "ahs|asd|conn_diag|nt_center"    # expect 0

If something is still alive, check whether it has a watchdog like `asd` did —
`nvram show | grep -i <name>` sometimes reveals an undocumented flag.
