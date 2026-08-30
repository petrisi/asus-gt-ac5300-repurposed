#!/bin/sh
#
# Regenerate the wl command inventory for THIS router's firmware.
#
# Writes a TSV of every command, its safety tier, and the first line of its
# built-in help. Run it on the router; it changes nothing.
#
#   ./wl-inventory.sh              > wl-commands.tsv
#   ./wl-inventory.sh --sweep-a    also executes every Tier A command (reads only)
#
# WHY THIS EXISTS: `wl -h` describes roughly 180 commands. `wl cmds` lists about
# 650. The difference carries built-in help but no listing, so it is invisible
# unless you already know the name.

IFACE=${IFACE:-eth6}
SWEEP=0
[ "$1" = "--sweep-a" ] && SWEEP=1

# --- every wl call is bounded -----------------------------------------------
#
# Two hazards, both encountered while building this:
#
#   1. `wl -h <cmd>` is NOT purely textual for every command. One of them hung
#      for 540 seconds in __skb_recv_datagram and stalled two harvest runs.
#   2. wl inherits stdin. Inside `while read ... done < list`, it consumes the
#      command list -- a 650-entry sweep silently processed 188 and stopped.
#      Hence `< /dev/null` on every invocation.
run_bounded() {   # $1=outfile, rest=args to wl
    _o=$1; shift
    : > "$_o"
    wl "$@" > "$_o" 2>&1 < /dev/null &
    _p=$!; _n=0
    while kill -0 "$_p" 2>/dev/null; do
        if [ "$_n" -ge 20 ]; then kill -9 "$_p" 2>/dev/null; wait "$_p" 2>/dev/null; return 1; fi
        usleep 100000; _n=$((_n + 1))
    done
    wait "$_p" 2>/dev/null
    return 0
}

# --- tier classification ----------------------------------------------------
#
# Broadcom convention: `wl <cmd>` reads, `wl <cmd> <value>` writes. So most
# commands are safe to call bare. The tiers capture the exceptions.
#
# Classification uses the HELP TEXT as well as the name, deliberately. A
# name-only pass let srclear ("Clears first 'len' bytes of the srom"), clmload,
# shmemx and diag into the "safe" bucket -- nothing in those names says danger.
NAME_D='^(cis|otp|sprom|sr(write|read|clear)|txcal|rpcalvars|radioreg|phytable|clmload|calload|shmem|diag$|perm_etheraddr|manfinfo|revinfo|phy_(txiqcc|txlocc|afeoverride|vcore|setrptbl|read_estpwrlut|test_))|^(regulatory|country|autocountry|sar_limit|bmac_reboot|dongleset|ucantdiv|olpc_|nvram_)'
HELP_D='srom|otp|cis|calibrat|shared memory|nvram|clm data|erase|clears first|permanent'
NAME_B='^(up|down|out|reboot|restart|reset|scan|escan|iscan|join|disassoc|deauthenticate|deauthorize|authorize|pkteng_|ota_|seq_|dfs_ap_move|interface_|tkip_countermeasures|reset_cnts|reset_d11cnts|drift_stats_reset|scanabort|escanabort|pfnclear|scancache_clear|p2po_(find|listen|stop)|anqpo_(start|stop)_query|proxd_(find|stop))|_clear$|_clear_stats$|clear_dump$'
HELP_C='send|transmit|inject|wakeup frame|request frame'

classify() {   # $1=name $2=help  ->  echoes A|B|C|D
    if echo "$1" | grep -qE "$NAME_D"; then echo D; return; fi
    if echo "$2" | grep -qiE "$HELP_D"; then echo D; return; fi
    if echo "$1" | grep -qE "$NAME_B"; then echo B; return; fi
    if echo "$2" | grep -qiE "$HELP_C"; then echo C; return; fi
    if echo "$1" | grep -qE '_(req|add|del)$'; then echo C; return; fi
    echo A
}

# --- enumerate --------------------------------------------------------------
LIST=/tmp/wlinv_cmds.$$
wl cmds 2>/dev/null | tr ' ,\t' '\n' | sed 's/[^a-zA-Z0-9_]//g' \
  | grep -E '^[a-z_][a-z_0-9]*$' | sort -u > "$LIST"

echo "# wl command inventory"
echo "# model:    $(nvram get productid 2>/dev/null)"
echo "# firmware: $(nvram get buildno 2>/dev/null).$(nvram get extendno 2>/dev/null)"
echo "# wl ver:   $(wl -i "$IFACE" ver 2>/dev/null | tail -1)"
echo "#"
echo "# A = bare call reads, safe    B = bare call acts, exclude from sweeps"
echo "# C = transmits or needs args  D = persistent/regulatory/calibration, do not touch"
echo "#"
printf 'command\ttier\thelp\n'

TMP=/tmp/wlinv_h.$$
TIERA=/tmp/wlinv_tierA.$$
: > "$TIERA"
while read -r c; do
    if run_bounded "$TMP" -h "$c"; then
        h=$(cat "$TMP" 2>/dev/null)
        case "$h" in *"Unrecognized command"*) continue ;; esac
        first=$(echo "$h" | sed -n '2p' | sed 's/^[ \t]*//' | tr -d '\t' | cut -c1-95)
    else
        first="(help call timed out)"
    fi
    t=$(classify "$c" "$first")
    [ "$t" = A ] && echo "$c" >> "$TIERA"
    printf '%s\t%s\t%s\n' "$c" "$t" "$first"
done < "$LIST"

# --- optional: execute every Tier A command (reads only) --------------------
if [ "$SWEEP" = "1" ]; then
    echo "#"
    echo "# --- Tier A sweep on $IFACE (reads only) ---"
    echo "# state before: clients=$(wl -i "$IFACE" assoclist 2>/dev/null | wc -l) isup=$(wl -i "$IFACE" isup 2>&1)"
    while read -r c; do
        [ -z "$c" ] && continue
        if run_bounded "$TMP" -i "$IFACE" "$c"; then
            o=$(head -c 120 "$TMP" | tr '\n' ' ')
        else
            o="(TIMED OUT)"
        fi
        printf '# %s\t%s\n' "$c" "$o"
    done < "$TIERA"
    echo "# state after:  clients=$(wl -i "$IFACE" assoclist 2>/dev/null | wc -l) isup=$(wl -i "$IFACE" isup 2>&1)"
fi

rm -f "$LIST" "$TMP" "$TIERA"
