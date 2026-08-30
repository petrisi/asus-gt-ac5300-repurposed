#!/bin/sh
# Replaces /usr/sbin/infosvr (original binary preserved at /jffs/infosvr.orig).
#
# rc execs this at boot. We use that as a boot hook, then exit -- infosvr is
# the ASUS discovery service on UDP 9999 with a long CVE history, which we
# want dead regardless, and nothing monitors or respawns it (verified:
# killing it left it dead).
#
# NOTE: chosen because it is a REAL binary. Most /sbin daemons here are
# symlinks to /sbin/rc; redirecting into one of those would overwrite the
# init binary and brick the device.
#
# TO RESTORE: mount -o remount,rw / && cp /jffs/infosvr.orig /usr/sbin/infosvr
#             && chmod 755 /usr/sbin/infosvr && mount -o remount,ro /

[ -x /jffs/killsvc.sh ] && /jffs/killsvc.sh &

exit 0
