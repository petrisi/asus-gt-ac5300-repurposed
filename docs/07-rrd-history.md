# Long-term history with rrdtool

The dashboard shows a rolling few minutes held in the browser. This adds
persistent history — 24 hours at one-minute detail down to a year at six-hour
detail, in about 8 MB that never grows.

**This layer is optional and isolated.** It lives on the USB stick, and if the
stick is absent every part of it exits silently and the live dashboard is
unaffected. Keep it that way if you extend it.

## Pieces

    rrd_feeder.sh    samples once a minute into the RRDs
    rrd_ping.sh      latency probe, detached (see below)
    rrd_export.sh    RRD -> JSON for the browser, every 5 minutes

`start.sh` calls the feeder and exporter from its supervision loop, gated on
stamp files so a slow run is never launched twice.

## Why round-robin

Fixed size forever. Older data is consolidated rather than accumulated, so a
year costs the same as the first day. On a device with finite storage and no
log rotation worth the name, that property matters more than the resolution
you give up.

## Schema decisions worth stealing

**Use `DERIVE`, not `COUNTER`, for byte counters.** `COUNTER` treats any
decrease as a hardware counter wrap and synthesises an enormous rate. These
counters reset to zero on reboot, which `COUNTER` renders as a spike of about
10¹⁰ bytes/second. `DERIVE` with `min=0` records the decrease as UNKNOWN, which
is the truth.

**Set the heartbeat to twice the step.** With a 60-second step and a 120-second
heartbeat, one missed sample records UNKNOWN instead of carrying the previous
value forward. Gaps then appear as breaks in the line rather than as a flat
segment indistinguishable from a genuinely idle router.

**Age-check your input before trusting it.** A wedged collector leaves a
perfectly well-formed `status.json` that is simply old. The feeder checks its
mtime and writes UNKNOWN rather than re-recording stale values as current.

**Never do arithmetic on counters in the shell.** Pass the raw value to
`rrdtool` as a string and let it do the maths in C. See the 2³¹ truncation
entry in `99-gotchas.md`.

**Give negative-valued gauges a negative floor.** Wireless noise is around
−90 dBm; a `GAUGE` declared `0:U` discards every sample silently.

## Why the latency probe is a separate process

Three ICMP probes at up to six seconds each is roughly 18 seconds, and a
black-holed target is unbounded in practice even with `-W`. Blocking a
60-second sampling loop on that is unacceptable.

`rrd_ping.sh` runs detached and self-locking, writing its result to a file that
the feeder reads on its *next* pass. Results are up to a minute old, which is
irrelevant for a trend line, and the feeder completes in well under a second.

## Exporting to the browser

rrdtool 1.2 (what Entware ships here) predates JSON export, so `rrd_export.sh`
converts `rrdtool fetch` output to JSON with awk and writes static files that
lighttpd serves. Two non-obvious requirements:

**Place samples on a fixed time grid, indexed by timestamp.** `rrdtool fetch`
returns rows only from where each database actually starts, so a database
created ten minutes ago yields a handful of rows for a seven-day request while
an older one yields the full set. Appending in order produces series of
different lengths drawn against one shared x-axis — every young series
stretched across the whole chart, silently misaligned.

**Never accumulate the payload in a shell variable.** busybox caps arguments to
its builtins at roughly 128 KB, and `[ -n "$big" ]` then fails with *Argument
list too long* and returns non-zero — which reads exactly like "empty". The
export silently produced empty series for some windows and not others. Stream
fragments through a file and test with `[ -s file ]`, which is a size test
rather than an argument test.

**Delete the exported files when the source disappears.** If the stick is
pulled, stale JSON left in tmpfs renders as though it were current. Absent data
must look absent.
