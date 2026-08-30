#!/bin/sh
#
# Guided installer. Run this ON the router, from the scripts/ directory.
#
# It does the safe parts automatically and REFUSES to do the dangerous one.
# Replacing a binary in the read-only rootfs is the step that can brick the
# device, so this script verifies the preconditions and then prints the exact
# commands for you to run yourself, having read them.

PORTAL=/jffs/portal
HOOK=/usr/sbin/infosvr

say()  { echo "  $*"; }
fail() { echo "  ERROR: $*"; exit 1; }

echo
echo "=== 1. platform checks ==="

[ -d /jffs ] || fail "/jffs not present - is this an Asuswrt router?"
touch /jffs/.wtest 2>/dev/null || fail "/jffs is not writable"
rm -f /jffs/.wtest
say "/jffs writable: yes"

say "kernel:   $(uname -m)   (aarch64 expected)"
say "userland: $(readelf -h /bin/busybox 2>/dev/null | sed -n 's/.*Class:  *//p' || echo 'ELF32 (assumed)')"
say "model:    $(nvram get productid 2>/dev/null)"
say "firmware: $(nvram get buildno 2>/dev/null).$(nvram get extendno 2>/dev/null)"

echo
echo "=== 2. THE BRICK CHECK ==="
#
# If the hook target is a symlink to rc, writing a wrapper there replaces init
# and the router will not boot. There is no recovery except firmware restore.
_real=$(readlink -f "$HOOK" 2>/dev/null)
say "$HOOK resolves to: ${_real:-<missing>}"
if [ "$_real" != "$HOOK" ]; then
    echo
    fail "$HOOK is a symlink (to $_real). DO NOT wrap it. Pick a different
         hook that is a real file, and re-check with readlink -f."
fi
say "not a symlink: safe to wrap"

echo
echo "=== 3. installing scripts to /jffs (safe, reversible) ==="

mkdir -p "$PORTAL/www" || fail "could not create $PORTAL"

if [ -f killsvc.sh ]; then
    cp killsvc.sh /jffs/killsvc.sh && chmod 755 /jffs/killsvc.sh
    say "installed /jffs/killsvc.sh"
fi

for f in portal/*.sh; do
    [ -f "$f" ] || continue
    cp "$f" "$PORTAL/" && chmod 755 "$PORTAL/$(basename "$f")"
    say "installed $PORTAL/$(basename "$f")"
done

if [ -f portal/www/index.html ]; then
    cp portal/www/index.html "$PORTAL/www/"
    say "installed $PORTAL/www/index.html"
fi

echo
echo "=== 4. syntax-checking everything installed ==="
_bad=0
for f in /jffs/killsvc.sh "$PORTAL"/*.sh; do
    [ -f "$f" ] || continue
    if sh -n "$f" 2>/dev/null; then
        say "OK   $f"
    else
        say "FAIL $f"; _bad=1
    fi
done
[ "$_bad" -eq 0 ] || fail "syntax errors above - nothing else will be done"

echo
echo "=== 5. stop the respawning daemon ==="
say "setting no_asd=1 (blocks the asd watchdog respawn)"
nvram set no_asd=1
nvram commit
say "no_asd is now: $(nvram get no_asd)"

echo
echo "=== 6. THE PART YOU MUST DO YOURSELF ==="
cat <<'MANUAL'

  Installing the boot hook modifies the read-only root filesystem. Read
  docs/02-persistence.md first, then run these by hand:

      cp /usr/sbin/infosvr /jffs/infosvr.orig      # keep the original
      mount -o remount,rw /
      cp infosvr-wrapper.sh /usr/sbin/infosvr
      chmod 755 /usr/sbin/infosvr
      mount -o remount,ro /

      head -1 /usr/sbin/infosvr                    # expect #!/bin/sh
      sh -n /usr/sbin/infosvr                      # expect no output

  To undo it, now or later:

      mount -o remount,rw /
      cp /jffs/infosvr.orig /usr/sbin/infosvr
      chmod 755 /usr/sbin/infosvr
      mount -o remount,ro /

  Write that second block down somewhere that is not on the router.

MANUAL

echo "=== done ==="
say "Scripts are installed but nothing runs until the hook is in place."
say "After installing the hook and rebooting, check /jffs/killsvc.log"
echo
