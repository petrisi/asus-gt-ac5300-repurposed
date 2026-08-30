#!/bin/sh
#
# Bounded latency sampler. Writes /tmp/portal/ping.kv; the feeder reads that file
# and never waits on this script.
#
# WHY DECOUPLED: three pings at up to ~6s each is ~18s of wall clock. The feeder
# runs on a 60s tick and must never spend a third of its budget blocked on the
# network -- and if a target black-holes, the delay is unbounded in practice even
# with -W. So this runs detached and leaves its result behind for the NEXT feeder
# pass. Results are therefore up to one minute old, which is irrelevant for a
# trend line and buys complete isolation from a hung probe.

RUN=/tmp/portal
OUT="$RUN/ping.kv"
LOCK="$RUN/.ping.lock"

# Never stack up. If a previous run wedged, its lock ages out and we try again.
if [ -f "$LOCK" ]; then
    _age=$(( $(date +%s) - $(date -r "$LOCK" +%s 2>/dev/null || echo 0) ))
    [ "$_age" -lt 120 ] && exit 0
fi
: > "$LOCK"

# The gateway is read fresh every pass: this box has already moved networks once,
# and a hardcoded address would silently measure nothing afterwards.
GW=$(ip route show default 2>/dev/null | awk '{print $3; exit}')

# probe <target> -> "rtt jitter loss"
#
# busybox ping -q prints:
#   3 packets transmitted, 3 packets received, 0% packet loss
#   round-trip min/avg/max = 6.899/6.976/7.067 ms
#
# There is no mdev in this build, so jitter is reported as max-min, which is a
# spread rather than a true deviation -- adequate for spotting instability.
# Total loss produces no round-trip line at all, hence the empty-value guards.
probe() {
    [ -z "$1" ] && { echo "U U U"; return; }
    _o=$(ping -c 3 -W 2 -q "$1" 2>/dev/null)
    _loss=$(echo "$_o" | sed -n 's/.*[, ]\([0-9]*\)% packet loss.*/\1/p' | head -1)
    _min=$(echo "$_o"  | sed -n 's|.*= \([0-9.]*\)/\([0-9.]*\)/\([0-9.]*\).*|\1|p' | head -1)
    _avg=$(echo "$_o"  | sed -n 's|.*= \([0-9.]*\)/\([0-9.]*\)/\([0-9.]*\).*|\2|p' | head -1)
    _max=$(echo "$_o"  | sed -n 's|.*= \([0-9.]*\)/\([0-9.]*\)/\([0-9.]*\).*|\3|p' | head -1)

    [ -z "$_loss" ] && _loss=100
    [ -z "$_avg" ]  && _avg=U
    if [ -n "$_min" ] && [ -n "$_max" ]; then
        # awk, not shell: these are decimals and ash does integer arithmetic only
        _jit=$(awk -v a="$_min" -v b="$_max" 'BEGIN { printf "%.3f", b - a }')
    else
        _jit=U
    fi
    echo "$_avg $_jit $_loss"
}

set -- $(probe "$GW"); GW_RTT=$1; GW_JIT=$2; GW_LOSS=$3
set -- $(probe 1.1.1.1); C1_RTT=$1; C1_JIT=$2; C1_LOSS=$3
set -- $(probe 8.8.8.8); G8_RTT=$1; G8_JIT=$2; G8_LOSS=$3

# Published atomically -- the feeder must never read a half-written file.
{
    echo "TS=$(date +%s)"
    echo "GW_ADDR=${GW:-none}"
    echo "GW_RTT=$GW_RTT";  echo "GW_JIT=$GW_JIT";  echo "GW_LOSS=$GW_LOSS"
    echo "C1_RTT=$C1_RTT";  echo "C1_JIT=$C1_JIT";  echo "C1_LOSS=$C1_LOSS"
    echo "G8_RTT=$G8_RTT";  echo "G8_JIT=$G8_JIT";  echo "G8_LOSS=$G8_LOSS"
} > "$OUT.tmp" 2>/dev/null
mv "$OUT.tmp" "$OUT" 2>/dev/null

rm -f "$LOCK"
exit 0
