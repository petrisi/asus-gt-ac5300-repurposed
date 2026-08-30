#!/bin/sh
#
# RRD history feeder -- OPTIONAL layer for the status portal.
#
# ============================ DESIGN CONSTRAINTS ============================
#
# 1. THE CORE DASHBOARD MUST NOT DEPEND ON THIS.
#    rrdtool is an Entware binary on the USB stick. If the stick is absent this
#    script exits immediately and portal_collector.sh / status.json / the live
#    dashboard carry on completely unaffected. Only the History section degrades.
#
# 2. NO NEW SAMPLING OF HANG-PRONE INTERFACES.
#    Levels come from /tmp/portal/status.json, which portal_collector.sh already
#    produces. That file's producer already owns the bounded-read discipline for
#    wl ioctls and /proc/fcache (see docs/99-gotchas.md). Duplicating that sampling here
#    would duplicate the hazard. Direct reads are limited to things that cannot
#    block: sysfs counters, flat /proc files, iptables -n, and pidof.
#    Latency probing is the one unbounded operation, and it lives in a separate
#    detached script (rrd_ping.sh) whose result is read from a file.
#
# 3. NO SHELL ARITHMETIC ON COUNTERS.
#    32-bit ARM userland; busybox ash truncates values >= 2^31 to zero silently
#    (see docs/99-gotchas.md: 32-bit arithmetic). eth0 rx_bytes is already 23.1e9. Counters are passed to rrdtool
#    AS STRINGS and rrdtool does the maths in C. Do not compute deltas here.
#
# 4. GAPS MUST STAY VISIBLE.
#    Heartbeat 120s against a 60s step, and status.json is age-checked before it
#    is trusted. A wedged collector leaves a well-formed but OLD file; feeding it
#    would draw a flat line indistinguishable from a genuinely idle router.
#
# ===========================================================================

RUN=/tmp/portal
STATUS="$RUN/status.json"
USB_LABEL=ROUTERDATA
USB_MP="/tmp/mnt/$USB_LABEL"
RRD_DIR="$USB_MP/rrd"
SYS="$RRD_DIR/sys.rrd"
NET="$RRD_DIR/net.rrd"
BT="$RRD_DIR/bt.rrd"
HEALTH="$RRD_DIR/health.rrd"
FW="$RRD_DIR/fw.rrd"
IFR="$RRD_DIR/if.rrd"
WIFI="$RRD_DIR/wifi.rrd"
PING="$RRD_DIR/ping.rrd"
TSTATS=/opt/etc/transmission/stats.json
PINGKV="$RUN/ping.kv"
WANSTATE=/jffs/portal/.wanip
SYSLOG=/tmp/syslog.log
BT_PORT=51413
STEP=60
MAXAGE=150

RRDTOOL=/opt/bin/rrdtool

# *** MANDATORY for every Entware binary (see docs/99-gotchas.md: LD_LIBRARY_PATH). ***
unset LD_LIBRARY_PATH LD_PRELOAD

# ---------------------------------------------------------------- guards ----
mount | grep -q " $USB_MP " || exit 0
[ -x "$RRDTOOL" ]           || exit 0
mkdir -p "$RRD_DIR" 2>/dev/null

RRA_SET="RRA:AVERAGE:0.5:1:1440 RRA:AVERAGE:0.5:5:2016 RRA:AVERAGE:0.5:30:1488 RRA:AVERAGE:0.5:360:1460 RRA:MAX:0.5:1:1440 RRA:MAX:0.5:5:2016 RRA:MAX:0.5:30:1488 RRA:MAX:0.5:360:1460"

# ------------------------------------------------------------ rrd schema ----
#
# Grouped by domain, one file each. rrdtool 1.2 CANNOT add a data source to an
# existing file, so a new metric means either a new file or recreating an old one
# and discarding its history. Domain grouping keeps any future change contained.
#
# DERIVE (not COUNTER) throughout for counters: COUNTER treats a decrease as a
# hardware wrap and synthesises an enormous rate, and every counter here resets
# to zero on reboot or on a firewall flush. DERIVE with min=0 records the
# decrease as UNKNOWN, which is the truth.

if [ ! -f "$NET" ]; then
    $RRDTOOL create "$NET" --step $STEP \
        DS:wan_rx:DERIVE:120:0:150000000 DS:wan_tx:DERIVE:120:0:150000000 \
        DS:lan_rx:DERIVE:120:0:150000000 DS:lan_tx:DERIVE:120:0:150000000 \
        DS:bt_up:DERIVE:120:0:150000000  DS:bt_dn:DERIVE:120:0:150000000 \
        $RRA_SET 2>/dev/null && echo "$(date '+%F %T') created $NET" >> "$RUN/rrd.log"
fi

if [ ! -f "$SYS" ]; then
    $RRDTOOL create "$SYS" --step $STEP \
        DS:cpu:GAUGE:120:0:100 DS:cpu0:GAUGE:120:0:100 DS:cpu1:GAUGE:120:0:100 \
        DS:cpu2:GAUGE:120:0:100 DS:cpu3:GAUGE:120:0:100 \
        DS:temp:GAUGE:120:0:150 DS:mem_used:GAUGE:120:0:U DS:conn:GAUGE:120:0:U \
        DS:nvram:GAUGE:120:0:U DS:usb_used:GAUGE:120:0:U DS:leases:GAUGE:120:0:U \
        $RRA_SET 2>/dev/null && echo "$(date '+%F %T') created $SYS" >> "$RUN/rrd.log"
fi

# bt.rrd v1 held two aggregate DSs. Split by protocol because the peer port also
# carries the DHT: measured 27.7 kB/s outbound UDP while transmission reported
# 0.0 kB/s of payload. An aggregate line over-reads payload by >10x when idle.
if [ -f "$BT" ] && ! $RRDTOOL info "$BT" 2>/dev/null | grep -q 'ds\[up_tcp\]'; then
    mv "$BT" "$BT.v1-aggregate" 2>/dev/null
    echo "$(date '+%F %T') bt.rrd schema changed (aggregate -> tcp/udp split)" >> "$RUN/rrd.log"
fi
if [ ! -f "$BT" ]; then
    $RRDTOOL create "$BT" --step $STEP \
        DS:up_tcp:DERIVE:120:0:150000000 DS:up_udp:DERIVE:120:0:150000000 \
        DS:dn_tcp:DERIVE:120:0:150000000 DS:dn_udp:DERIVE:120:0:150000000 \
        $RRA_SET 2>/dev/null && echo "$(date '+%F %T') created $BT" >> "$RUN/rrd.log"
fi

# load is capped at 64 rather than U: a runaway makes the axis useless otherwise,
# and this box has already reached 19.5 (see docs/99-gotchas.md: fcache runaway).
if [ ! -f "$HEALTH" ]; then
    $RRDTOOL create "$HEALTH" --step $STEP \
        DS:load1:GAUGE:120:0:64 DS:load5:GAUGE:120:0:64 DS:load15:GAUGE:120:0:64 \
        DS:jffs_used:GAUGE:120:0:U DS:arp:GAUGE:120:0:U \
        DS:svc_tm:GAUGE:120:0:1 DS:svc_web:GAUGE:120:0:1 DS:svc_coll:GAUGE:120:0:1 \
        DS:wan_ip_age:GAUGE:120:0:U DS:bt_peers:GAUGE:120:0:U \
        DS:mem_cached:GAUGE:120:0:U DS:mem_slab:GAUGE:120:0:U \
        DS:prun:GAUGE:120:0:U DS:ctxt:GAUGE:120:0:U DS:intr:GAUGE:120:0:U \
        $RRA_SET 2>/dev/null && echo "$(date '+%F %T') created $HEALTH" >> "$RUN/rrd.log"
fi

if [ ! -f "$FW" ]; then
    $RRDTOOL create "$FW" --step $STEP \
        DS:drops_in:DERIVE:120:0:U DS:drops_inb:DERIVE:120:0:U DS:drops_fwd:DERIVE:120:0:U \
        DS:est4:GAUGE:120:0:U DS:est6:GAUGE:120:0:U \
        DS:sock_tcp:GAUGE:120:0:U DS:sock_udp:GAUGE:120:0:U \
        DS:sock_tcp6:GAUGE:120:0:U DS:sock_udp6:GAUGE:120:0:U \
        DS:ssh_scans:DERIVE:120:0:U \
        DS:rules_f:GAUGE:120:0:U DS:rules_n:GAUGE:120:0:U \
        DS:rules_m:GAUGE:120:0:U DS:rules_r:GAUGE:120:0:U \
        $RRA_SET 2>/dev/null && echo "$(date '+%F %T') created $FW" >> "$RUN/rrd.log"
fi

if [ ! -f "$IFR" ]; then
    $RRDTOOL create "$IFR" --step $STEP \
        DS:e0_rxerr:DERIVE:120:0:U DS:e0_rxdrop:DERIVE:120:0:U \
        DS:e0_txerr:DERIVE:120:0:U DS:e0_txdrop:DERIVE:120:0:U \
        DS:br_rxerr:DERIVE:120:0:U DS:br_rxdrop:DERIVE:120:0:U \
        DS:br_txerr:DERIVE:120:0:U DS:br_txdrop:DERIVE:120:0:U \
        $RRA_SET 2>/dev/null && echo "$(date '+%F %T') created $IFR" >> "$RUN/rrd.log"
fi

# noise is dBm and always negative, hence the -120:0 range. A GAUGE with min 0
# would silently discard every sample.
if [ ! -f "$WIFI" ]; then
    $RRDTOOL create "$WIFI" --step $STEP \
        DS:r0_noise:GAUGE:120:-120:0 DS:r0_idle:GAUGE:120:0:100 \
        DS:r0_glitch:GAUGE:120:0:U   DS:r0_cli:GAUGE:120:0:U DS:r0_tx:GAUGE:120:0:100 \
        DS:r1_noise:GAUGE:120:-120:0 DS:r1_idle:GAUGE:120:0:100 \
        DS:r1_glitch:GAUGE:120:0:U   DS:r1_cli:GAUGE:120:0:U DS:r1_tx:GAUGE:120:0:100 \
        DS:r2_noise:GAUGE:120:-120:0 DS:r2_idle:GAUGE:120:0:100 \
        DS:r2_glitch:GAUGE:120:0:U   DS:r2_cli:GAUGE:120:0:U DS:r2_tx:GAUGE:120:0:100 \
        $RRA_SET 2>/dev/null && echo "$(date '+%F %T') created $WIFI" >> "$RUN/rrd.log"
fi

if [ ! -f "$PING" ]; then
    $RRDTOOL create "$PING" --step $STEP \
        DS:gw_rtt:GAUGE:180:0:10000 DS:gw_jit:GAUGE:180:0:10000 DS:gw_loss:GAUGE:180:0:100 \
        DS:c1_rtt:GAUGE:180:0:10000 DS:c1_jit:GAUGE:180:0:10000 DS:c1_loss:GAUGE:180:0:100 \
        DS:g8_rtt:GAUGE:180:0:10000 DS:g8_jit:GAUGE:180:0:10000 DS:g8_loss:GAUGE:180:0:100 \
        $RRA_SET 2>/dev/null && echo "$(date '+%F %T') created $PING" >> "$RUN/rrd.log"
fi

[ -f "$NET" ] && [ -f "$SYS" ] || exit 1

# ------------------------------------------------------- status.json parse ---
#
# Parsed by isolating each sub-object first, then reading keys inside it. The
# earlier approach matched long anchored patterns from the start of the parent
# object; that worked but grew unreadable and would break on any field reorder.
# Sub-object isolation is both shorter and order-independent.
#
# "t" and "u" appear under both mem and usb, which is exactly why key lookups
# must be scoped to a parent rather than run against the whole line.
parse_status() {
    awk '
    function obj(name) {
        if (!match(line, "\"" name "\":\\{[^}]*\\}")) return ""
        return substr(line, RSTART, RLENGTH)
    }
    function fld(o, key,   s) {
        if (o == "") return "U"
        if (!match(o, "\"" key "\":-?[0-9]+(\\.[0-9]+)?")) return "U"
        s = substr(o, RSTART, RLENGTH)
        sub(/^[^:]*:/, "", s)
        return s
    }
    { line = line $0 }
    END {
        printf "P_CPU=%s\n", fld(line, "cpu")

        if (match(line, "\"cores\":\\[[0-9]+,[0-9]+,[0-9]+,[0-9]+\\]")) {
            c = substr(line, RSTART, RLENGTH); gsub(/[^0-9,]/, "", c)
            n = split(c, a, ",")
            for (i = 1; i <= 4; i++) printf "P_C%d=%s\n", i-1, (i <= n ? a[i] : "U")
        } else for (i = 0; i < 4; i++) printf "P_C%d=U\n", i

        tm = fld(line, "temp_m")
        printf "P_TEMP=%s\n", (tm == "U" ? "U" : tm / 1000)

        # load is a STRING field: "load":"2.58 2.44 2.45"
        if (match(line, "\"load\":\"[0-9. ]+\"")) {
            s = substr(line, RSTART, RLENGTH); gsub(/[^0-9. ]/, "", s)
            n = split(s, L, " ")
            printf "P_LOAD1=%s\nP_LOAD5=%s\nP_LOAD15=%s\n", \
                (n>0?L[1]:"U"), (n>1?L[2]:"U"), (n>2?L[3]:"U")
        } else printf "P_LOAD1=U\nP_LOAD5=U\nP_LOAD15=U\n"

        m = obj("mem")
        mt = fld(m, "t"); ma = fld(m, "a")
        # "used" excludes cache: total-available is what constrains the box.
        printf "P_MEMU=%s\n",   (mt == "U" || ma == "U" ? "U" : mt - ma)
        printf "P_MEMC=%s\n",   fld(m, "cached")
        printf "P_MEMS=%s\n",   fld(m, "slab")

        printf "P_CONN=%s\n",   fld(obj("ct"), "c")

        s = obj("sock")
        printf "P_EST4=%s\nP_EST6=%s\n", fld(s, "est4"), fld(s, "est6")
        printf "P_STCP=%s\nP_SUDP=%s\nP_STCP6=%s\nP_SUDP6=%s\n", \
            fld(s, "tcp"), fld(s, "udp"), fld(s, "tcp6"), fld(s, "udp6")

        y = obj("sys")
        printf "P_CTXT=%s\nP_INTR=%s\nP_PRUN=%s\n", \
            fld(y, "ctxt"), fld(y, "intr"), fld(y, "prun")

        f = obj("fw")
        printf "P_FWINP=%s\nP_FWINB=%s\nP_FWFWP=%s\n", \
            fld(f, "inp"), fld(f, "inb"), fld(f, "fwp")

        w = obj("slow")
        printf "P_NVU=%s\nP_ARP=%s\nP_JU=%s\n", fld(w, "nvu"), fld(w, "arp"), fld(w, "ju")
        printf "P_RF=%s\nP_RN=%s\nP_RM=%s\nP_RR=%s\n", \
            fld(w, "rf"), fld(w, "rn"), fld(w, "rm"), fld(w, "rr")

        printf "P_USBU=%s\n", fld(obj("usb"), "u")

        # dhcp contains a nested array, so obj() truncates at the first inner
        # brace -- harmless, because "n" precedes "leases" in the emitted order.
        printf "P_LEASE=%s\n", fld(obj("dhcp"), "n")

        # radios: fixed array of three, split on the object boundary
        if (match(line, "\"radios\":\\[.*\\],\"slow\"")) {
            r = substr(line, RSTART, RLENGTH)
            sub(/^"radios":\[/, "", r); sub(/\],"slow"$/, "", r)
            # split() treats its separator as a REGEX, and "{" is the interval
            # metacharacter -- passing "},{" aborts busybox awk with
            # "bad regex: Unmatched \{" and kills the whole program mid-output.
            # Rewrite the boundary to a sentinel with no regex meaning first.
            gsub(/\},\{/, "@@", r)
            nr = split(r, R, "@@")
            for (i = 1; i <= 3; i++) {
                o = (i <= nr) ? R[i] : ""
                printf "P_R%d_NOISE=%s\nP_R%d_IDLE=%s\nP_R%d_GLI=%s\nP_R%d_CLI=%s\nP_R%d_TX=%s\n", \
                    i-1, fld(o, "noise"), i-1, fld(o, "idle"), i-1, fld(o, "glitch"), \
                    i-1, fld(o, "clients"), i-1, fld(o, "tx")
            }
        } else for (i = 0; i < 3; i++) \
            printf "P_R%d_NOISE=U\nP_R%d_IDLE=U\nP_R%d_GLI=U\nP_R%d_CLI=U\nP_R%d_TX=U\n", i,i,i,i,i
    }' "$STATUS" 2>/dev/null
}

# Default everything to UNKNOWN, then overwrite only if status.json is FRESH.
for v in P_CPU P_C0 P_C1 P_C2 P_C3 P_TEMP P_MEMU P_MEMC P_MEMS P_CONN \
         P_EST4 P_EST6 P_STCP P_SUDP P_STCP6 P_SUDP6 P_CTXT P_INTR P_PRUN \
         P_FWINP P_FWINB P_FWFWP P_NVU P_ARP P_JU P_RF P_RN P_RM P_RR \
         P_USBU P_LEASE P_LOAD1 P_LOAD5 P_LOAD15 \
         P_R0_NOISE P_R0_IDLE P_R0_GLI P_R0_CLI P_R0_TX \
         P_R1_NOISE P_R1_IDLE P_R1_GLI P_R1_CLI P_R1_TX \
         P_R2_NOISE P_R2_IDLE P_R2_GLI P_R2_CLI P_R2_TX; do
    eval "$v=U"
done

SVC_COLL=0
if [ -f "$STATUS" ]; then
    _age=$(( $(date +%s) - $(date -r "$STATUS" +%s 2>/dev/null || echo 0) ))
    if [ "$_age" -le "$MAXAGE" ]; then
        eval "$(parse_status)"
    else
        echo "$(date '+%F %T') status.json stale (${_age}s) - writing UNKNOWN" >> "$RUN/rrd.log"
    fi
    # Collector liveness is judged by OUTPUT FRESHNESS, not by whether a process
    # exists. A hung collector stays in the process table forever -- that is
    # exactly how it once sat wedged for 3.4 days (see docs/99-gotchas.md: hung collector).
    [ "$_age" -le 30 ] && SVC_COLL=1
fi

# --------------------------------------------------------- direct sampling ---
rd() { cat "$1" 2>/dev/null || echo U; }

W_RX=$(rd /sys/class/net/eth0/statistics/rx_bytes)
W_TX=$(rd /sys/class/net/eth0/statistics/tx_bytes)
L_RX=$(rd /sys/class/net/br0/statistics/rx_bytes)
L_TX=$(rd /sys/class/net/br0/statistics/tx_bytes)

E0_RXE=$(rd /sys/class/net/eth0/statistics/rx_errors)
E0_RXD=$(rd /sys/class/net/eth0/statistics/rx_dropped)
E0_TXE=$(rd /sys/class/net/eth0/statistics/tx_errors)
E0_TXD=$(rd /sys/class/net/eth0/statistics/tx_dropped)
BR_RXE=$(rd /sys/class/net/br0/statistics/rx_errors)
BR_RXD=$(rd /sys/class/net/br0/statistics/rx_dropped)
BR_TXE=$(rd /sys/class/net/br0/statistics/tx_errors)
BR_TXD=$(rd /sys/class/net/br0/statistics/tx_dropped)

svc() { pidof "$1" >/dev/null 2>&1 && echo 1 || echo 0; }
SVC_TM=$(svc transmission-daemon)
SVC_WEB=$(svc lighttpd)

# BitTorrent peer count straight from /proc, avoiding netstat: 51413 = 0xC8D5,
# TCP state 01 = ESTABLISHED. netstat on a box holding thousands of peer sockets
# is measurably slower and buys nothing here.
BT_PEERS=$(cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | awk '$4 == "01" && $2 ~ /:C8D5$/ { n++ } END { print n+0 }')

# Cumulative count of rejected logins. Fed as DERIVE, so log rotation shows up as
# one UNKNOWN interval rather than a negative spike. Redirected from stdin so
# busybox grep prints a bare count with no filename prefix.
SSH_SCANS=$(grep -c "nonexistent user" < "$SYSLOG" 2>/dev/null)
[ -z "$SSH_SCANS" ] && SSH_SCANS=U

# WAN address stability: seconds since the address last changed.
#
# The state file lives on /jffs so it survives reboot, and is written ONLY when
# the address actually changes -- a once-a-minute write to NAND would be a
# pointless way to wear out flash that is never getting reflashed.
WANIP=$(nvram get wan0_ipaddr 2>/dev/null)
_now=$(date +%s); _prev=""; _since=""
[ -f "$WANSTATE" ] && read _prev _since < "$WANSTATE" 2>/dev/null
if [ -n "$WANIP" ] && [ "$WANIP" != "$_prev" ]; then
    echo "$WANIP $_now" > "$WANSTATE" 2>/dev/null
    _since=$_now
    [ -n "$_prev" ] && echo "$(date '+%F %T') WAN IP changed: $_prev -> $WANIP" >> "$RUN/rrd.log"
fi
case "$_since" in
    ''|*[!0-9]*) WAN_AGE=U ;;
    *)           WAN_AGE=$(( _now - _since )) ;;
esac

# --- BitTorrent wire counters, split by protocol ---
#
# Summed in AWK, never the shell: gigabyte totals, and ash truncates at 2^31.
# -n is essential -- without it iptables reverse-resolves every peer address.
# Emits nothing if no rule matched, so a flushed firewall records UNKNOWN rather
# than a fabricated zero.
btw() {
    { iptables -L "$1" -n -v -x 2>/dev/null; ip6tables -L "$1" -n -v -x 2>/dev/null; } \
      | awk -v pat="$2" '$0 ~ pat {
            p = "?"
            for (i = 1; i <= NF; i++) if ($i == "tcp" || $i == "udp") { p = $i; break }
            b[p] += $2; n++
        } END { if (n) printf "%.0f %.0f", b["tcp"] + 0, b["udp"] + 0 }'
}
# `set --` only at top level, never inside a function: doing it in a function
# overwrites that function's own arguments, which once printed a label as "25".
set -- $(btw OUTPUT "spt:$BT_PORT"); BTW_UT=${1:-U}; BTW_UU=${2:-U}
set -- $(btw INPUT  "dpt:$BT_PORT"); BTW_DT=${1:-U}; BTW_DU=${2:-U}

# --- transmission lifetime totals (authoritative for volume) ---
BT_UP=U; BT_DN=U
if [ -f "$TSTATS" ]; then
    BT_UP=$(sed -n 's/.*"uploaded-bytes": *\([0-9]*\).*/\1/p' "$TSTATS" 2>/dev/null | head -1)
    BT_DN=$(sed -n 's/.*"downloaded-bytes": *\([0-9]*\).*/\1/p' "$TSTATS" 2>/dev/null | head -1)
    [ -z "$BT_UP" ] && BT_UP=U
    [ -z "$BT_DN" ] && BT_DN=U
fi

# --- latency, produced by the detached sampler on its previous pass ---
GW_RTT=U; GW_JIT=U; GW_LOSS=U
C1_RTT=U; C1_JIT=U; C1_LOSS=U
G8_RTT=U; G8_JIT=U; G8_LOSS=U
if [ -f "$PINGKV" ]; then
    _page=$(( $(date +%s) - $(date -r "$PINGKV" +%s 2>/dev/null || echo 0) ))
    # Older than three minutes means the sampler stopped; record UNKNOWN rather
    # than replaying a stale round-trip time as if it were current.
    [ "$_page" -le 180 ] && . "$PINGKV" 2>/dev/null
fi

# ---------------------------------------------------------------- update ----
$RRDTOOL update "$NET"    "N:$W_RX:$W_TX:$L_RX:$L_TX:$BT_UP:$BT_DN"                    2>>"$RUN/rrd.err"
$RRDTOOL update "$SYS"    "N:$P_CPU:$P_C0:$P_C1:$P_C2:$P_C3:$P_TEMP:$P_MEMU:$P_CONN:$P_NVU:$P_USBU:$P_LEASE" 2>>"$RUN/rrd.err"
$RRDTOOL update "$BT"     "N:$BTW_UT:$BTW_UU:$BTW_DT:$BTW_DU"                          2>>"$RUN/rrd.err"
$RRDTOOL update "$HEALTH" "N:$P_LOAD1:$P_LOAD5:$P_LOAD15:$P_JU:$P_ARP:$SVC_TM:$SVC_WEB:$SVC_COLL:$WAN_AGE:$BT_PEERS:$P_MEMC:$P_MEMS:$P_PRUN:$P_CTXT:$P_INTR" 2>>"$RUN/rrd.err"
$RRDTOOL update "$FW"     "N:$P_FWINP:$P_FWINB:$P_FWFWP:$P_EST4:$P_EST6:$P_STCP:$P_SUDP:$P_STCP6:$P_SUDP6:$SSH_SCANS:$P_RF:$P_RN:$P_RM:$P_RR" 2>>"$RUN/rrd.err"
$RRDTOOL update "$IFR"    "N:$E0_RXE:$E0_RXD:$E0_TXE:$E0_TXD:$BR_RXE:$BR_RXD:$BR_TXE:$BR_TXD" 2>>"$RUN/rrd.err"
$RRDTOOL update "$WIFI"   "N:$P_R0_NOISE:$P_R0_IDLE:$P_R0_GLI:$P_R0_CLI:$P_R0_TX:$P_R1_NOISE:$P_R1_IDLE:$P_R1_GLI:$P_R1_CLI:$P_R1_TX:$P_R2_NOISE:$P_R2_IDLE:$P_R2_GLI:$P_R2_CLI:$P_R2_TX" 2>>"$RUN/rrd.err"
$RRDTOOL update "$PING"   "N:$GW_RTT:$GW_JIT:$GW_LOSS:$C1_RTT:$C1_JIT:$C1_LOSS:$G8_RTT:$G8_JIT:$G8_LOSS" 2>>"$RUN/rrd.err"

# Kick the latency sampler for the NEXT pass. Detached and self-locking, so this
# never blocks the feeder and never stacks up.
[ -x /jffs/portal/rrd_ping.sh ] && /jffs/portal/rrd_ping.sh >/dev/null 2>&1 &

# keep the error log bounded
if [ -f "$RUN/rrd.err" ]; then
    _n=$(wc -l < "$RUN/rrd.err" 2>/dev/null || echo 0)
    [ "$_n" -gt 200 ] && { tail -50 "$RUN/rrd.err" > "$RUN/rrd.err.t" 2>/dev/null; mv "$RUN/rrd.err.t" "$RUN/rrd.err" 2>/dev/null; }
fi

exit 0
