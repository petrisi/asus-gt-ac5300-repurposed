#!/bin/sh
# Kill ASUS daemons that have no nvram switch on stock firmware.
# Invoked at boot from the /usr/sbin/infosvr wrapper (see scripts/infosvr-wrapper.sh).
#
# TO DISABLE THE WHOLE MECHANISM: delete this file. The wrapper is guarded
# with [ -x ], so a missing file is a silent no-op.

LOG=/jffs/killsvc.log
LOCK=/tmp/killsvc.lock
# asd is included deliberately: nvram no_asd=1 blocks the watchdog respawn,
# so killing it here makes it stick. Both halves are required.
# disk_monitor deliberately NOT in this list any more: USB storage is in use, and
# it participates in mount/hotplug handling. usbmuxd stays killed (iOS tethering).
# wpsaide: WPS is disabled (nvram + driver SES_OW bit cleared) but rc still starts
# this button helper. Inert, not watchdog-guarded, killed for tidiness.
# eapd is NOT here -- it is the WPA authenticator and must keep running.
TARGETS="ahs asd conn_diag nt_center nt_monitor nt_actMail netool infosvr vis-dcon vis-datacollector lld2d usbmuxd wpsaide"

# Only one instance per boot. /tmp is tmpfs, so this clears itself.
[ -f "$LOCK" ] && exit 0
touch "$LOCK"

# Status portal (independent of the kill sweeps; guarded so deleting the file
# disables it). Delayed so rc has finished building the firewall chains.
[ -x /jffs/portal/start.sh ] && ( sleep 55; /jffs/portal/start.sh ) >/dev/null 2>&1 &

# keep the log bounded
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 65536 ]; then
    rm -f "$LOG"
fi

echo "=== run start, uptime $(cut -d' ' -f1 /proc/uptime) ===" >> "$LOG"

# Services come up spread out over the first couple of minutes, so sweep
# repeatedly rather than once.
i=0
while [ "$i" -lt 6 ]; do
    sleep 30
    for p in $TARGETS; do
        killall "$p" 2>/dev/null
    done
    i=$((i + 1))
done

echo "--- final state, uptime $(cut -d' ' -f1 /proc/uptime) ---" >> "$LOG"
for p in $TARGETS; do
    if pidof "$p" >/dev/null 2>&1; then
        echo "  $p: RUNNING" >> "$LOG"
    else
        echo "  $p: gone" >> "$LOG"
    fi
done
echo >> "$LOG"

exit 0
