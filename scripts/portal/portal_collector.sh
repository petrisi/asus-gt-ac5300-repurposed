#!/bin/sh
# Samples router telemetry into /tmp/portal/status.json
#
# Writes to /tmp (tmpfs/RAM) deliberately -- NOT /jffs. At a 2s interval this is
# ~43k writes/day; putting that on NAND would wear it out for no reason.
#
# *** ALL COUNTER ARITHMETIC IS DONE IN AWK, NOT THE SHELL. ***
#
# This userland is 32-bit ARM and busybox ash arithmetic silently truncates any
# value >= 2^31 to ZERO -- no error, no warning:
#     rx_bytes=18821963980 ; echo $((rx_bytes + 1))   ->  1
# Interface byte counters pass 2 GB within hours of real traffic, so shell-based
# deltas produce a permanent 0 for the busier direction while the quieter one
# still looks fine. That is exactly how it presented: WAN "download" stuck at 0
# while "upload" tracked correctly, which reads as swapped labels.
# awk uses doubles and is exact to 2^53, so all deltas are computed there.

RUN=/tmp/portal
JSON="$RUN/status.json"
TMP="$RUN/.status.tmp"
INTERVAL=2
SLOWMOD=15          # 15 x 2s = every 30s
WANIF=eth0
LANIF=br0
USB_LINK=/tmp/usb   # symlink maintained by start.sh; absent when no stick is mounted
THERMAL=/sys/class/thermal/thermal_zone0/temp

mkdir -p "$RUN"

# Device identity -- read once so the page carries no hardcoded assumptions.
h_model=$(nvram get productid); [ -z "$h_model" ] && h_model="router"
h_name=$(cat /proc/sys/kernel/hostname 2>/dev/null); [ -z "$h_name" ] && h_name="$h_model"
h_lan=$(nvram get lan_ipaddr)
h_mask=$(nvram get lan_netmask)
h_fw="$(nvram get firmver).$(nvram get buildno)_$(nvram get extendno)"

d_on=$(nvram get dhcp_enable_x);  [ -z "$d_on" ] && d_on=0
d_st=$(nvram get dhcp_start);     d_en=$(nvram get dhcp_end)
d_ls=$(nvram get dhcp_lease);     [ -z "$d_ls" ] && d_ls=0
LEASES=/var/lib/misc/dnsmasq.leases

# ---- raw snapshot helpers: emit space-separated counters, no arithmetic ----
snap_cpu()  { awk '/^cpu /{printf "%.0f %.0f", $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat; }
snap_core() { awk '/^cpu[0-9]/{printf "%.0f %.0f ", $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat; }
snap_net()  { awk -v w="$WANIF" -v l="$LANIF" '
                { gsub(/:/, " ")
                  if ($1 == w) { wr = $2; wt = $10 }
                  if ($1 == l) { lr = $2; lt = $10 } }
                END { printf "%.0f %.0f %.0f %.0f", wr, wt, lr, lt }' /proc/net/dev; }
snap_sys()  { awk '/^ctxt /{c=$2} /^intr /{i=$2} /^procs_running/{r=$2}
                   END{printf "%.0f %.0f %s", c, i, r}' /proc/stat; }
snap_fw()   { iptables -L -n -v -x 2>/dev/null | awk '
                /^Chain INPUT/   { c = "i"; next }
                /^Chain FORWARD/ { c = "f"; next }
                /^Chain /        { c = "";  next }
                c == "i" && $3 == "DROP" { ip += $1; ib += $2 }
                c == "f" && $3 == "DROP" { fp += $1; fb += $2 }
                END { printf "%.0f %.0f %.0f %.0f", ip, ib, fp, fb }'; }

wl_to() {   # bounded wl call -- wl can block forever against this driver
    _if=$1; shift
    : > "$RUN/.wl"
    wl -i "$_if" "$@" > "$RUN/.wl" 2>/dev/null &
    _p=$!; _n=0
    while kill -0 "$_p" 2>/dev/null; do
        [ "$_n" -ge 50 ] && { kill -9 "$_p" 2>/dev/null; break; }
        usleep 100000; _n=$((_n + 1))
    done
    wait "$_p" 2>/dev/null
    cat "$RUN/.wl" 2>/dev/null
}

# Bounded line-count of a /proc file that can wedge.
#
# /proc/fcache/nflist normally returns ~11 lines instantly, but reading it takes a
# lock the Broadcom flow cache also takes on its own datapath. Under load (heavy
# seeding) the read can block FOREVER. What that cost, observed 2026-08-15:
# the collector stalled mid-cycle, the supervisor killed it for being stale, and
# the awk child was reparented to init where it spun at 100% CPU. One orphan per
# cycle, ~18 of them, load 19.5, the box barely usable -- while the dashboard just
# showed frozen numbers.
#
# ONE child process, deliberately NOT a pipeline: `awk ... | grep -c .` gives two
# pids and $! is only the last, so killing on timeout left the awk behind. That is
# precisely how the orphans accumulated. awk counts internally, so there is a
# single pid and the timeout kill is complete.
proc_count() {   # $1 = file, $2 = header lines to skip. Echoes count; nothing on timeout.
    : > "$RUN/.pc"
    awk -v s="$2" 'NR>s{n++} END{print n+0}' "$1" > "$RUN/.pc" 2>/dev/null &
    _p=$!; _n=0
    while kill -0 "$_p" 2>/dev/null; do
        [ "$_n" -ge 20 ] && { kill -9 "$_p" 2>/dev/null; wait "$_p" 2>/dev/null; return 1; }
        usleep 100000; _n=$((_n + 1))
    done
    wait "$_p" 2>/dev/null
    cat "$RUN/.pc" 2>/dev/null
}

P_CPU=$(snap_cpu); P_CORE=$(snap_core); P_NET=$(snap_net)
P_SYS=$(snap_sys); P_FW=$(snap_fw); P_FW_SLOW="$P_FW"
first=1; tick=0
rfi=0; rff=0
s_nvu=0; s_nvf=0; s_arp=0; s_flow=0; s_ju=0; s_jt=0
s_rf=0; s_rn=0; s_rm=0; s_rr=0
s_up=0; s_ut=0; s_uu=0; s_ua=0     # USB absent until proven present
s_dhn=0; s_dhl=""; s_radios=""

while :; do
    sleep "$INTERVAL"

    C_CPU=$(snap_cpu); C_CORE=$(snap_core); C_NET=$(snap_net)
    C_SYS=$(snap_sys); C_FW=$(snap_fw)

    # One awk call computes every rate. Assignments are eval'd back into the shell
    # as already-safe small integers.
    eval "$(awk -v pcpu="$P_CPU" -v ccpu="$C_CPU" \
                -v pcore="$P_CORE" -v ccore="$C_CORE" \
                -v pnet="$P_NET" -v cnet="$C_NET" \
                -v psys="$P_SYS" -v csys="$C_SYS" \
                -v pfw="$P_FW" -v cfw="$C_FW" \
                -v iv="$INTERVAL" -v first="$first" 'BEGIN {
        split(pcpu,A," "); split(ccpu,B," ")
        dt = B[1]-A[1]; di = B[2]-A[2]
        cpu = (first==0 && dt>0) ? int(100*(dt-di)/dt) : 0
        if (cpu<0) cpu=0; if (cpu>100) cpu=100
        printf "CPU=%d\n", cpu

        n = split(pcore,PC," "); split(ccore,CC," ")
        for (i=1; i<=n/2; i++) {
            t = CC[2*i-1]-PC[2*i-1]; d = CC[2*i]-PC[2*i]
            k = (first==0 && t>0) ? int(100*(t-d)/t) : 0
            if (k<0) k=0; if (k>100) k=100
            printf "K%d=%d\n", i-1, k
        }
        printf "NCORE=%d\n", n/2

        split(pnet,PN," "); split(cnet,CN," ")
        nm[1]="WRX"; nm[2]="WTX"; nm[3]="LRX"; nm[4]="LTX"
        for (i=1; i<=4; i++) {
            d = CN[i]-PN[i]
            if (d<0 || first!=0) d=0          # counter reset/wrap, or first pass
            printf "%s=%.0f\n", nm[i], d/iv
        }

        split(psys,PS," "); split(csys,CS," ")
        dc = CS[1]-PS[1]; dI = CS[2]-PS[2]
        if (dc<0 || first!=0) dc=0
        if (dI<0 || first!=0) dI=0
        printf "RCTXT=%.0f\nRINTR=%.0f\nPRUN=%s\n", dc/iv, dI/iv, CS[3]

        split(pfw,PF," "); split(cfw,CF," ")
        printf "FWIP=%.0f\nFWIB=%.0f\nFWFP=%.0f\nFWFB=%.0f\n", CF[1], CF[2], CF[3], CF[4]
    }')"

    P_CPU="$C_CPU"; P_CORE="$C_CORE"; P_NET="$C_NET"; P_SYS="$C_SYS"; P_FW="$C_FW"

    # ---- memory (KB values, always well under 2^31) ----
    set -- $(awk '/^MemTotal/{t=$2} /^MemFree/{f=$2} /^MemAvailable/{a=$2}
                  /^Cached/{c=$2} /^Slab/{s=$2} END{print t,f,a,c,s}' /proc/meminfo)
    mt=$1; mf=$2; ma=$3; mc=$4; ms=$5

    ctc=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null); [ -z "$ctc" ] && ctc=0
    ctm=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null); [ -z "$ctm" ] && ctm=0
    # NOTE: /proc/net/sockstat is IPv4 ONLY -- IPv6 lives in sockstat6. The old
    # "TCP / UDP" row was therefore showing v4 counts labelled as totals.
    set -- $(awk '/^sockets:/{u=$3} /^TCP:/{t=$3} /^UDP:/{d=$3} END{print u+0,t+0,d+0}' /proc/net/sockstat)
    sall=$1; stcp=$2; sudp=$3
    set -- $(awk '/^TCP6:/{t=$3} /^UDP6:/{d=$3} END{print t+0,d+0}' /proc/net/sockstat6 2>/dev/null)
    stcp6=${1:-0}; sudp6=${2:-0}
    # established only ($4=="01"), which is the number that reflects real peers
    est4=$(awk 'NR>1 && $4=="01"' /proc/net/tcp  2>/dev/null | grep -c .)
    est6=$(awk 'NR>1 && $4=="01"' /proc/net/tcp6 2>/dev/null | grep -c .)
    ent=$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null); [ -z "$ent" ] && ent=0

    # ---- slow tick ----
    if [ "$tick" -eq 0 ]; then
        # firewall drop rate over the 30s window, expressed per minute (awk math)
        if [ "$first" -eq 0 ]; then
            eval "$(awk -v p="$P_FW_SLOW" -v c="$C_FW" 'BEGIN{
                split(p,P," "); split(c,C," ")
                di=C[1]-P[1]; df=C[3]-P[3]
                if(di<0)di=0; if(df<0)df=0
                printf "rfi=%.0f\nrff=%.0f\n", di*2, df*2 }')"
        fi
        P_FW_SLOW="$C_FW"

        set -- $(nvram show 2>&1 >/dev/null | awk '/size:/{gsub(/[^0-9 ]/," "); print $1, $2}')
        s_nvu=${1:-0}; s_nvf=${2:-0}
        s_arp=$(awk 'NR>1' /proc/net/arp 2>/dev/null | grep -c .)
        # BOUNDED -- see proc_count(). An unbounded read here once drove the box to
        # load 19 with orphaned awk processes. -1 means "could not read", which the
        # UI shows as n/a; it must never silently report a stale flow count.
        s_flow=$(proc_count /proc/fcache/nflist 2)
        [ -z "$s_flow" ] && s_flow=-1
        set -- $(df /jffs 2>/dev/null | awk 'NR==2{print $3, $2}')
        s_ju=${1:-0}; s_jt=${2:-0}

        # USB capacity -- deliberately NO dependency on the stick being present.
        # Absence is a reported state, not an error: the symlink is resolved, the
        # result checked against the mount table, and df is only run on a path
        # confirmed to be a real mount. If the stick is pulled, present=0 and the
        # collector carries on unaffected. df on a stale mount point can block,
        # which is why the mount check comes first rather than relying on df.
        s_up=0; s_ut=0; s_uu=0; s_ua=0
        _um=$(readlink -f "$USB_LINK" 2>/dev/null)
        if [ -n "$_um" ] && mount | grep -q " $_um "; then
            set -- $(df -k "$_um" 2>/dev/null | awk 'NR==2{print $2, $3, $4}')
            s_ut=${1:-0}; s_uu=${2:-0}; s_ua=${3:-0}
            [ "$s_ut" -gt 0 ] 2>/dev/null && s_up=1
        fi
        s_rf=$(iptables -S 2>/dev/null | grep -c .)
        s_rn=$(iptables -t nat -S 2>/dev/null | grep -c .)
        s_rm=$(iptables -t mangle -S 2>/dev/null | grep -c .)
        s_rr=$(iptables -t raw -S 2>/dev/null | grep -c .)

        s_dhn=$(grep -c . "$LEASES" 2>/dev/null); [ -z "$s_dhn" ] && s_dhn=0
        s_dhl=$(awk '{ gsub(/"/,"",$4)
            printf "%s{\"exp\":%s,\"mac\":\"%s\",\"ip\":\"%s\",\"host\":\"%s\"}",
                   (NR>1?",":""), $1, $2, $3, ($4=="*"?"":$4) }' "$LEASES" 2>/dev/null)

        s_radios=""; sep=""
        for IF in eth6 eth7 eth8; do
            case "$IF" in
                eth6) BAND="2.4 GHz" ;;
                eth7) BAND="5 GHz-1" ;;
                *)    BAND="5 GHz-2" ;;
            esac
            rmask=$(wl_to "$IF" radio)
            if [ "$rmask" = "0x0000" ]; then ron=1; else ron=0; fi
            rssid=""; rch=""; rnoise=0; ridle=0; rtx=0; robss=0; rglitch=0; rcl=0
            if [ "$ron" -eq 1 ]; then
                rssid=$(wl_to "$IF" ssid | sed 's/.*"\(.*\)".*/\1/')
                rch=$(wl_to "$IF" status | awk -F'Channel: ' '/Channel: /{print $2; exit}')
                rnoise=$(wl_to "$IF" noise); [ -z "$rnoise" ] && rnoise=0
                set -- $(wl_to "$IF" chanim_stats | awk 'NR==3{print $2, $4, $11, $14}')
                rtx=${1:-0}; robss=${2:-0}; rglitch=${3:-0}; ridle=${4:-0}
                rcl=$(wl_to "$IF" assoclist | grep -c assoclist)
                case "$rnoise"  in ''|*[!0-9-]*) rnoise=0 ;; esac
                case "$ridle"   in ''|*[!0-9]*)  ridle=0  ;; esac
                case "$rtx"     in ''|*[!0-9]*)  rtx=0    ;; esac
                case "$robss"   in ''|*[!0-9]*)  robss=0  ;; esac
                case "$rglitch" in ''|*[!0-9]*)  rglitch=0 ;; esac
            fi
            s_radios="${s_radios}${sep}{\"if\":\"$IF\",\"band\":\"$BAND\",\"on\":$ron,\"ssid\":\"$rssid\",\"ch\":\"$rch\",\"noise\":$rnoise,\"idle\":$ridle,\"tx\":$rtx,\"obss\":$robss,\"glitch\":$rglitch,\"clients\":$rcl}"
            sep=","
        done
    fi
    tick=$(( (tick + 1) % SLOWMOD ))

    temp=$(cat "$THERMAL" 2>/dev/null); [ -z "$temp" ] && temp=0
    up=$(cut -d' ' -f1 /proc/uptime)
    load=$(cut -d' ' -f1-3 /proc/loadavg)
    now=$(date +%s)
    clock=$(date '+%Y-%m-%d %H:%M:%S')
    tzn=$(date '+%Z')
    [ -z "$K0" ] && K0=0; [ -z "$K1" ] && K1=0
    [ -z "$K2" ] && K2=0; [ -z "$K3" ] && K3=0

    printf '{"ts":%s,"clock":"%s","tz":"%s",'\
'"host":{"model":"%s","name":"%s","lan":"%s","mask":"%s","fw":"%s"},'\
'"up":%s,"load":"%s","cpu":%s,"cores":[%s,%s,%s,%s],"temp_m":%s,'\
'"mem":{"t":%s,"f":%s,"a":%s,"cached":%s,"slab":%s},'\
'"wan":{"rx":%s,"tx":%s},"lan":{"rx":%s,"tx":%s},'\
'"ct":{"c":%s,"m":%s},'\
'"sock":{"all":%s,"tcp":%s,"udp":%s,"tcp6":%s,"udp6":%s,"est4":%s,"est6":%s},'\
'"sys":{"ctxt":%s,"intr":%s,"prun":%s,"ent":%s},'\
'"fw":{"inp":%s,"inb":%s,"inr":%s,"fwp":%s,"fwb":%s,"fwr":%s},'\
'"dhcp":{"on":%s,"start":"%s","end":"%s","lease":%s,"n":%s,"leases":[%s]},'\
'"radios":[%s],'\
'"slow":{"nvu":%s,"nvf":%s,"arp":%s,"flows":%s,"ju":%s,"jt":%s,'\
'"rf":%s,"rn":%s,"rm":%s,"rr":%s},'\
'"usb":{"on":%s,"t":%s,"u":%s,"a":%s}}\n' \
        "$now" "$clock" "$tzn" \
        "$h_model" "$h_name" "$h_lan" "$h_mask" "$h_fw" \
        "$up" "$load" "$CPU" "$K0" "$K1" "$K2" "$K3" "$temp" \
        "$mt" "$mf" "$ma" "$mc" "$ms" \
        "$WRX" "$WTX" "$LRX" "$LTX" \
        "$ctc" "$ctm" "$sall" "$stcp" "$sudp" "$stcp6" "$sudp6" "$est4" "$est6" \
        "$RCTXT" "$RINTR" "$PRUN" "$ent" \
        "$FWIP" "$FWIB" "$rfi" "$FWFP" "$FWFB" "$rff" \
        "$d_on" "$d_st" "$d_en" "$d_ls" "$s_dhn" "$s_dhl" \
        "$s_radios" \
        "$s_nvu" "$s_nvf" "$s_arp" "$s_flow" "$s_ju" "$s_jt" \
        "$s_rf" "$s_rn" "$s_rm" "$s_rr" \
        "$s_up" "$s_ut" "$s_uu" "$s_ua" > "$TMP" 2>/dev/null

    mv "$TMP" "$JSON" 2>/dev/null
    first=0
done
