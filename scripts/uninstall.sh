#!/bin/sh
#
# Undo everything this repository installs, in dependency order.
# Safe to run repeatedly; every step is guarded.

PORTAL=/jffs/portal
HOOK=/usr/sbin/infosvr
ORIG=/jffs/infosvr.orig

say() { echo "  $*"; }

echo
echo "=== 1. stop what is running ==="

# Match on comm, never on cmdline: matching cmdline patterns will kill the
# shell running this script, because its cmdline contains the pattern.
for c in start.sh portal_collecto lighttpd transmission-daemon; do
    for p in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
        [ "$p" = "$$" ] && continue
        if [ "$(cat /proc/$p/comm 2>/dev/null)" = "$c" ]; then
            kill "$p" 2>/dev/null && say "stopped $c (pid $p)"
        fi
    done
done

echo
echo "=== 2. restore the boot hook ==="
if [ -f "$ORIG" ]; then
    mount -o remount,rw /
    if cp "$ORIG" "$HOOK" && chmod 755 "$HOOK"; then
        say "restored $HOOK from $ORIG"
    else
        say "FAILED to restore $HOOK - do it by hand before rebooting"
    fi
    mount -o remount,ro /
else
    say "no $ORIG saved; leaving $HOOK alone"
    say "if it is still the wrapper, restore it from a firmware copy"
fi

echo
echo "=== 3. remove installed scripts ==="
# killsvc.sh and start.sh are both invoked behind [ -x ] guards, so removing
# them is sufficient to disable the chain even if a hook remains.
for f in /jffs/killsvc.sh /jffs/killsvc.log; do
    [ -e "$f" ] && rm -f "$f" && say "removed $f"
done
if [ -d "$PORTAL" ]; then
    rm -rf "$PORTAL"
    say "removed $PORTAL"
fi

echo
echo "=== 4. revert nvram ==="
if [ "$(nvram get no_asd)" = "1" ]; then
    nvram unset no_asd
    nvram commit
    say "unset no_asd (asd will respawn again after a reboot)"
fi

echo
echo "=== 5. things this does NOT undo ==="
cat <<'MANUAL'

  - firewall rules added by start.sh: they live in memory only and are gone
    after a reboot, or flush them now with your own iptables/ip6tables commands
  - the webs_update.sh stub, if you applied it:
        mount -o remount,rw /
        cp /jffs/webs_update.sh.orig /usr/sbin/webs_update.sh
        chmod 755 /usr/sbin/webs_update.sh
        mount -o remount,ro /
  - Entware on the USB stick: unmount /opt and delete the directory
  - anything you changed in the GUI

MANUAL

echo "=== done - reboot to return to stock behaviour ==="
echo
