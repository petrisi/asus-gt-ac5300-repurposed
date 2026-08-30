#!/bin/sh
#
# RRD -> JSON exporter for the dashboard's History section.
#
# rrdtool 1.2.30 predates --json (xport emits XML only), and no CGI module is
# loaded in lighttpd, so history is exported to static JSON on tmpfs on a timer
# and served through the existing /data/ alias. The browser renders it with the
# same chart code as the live view, which keeps one visual language rather than
# bolting on server-rendered PNGs.
#
# STALENESS: if the RRDs are gone (stick pulled), the exported files are DELETED
# rather than left behind. A leftover hist_*.json would render as though it were
# current -- the precise failure mode that hid a 3.4-day collector stall and a
# frozen dashboard once already. Absent data must look absent.

RUN=/tmp/portal
USB_LABEL=ROUTERDATA
RRD_DIR="/tmp/mnt/$USB_LABEL/rrd"
SYS="$RRD_DIR/sys.rrd"
NET="$RRD_DIR/net.rrd"
RRDTOOL=/opt/bin/rrdtool

# Every file added after the first release is optional here: each appears only
# once its feeder has run, and the export must stay valid in the meantime.
# Listing them rather than globbing keeps the JSON key order stable.
EXTRA="$RRD_DIR/bt.rrd $RRD_DIR/health.rrd $RRD_DIR/fw.rrd $RRD_DIR/if.rrd $RRD_DIR/wifi.rrd $RRD_DIR/ping.rrd"

unset LD_LIBRARY_PATH LD_PRELOAD        # mandatory for Entware binaries

if [ ! -f "$SYS" ] || [ ! -f "$NET" ] || [ ! -x "$RRDTOOL" ]; then
    rm -f "$RUN"/hist_*.json 2>/dev/null
    exit 0
fi

NOW=$(date +%s)

# fetch_json <rrdfile> <cf> <resolution> <span> <downsample-factor>
#
# Emits `"name":[v,...]` fragments. rrdtool prints one header line of DS names,
# a blank line, then "<epoch>: v1 v2 ...". Unknown samples are emitted as JSON
# null, never 0 -- a gap is not a zero, and charting it as one would invent data.
fetch_json() {
    _f=$1; _cf=$2; _res=$3; _span=$4; _ds=${5:-1}
    _s=$(( NOW - _span ))
    $RRDTOOL fetch "$_f" "$_cf" -r "$_res" -s "$_s" -e "$NOW" 2>/dev/null | awk -v ds="$_ds" -v start="$_s" -v step="$_res" -v span="$_span" '
    NR == 1 { for (i = 1; i <= NF; i++) nm[i] = $i; nds = NF; next }
    /^[0-9]+:/ {
        # Place each row onto a FIXED time grid rather than appending in order.
        #
        # rrdtool only returns rows from the point the database actually starts,
        # so a file created ten minutes ago yields a handful of rows for a
        # 7-day request while an older file yields the full set. Appending would
        # produce series of DIFFERENT LENGTHS that the browser then draws against
        # one shared x-axis -- every young series stretched across the whole
        # chart and silently misaligned with the rest. Indexing by timestamp
        # makes every series cover the same span with holes where data is absent.
        t = $1; sub(/:/, "", t)
        idx = int((t - start) / step)
        if (idx < 0) next
        for (i = 1; i <= nds; i++) {
            v = $(i + 1)
            if (v != "nan" && v != "-nan" && v != "NaN" && v != "") g[i "," idx] = v + 0
        }
    }
    END {
        if (nds == 0) exit                  # no header: nothing to say
        n = int(span / step); if (n < 1) n = 1
        out = ""
        for (i = 1; i <= nds; i++) {
            if (out != "") out = out ","
            out = out "\"" nm[i] "\":["
            row = ""
            # downsample by averaging ds grid cells, ignoring gaps
            for (b = 0; b * ds < n; b++) {
                sum = 0; cnt = 0
                for (k = b * ds; k < (b + 1) * ds && k < n; k++) {
                    key = i "," k
                    if (key in g) { sum += g[key]; cnt++ }
                }
                if (row != "") row = row ","
                row = row (cnt ? sprintf("%.4g", sum / cnt) : "null")
            }
            out = out row "]"
        }
        printf "%s", out
    }'
}

# window <name> <resolution> <span> <downsample>
window() {
    _n=$1; _r=$2; _sp=$3; _d=$4
    _tmp="$RUN/.hist_$_n.tmp"
    _frag="$RUN/.hist_frag"
    {
        printf '{"window":"%s","generated":%s,"step":%s,"span":%s,' \
               "$_n" "$NOW" "$(( _r * _d ))" "$_sp"
        printf '"series":{'

        # THE PAYLOAD IS NEVER HELD IN A SHELL VARIABLE.
        #
        # This originally accumulated fragments into $_parts and printf'd it.
        # busybox caps arguments to its builtins at ~128 KB, and `[ -n "$_parts" ]`
        # started failing with "Argument list too long" once the total passed it --
        # emitting an EMPTY series block while exiting 0, so the export looked
        # like it had simply found no data. The day window (120 KB) slipped under
        # the limit while week (139 KB) did not, which is why only some windows
        # broke. Values are longer than the "null" placeholders they replace, so
        # every window would have crossed it as history filled in.
        #
        # Each fragment now goes to a file, is tested with [ -s ] (a size test,
        # not an argument test), and is streamed with cat. Nothing scales with
        # payload size.
        _first=1
        for _f in "$NET" "$SYS" $EXTRA; do
            [ -f "$_f" ] || continue
            fetch_json "$_f" AVERAGE "$_r" "$_sp" "$_d" > "$_frag" 2>/dev/null
            [ -s "$_frag" ] || continue
            [ "$_first" = 1 ] || printf ','
            cat "$_frag"
            _first=0
        done

        printf '},"peaks":{'
        # MAX consolidation: on a seeding box the burst is usually the point, and
        # a 6-hour average hides it completely.
        fetch_json "$NET" MAX "$_r" "$_sp" "$_d"
        printf '}}'
    } > "$_tmp" 2>/dev/null
    rm -f "$_frag" 2>/dev/null
    # publish atomically so the browser never reads a half-written file
    mv "$_tmp" "$RUN/hist_$_n.json" 2>/dev/null
}

window day   300   86400    1     # 5-min buckets over 24h   -> ~288 points
window week  1800  604800   1     # 30-min over 7d           -> ~336
window month 1800  2592000  4     # 30-min averaged x4 (2h)  -> ~360
window year  21600 31536000 4     # 6-hour averaged x4 (24h) -> ~365

# ------------------------------------------------------------- totals ------
#
# Transfer totals = sum(rate * bucket_seconds) over the window, taken from the
# finest RRA that still covers it. Gaps are skipped rather than treated as zero,
# so a total can UNDER-report after an outage; "coverage" reports what fraction
# of buckets actually held data so the number can be judged rather than trusted
# blindly.
totals() {
    _span=$1; _res=$2; _label=$3
    $RRDTOOL fetch "$NET" AVERAGE -r "$_res" -s "$(( NOW - _span ))" -e "$NOW" 2>/dev/null | awk -v res="$_res" -v lb="$_label" '
    NR == 1 { for (i = 1; i <= NF; i++) nm[i] = $i; nds = NF; next }
    /^[0-9]+:/ {
        rows++
        for (i = 1; i <= nds; i++) {
            v = $(i + 1)
            if (v != "nan" && v != "-nan" && v != "NaN" && v != "") { tot[i] += v * res; got[i]++ }
        }
    }
    END {
        printf "\"%s\":{", lb
        for (i = 1; i <= nds; i++) {
            if (i > 1) printf ","
            printf "\"%s\":%.0f", nm[i], tot[i]
        }
        printf ",\"coverage\":%.3f}", (rows ? got[1] / rows : 0)
    }'
}

_t="$RUN/.hist_totals.tmp"
{
    printf '{"generated":%s,' "$NOW"
    printf '%s,' "$(totals 86400   60   day)"
    printf '%s,' "$(totals 604800  300  week)"
    printf '%s'  "$(totals 2592000 1800 month)"
    printf '}'
} > "$_t" 2>/dev/null
mv "$_t" "$RUN/hist_totals.json" 2>/dev/null

exit 0
