#!/bin/sh
# Starts and supervises the status portal: lighttpd (static) + telemetry collector,
# plus the USB mount and Entware /opt bind.
#
# TO DISABLE: delete /jffs/portal/start.sh  (killsvc.sh guards with [ -x ])

PORTAL=/jffs/portal
RUN=/tmp/portal
CONF="$RUN/lighttpd.conf"
STALE=150            # seconds without a status.json update before restarting the collector
PORT=8080            # NOT 80: ASUS httpd owns port 80 on the LAN address and loopback,
                     # so a 0.0.0.0:80 bind would collide. 8080 is free.
USB_LABEL=ROUTERDATA
USB_LINK=/tmp/usb    # stable path -- everything else references this, not a device node
AUTHFILE="$PORTAL/.htdigest"   # deliberately NOT under $PORTAL/www (would be downloadable)
BT_PORT=51413                  # transmission peer port; RPC 9091 stays localhost-only

# Interfaces resolved from nvram rather than hardcoded, so this survives a move.
WANIF=$(nvram get wan0_ifname 2>/dev/null); [ -z "$WANIF" ] && WANIF=eth0
LANIF=$(nvram get lan_ifname 2>/dev/null); [ -z "$LANIF" ] && LANIF=br0

mkdir -p "$RUN"

# Ensure the USB stick is mounted and /tmp/usb points at it.
#
# Located BY LABEL, not by device node: /dev/sda1 is not stable if another disk is
# ever attached. Idempotent, so it is safe to call from the supervision loop -- that
# also makes a stick survive being unplugged and reinserted without a reboot.
ensure_usb() {
    # FAST PATH: already mounted where we expect -- do NOT probe.
    #
    # blkid opens every block device it can find, and that includes the UBI volume
    # holding the read-only rootfs. The open is refused with EBUSY and the kernel
    # logs, every single time:
    #
    #   ubi0 error: ubi_open_volume: cannot open device 0, volume 0, error -16
    #
    # At one supervisor pass per 30s that was ~2,880 lines/day: 1,748 of the 2,310
    # lines in syslog, i.e. 76% of the log, burying every real event and rotating
    # genuine history away early. Measured directly -- one blkid call produces
    # exactly one such message.
    #
    # Probing is only needed when the volume is NOT mounted, which is the rare case.
    # The slow path below is unchanged and still handles first mount, reinsertion,
    # and a stick mounted somewhere unexpected.
    _mp="/tmp/mnt/$USB_LABEL"
    if mount | grep -q " $_mp "; then
        ln -sfn "$_mp" "$USB_LINK" 2>/dev/null
        return 0
    fi

    _dev=$(blkid 2>/dev/null | awk -F: -v l="LABEL=\"$USB_LABEL\"" 'index($0,l){print $1; exit}')
    if [ -z "$_dev" ]; then
        for _m in scsi_mod sd_mod usb-storage; do modprobe "$_m" 2>/dev/null; done
        _dev=$(blkid 2>/dev/null | awk -F: -v l="LABEL=\"$USB_LABEL\"" 'index($0,l){print $1; exit}')
    fi
    [ -z "$_dev" ] && { rm -f "$USB_LINK" 2>/dev/null; return 1; }

    _mp=$(mount | awk -v d="$_dev" '$1==d {print $3; exit}')
    if [ -z "$_mp" ]; then
        _mp="/tmp/mnt/$USB_LABEL"
        mkdir -p "$_mp"
        mount -t ext4 -o rw,noatime "$_dev" "$_mp" 2>/dev/null || { rm -f "$USB_LINK" 2>/dev/null; return 1; }
    fi
    ln -sfn "$_mp" "$USB_LINK" 2>/dev/null
    return 0
}

# Re-establish /opt (Entware) after a reboot.
#
# /opt is a firmware symlink to /tmp/opt, which is tmpfs -- so the bind mount onto
# the copy on USB must be recreated every boot or the entire Entware tree silently
# disappears. /etc/profile already puts /opt/sbin:/opt/bin on PATH.
ensure_opt() {
    [ -e "$USB_LINK" ] || return 1
    _src="$USB_LINK/opt"
    [ -d "$_src/bin" ] || return 1
    mkdir -p /tmp/opt
    if ! mount | grep -q " /tmp/opt "; then
        mount -o bind "$_src" /tmp/opt 2>/dev/null || return 1
    fi
    # Entware services are deliberately NOT auto-started. This device is EOL and
    # never patched again, so every extra listener is permanent attack surface.
    # Uncomment when you actually want installed services to come up at boot:
    # [ -x /opt/etc/init.d/rc.unslung ] && /opt/etc/init.d/rc.unslung start
    return 0
}

# Firewall policy for the dashboard.
#
# lighttpd binds the wildcard address so it follows any address change automatically
# -- there is no bind address to go stale when this box moves to another network. It
# binds "::" dual-stack (see the config below), which covers IPv4 too. Access is
# restricted here instead, by INTERFACE rather than by subnet, so it also survives
# a move:
#   - allowed  on the WAN-side interface  (the trusted upstream network)
#   - DROPPED  on the LAN bridge          (the guest network -- guests must not see this)
#
# The DROP must precede ASUS's blanket "ACCEPT all NEW from br0" rule, so both are
# inserted at position 1. rc rebuilds these chains on various events, hence the
# re-assertion from the supervision loop.
ensure_fw() {
    iptables -C INPUT -i "$LANIF" -p tcp --dport "$PORT" -j DROP 2>/dev/null || \
        iptables -I INPUT 1 -i "$LANIF" -p tcp --dport "$PORT" -j DROP 2>/dev/null
    iptables -C INPUT -i "$WANIF" -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT 1 -i "$WANIF" -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null
    # retire the old wide-open port 80 rule if it is still present
    if iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null; then
        iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
    fi

    # BitTorrent peer port, TCP and UDP (uTP/DHT need UDP). Inbound connections
    # are the whole point of seeding from a routable address.
    # Transmission's RPC (9091) is bound to 127.0.0.1 and is deliberately NOT
    # opened here -- it is reached over an SSH tunnel instead.
    for _pr in tcp udp; do
        iptables -C INPUT -i "$WANIF" -p "$_pr" --dport "$BT_PORT" -j ACCEPT 2>/dev/null || \
            iptables -I INPUT 1 -i "$WANIF" -p "$_pr" --dport "$BT_PORT" -j ACCEPT 2>/dev/null
    done

    # --- IPv6 ---
    # ip6tables is a SEPARATE table: none of the rules above apply to it. With
    # IPv6 Native enabled, ASUS generates its own chain which opens tcp/22 to
    # ::/0 but leaves the BitTorrent port closed -- so IPv6 peers could not reach
    # the seed, which is most of the reason for having IPv6 at all.
    # Transmission already listens on :::51413, so only the filter needs opening.
    if [ -x /usr/sbin/ip6tables ] || command -v ip6tables >/dev/null 2>&1; then
        for _pr in tcp udp; do
            ip6tables -C INPUT -i "$WANIF" -p "$_pr" --dport "$BT_PORT" -j ACCEPT 2>/dev/null || \
                ip6tables -I INPUT 1 -i "$WANIF" -p "$_pr" --dport "$BT_PORT" -j ACCEPT 2>/dev/null
        done

        # Dashboard over IPv6.
        #
        # Once an AAAA record exists for this box, clients PREFER IPv6 (RFC 6724).
        # Without this rule the v6 packets hit the chain's trailing DROP and the
        # dashboard is reachable only because Happy Eyeballs gives up on v6 after
        # ~250ms and retries over v4. A v6-only client never reaches it at all,
        # and because it is DROP rather than REJECT the failure is a silent hang.
        #
        # NOTE the asymmetry with IPv4: there, 8080 is also explicitly DROPped on
        # $LANIF. No equivalent is added here because ASUS's generated v6 chain
        # already ACCEPTs everything NEW arriving on $LANIF ahead of this rule, so
        # a DROP appended below it would never match. Nothing is attached to that
        # segment today; revisit if that changes.
        ip6tables -C INPUT -i "$WANIF" -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || \
            ip6tables -I INPUT 1 -i "$WANIF" -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null
    fi

    # --- BitTorrent byte accounting (measurement only, no filtering) ---
    #
    # These rules have NO TARGET. A targetless rule counts the packets it matches
    # and falls through to the next rule, so nothing about what the firewall
    # permits or blocks changes -- they are pure instrumentation.
    #
    # WHY: transmission only rewrites its stats.json every few minutes, so a rate
    # derived from it is a comb of spikes and zeroes rather than a throughput
    # line. These counters advance continuously, giving a smooth signal.
    #
    # Inbound is already counted for free by the ACCEPT rules above (dport 51413),
    # which sit ABOVE the RELATED,ESTABLISHED rule in both families and therefore
    # see every packet of those flows. Only the outbound direction needs adding.
    #
    # ACCURACY, stated plainly: this measures the peer port, not the process.
    # Connections that WE initiate to a remote peer carry an ephemeral source port
    # and the peer's listening port, so no port-based rule can see them -- against
    # transmission's own figures the inbound counters captured ~53% of the
    # download, which was dominated by outbound-initiated connections. Seeding is
    # mostly inbound-initiated, so upload capture is far higher, but it is still a
    # SUBSET. Authoritative totals therefore keep coming from transmission; these
    # counters exist to give the throughput chart its shape.
    # (An owner-match would be exact, but transmission runs as uid 0 alongside
    # everything else on this box, so it cannot discriminate.)
    #
    # Inserted at position 1 so no earlier rule can terminate the packet before it
    # is counted.
    for _pr in tcp udp; do
        iptables -C OUTPUT -p "$_pr" --sport "$BT_PORT" 2>/dev/null || \
            iptables -I OUTPUT 1 -p "$_pr" --sport "$BT_PORT" 2>/dev/null
        if [ -x /usr/sbin/ip6tables ] || command -v ip6tables >/dev/null 2>&1; then
            ip6tables -C OUTPUT -p "$_pr" --sport "$BT_PORT" 2>/dev/null || \
                ip6tables -I OUTPUT 1 -p "$_pr" --sport "$BT_PORT" 2>/dev/null
        fi
    done
}

# Start transmission only when the USB volume is genuinely mounted.
#
# WITHOUT THIS GUARD: download-dir lives under /tmp/usb, and if the stick is
# missing that path resolves into tmpfs -- transmission would happily download
# into RAM, appear to work, and quietly consume memory until the box died.
ensure_transmission() {
    _tlog="$RUN/transmission.log"
    _tlock="$RUN/.transmission.starting"

    [ -x /opt/bin/transmission-daemon ] || return 1
    mount | grep -q " /tmp/mnt/$USB_LABEL " || return 1
    pidof transmission-daemon >/dev/null 2>&1 && { rm -f "$_tlock"; return 0; }

    # A start already in flight?
    #
    # Transmission can take 20s+ to appear on a slow USB volume. The first version
    # of this waited only 3s, decided it had failed, and let the next 30s loop pass
    # launch a SECOND instance -- the two fought over the config lock and both died,
    # every 30s, forever. The lock makes starts non-reentrant; the stale timeout
    # stops a crashed attempt from wedging it permanently.
    if [ -f "$_tlock" ]; then
        _age=$(( $(date +%s) - $(date -r "$_tlock" +%s 2>/dev/null || echo 0) ))
        [ "$_age" -lt 90 ] && return 0
        echo "$(date '+%H:%M:%S') previous attempt stale after ${_age}s, retrying" >> "$_tlog"
    fi
    : > "$_tlock"

    killall transmission-daemon 2>/dev/null   # clear any half-dead instance
    sleep 2

    echo "$(date '+%H:%M:%S') starting transmission..." >> "$_tlog"
    # Launched DIRECTLY rather than via /opt/etc/init.d/S88transmission.
    # rc.func runs the daemon as `$PROC $ARGS > /dev/null 2>&1 &`, discarding its
    # stderr -- so a startup failure is completely silent and undiagnosable.
    #
    # *** LD_LIBRARY_PATH MUST BE UNSET FOR ANY ENTWARE BINARY. ***
    #
    # The firmware exports LD_LIBRARY_PATH=/lib:/usr/lib:/lib/aarch64 (see
    # /etc/profile), and start.sh inherits it from rc at boot. Entware binaries
    # carry DT_RUNPATH=/opt/lib, but LD_LIBRARY_PATH takes PRECEDENCE over RUNPATH
    # -- so they load the firmware's older glibc/libstdc++ and die with:
    #     libstdc++.so.6: version `GLIBCXX_3.4.22' not found
    #     libc.so.6: version `GLIBC_2.25' not found
    #
    # This is why it "worked when run by hand": `ssh host 'cmd'` is a non-login
    # shell, never sources /etc/profile, so the variable is unset there. The
    # Entware installer unsets both vars in its first lines for exactly this reason.
    #
    # Scoped to a subshell so firmware binaries elsewhere in this script keep the
    # library path they expect.
    (
        unset LD_LIBRARY_PATH LD_PRELOAD
        TRANSMISSION_WEB_HOME=/opt/share/transmission/public_html \
            /opt/bin/transmission-daemon -g /opt/etc/transmission
    ) >> "$_tlog" 2>&1
    _n=0
    while [ "$_n" -lt 30 ]; do
        pidof transmission-daemon >/dev/null 2>&1 && break
        sleep 1; _n=$((_n + 1))
    done
    echo "$(date '+%H:%M:%S') settled after ${_n}s: pid=[$(pidof transmission-daemon)]" >> "$_tlog"
    rm -f "$_tlock"
    return 0
}

# busybox truncates /proc/PID/comm to 15 chars, so `killall portal_collector.sh`
# never matches -- it sees "portal_collecto". Match the truncated form instead.
#
# Matched on /proc/PID/comm rather than the full `ps` command line: a command line
# match also hits any *other* shell that merely mentions the name -- which killed an
# interactive SSH session during development. comm is the process's own name only.
kill_collectors() {
    for _c in /proc/[0-9]*; do
        _n=$(cat "$_c/comm" 2>/dev/null)
        case "$_n" in
            portal_collecto) kill -9 "${_c#/proc/}" 2>/dev/null ;;
            wl)              kill -9 "${_c#/proc/}" 2>/dev/null ;;  # orphaned wl call
        esac
    done
}

start_collector() {
    kill_collectors
    "$PORTAL/portal_collector.sh" >/dev/null 2>&1 &
}

# --- stop anything we started previously ---
if [ -f "$RUN/lighttpd.pid" ]; then
    kill "$(cat "$RUN/lighttpd.pid")" 2>/dev/null
    rm -f "$RUN/lighttpd.pid"
fi

ensure_usb
ensure_opt

# --- lighttpd config (regenerated each start; /tmp is volatile anyway) ---
cat > "$CONF" <<EOF
server.document-root = "$PORTAL/www"
server.port          = $PORT
# Dual-stack on ONE socket.
#
# server.bind is deliberately NOT set: with use-ipv6 enabled and v6only disabled,
# lighttpd binds "::" and the kernel accepts IPv4 as v4-mapped on the same socket
# (this box has net.ipv6.bindv6only = 0). Result is ":::8080", matching how sshd
# and transmission already appear.
#
# set-v6only MUST stay "disable". With it enabled the socket becomes IPv6-only and
# the dashboard disappears over IPv4 -- which is still the path that works when the
# AAAA record is stale, i.e. exactly when it is most needed.
server.use-ipv6      = "enable"
server.set-v6only    = "disable"
server.modules       = ( "mod_access", "mod_alias", "mod_auth", "mod_indexfile", "mod_staticfile" )
server.pid-file      = "$RUN/lighttpd.pid"
server.errorlog      = "$RUN/error.log"
index-file.names     = ( "index.html" )

# live telemetry comes from tmpfs, not the document root
alias.url = ( "/data/" => "$RUN/" )

mimetype.assign = (
  ".html" => "text/html",
  ".css"  => "text/css",
  ".js"   => "application/javascript",
  ".json" => "application/json",
  ".svg"  => "image/svg+xml",
  ""      => "text/plain"
)
EOF

# HTTP authentication.
#
# DIGEST, not basic: this is plain HTTP, and basic auth transmits the password on
# every request. Digest never sends it.
#
# Appended only if the credentials file exists — a missing file must not stop
# lighttpd from starting, which would take the dashboard down entirely rather than
# merely leaving it unauthenticated.
#
# The realm is read back OUT of the file rather than hardcoded, because a digest
# hash is computed over the realm: any mismatch means every login silently fails.
#
# The userfile lives in $PORTAL, NOT $PORTAL/www — inside the document root it
# would be downloadable, which would hand over the password hash.
if [ -f "$AUTHFILE" ]; then
    _realm=$(cut -d: -f2 "$AUTHFILE" 2>/dev/null | head -1)
    [ -z "$_realm" ] && _realm="router status"
    cat >> "$CONF" <<EOF

auth.backend                   = "htdigest"
auth.backend.htdigest.userfile = "$AUTHFILE"
auth.require = ( "/" => (
    "method"  => "digest",
    "realm"   => "$_realm",
    "require" => "valid-user"
) )
EOF
fi

start_collector
/usr/sbin/lighttpd -f "$CONF" >/dev/null 2>&1
ensure_fw

# RRD history -- an OPTIONAL layer, deliberately isolated.
#
# Both scripts are no-ops when the USB volume or Entware is missing; they check
# for themselves rather than being gated here, so there is exactly one place that
# decides (see rrd_feeder.sh header). The live dashboard must not acquire a
# dependency on the stick, so nothing below is allowed to affect the collector,
# lighttpd, or status.json.
#
# Run in the BACKGROUND and gated on stamp files: the supervision loop must never
# block on rrdtool, and the gate prevents a slow run being launched again on the
# next 30s pass -- the duplicate-instance trap that transmission fell into.
ensure_rrd() {
    [ -x "$PORTAL/rrd_feeder.sh" ] || return 0

    _fs="$RUN/.rrd_feed_stamp"
    if [ ! -f "$_fs" ] || [ $(( $(date +%s) - $(date -r "$_fs" +%s 2>/dev/null || echo 0) )) -ge 55 ]; then
        : > "$_fs"
        "$PORTAL/rrd_feeder.sh" >/dev/null 2>&1 &
    fi

    # Exporting is far heavier than feeding (dozens of rrdtool fetches) and the
    # coarsest window gains a point only every 6 hours, so 5 minutes is ample.
    if [ -x "$PORTAL/rrd_export.sh" ]; then
        _es="$RUN/.rrd_export_stamp"
        if [ ! -f "$_es" ] || [ $(( $(date +%s) - $(date -r "$_es" +%s 2>/dev/null || echo 0) )) -ge 300 ]; then
            : > "$_es"
            "$PORTAL/rrd_export.sh" >/dev/null 2>&1 &
        fi
    fi
}

# --- supervision loop ---
while :; do
    ensure_fw
    ensure_usb && ensure_opt && ensure_transmission
    ensure_rrd

    # lighttpd liveness
    if [ ! -f "$RUN/lighttpd.pid" ] || ! kill -0 "$(cat "$RUN/lighttpd.pid" 2>/dev/null)" 2>/dev/null; then
        /usr/sbin/lighttpd -f "$CONF" >/dev/null 2>&1
    fi

    # collector liveness -- checked by OUTPUT FRESHNESS, not process existence.
    # A hung collector stays in the process table forever (observed: blocked on a
    # wl ioctl during a DFS event), so "is it running" is not a useful question.
    NOW=$(date +%s)
    MTIME=$(date -r "$RUN/status.json" +%s 2>/dev/null)
    [ -z "$MTIME" ] && MTIME=0
    if [ $((NOW - MTIME)) -gt "$STALE" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') collector stale ($((NOW - MTIME))s) - restarting" >> "$RUN/watchdog.log"
        start_collector
    fi

    sleep 30
done
