# Platform traps

Every entry here cost real debugging time. They share a shape: **the failure is
silent and the output looks plausible.** Nothing here throws an error you would
notice.

Read this before you debug anything.

---

## Shell arithmetic silently truncates at 2³¹

busybox `ash` on this 32-bit userland:

    # rx=18821963980
    # echo $((rx + 1))
    1

No error, no warning. Interface byte counters exceed 2³¹ within days of uptime,
so anything computing throughput in the shell reports zero on a busy link.

**Do the arithmetic in `awk`**, which uses doubles. If you are feeding a tool
that can do the maths itself, pass the raw value through as a string and never
touch it.

## `LD_LIBRARY_PATH` breaks every Entware binary at boot

`rc` exports it pointing at the firmware's libraries. Entware binaries have a
`DT_RUNPATH`, but an inherited `LD_LIBRARY_PATH` takes precedence, so they load
the wrong libc and die. `rc.func` discards stderr, so there is no message at
all.

    ( unset LD_LIBRARY_PATH LD_PRELOAD ; /opt/bin/thing )

Interactive SSH sessions do not inherit it — which is why the thing works
perfectly by hand and fails only at boot.

## `uniq` does not exist

Not as a busybox applet, not standalone. Every `sort | uniq -c` pipeline
silently produces **nothing**, and an empty result reads as "no matches".

    # count occurrences without uniq
    awk '{c[$0]++} END {for (k in c) print c[k], k}' | sort -rn

`sort` is present. Check before assuming anything else is: `command -v` is also
unreliable here — it reports `usleep` as missing when `usleep` works fine.

## busybox caps builtin arguments at about 128 KB

    [ -n "$big_string" ]
    sh: [: Argument list too long

The test returns non-zero, which is indistinguishable from "the string is
empty" unless you are checking stderr. A JSON exporter here silently emitted
empty output for larger windows while working fine for smaller ones.

Stream large data through files and test with `[ -s file ]`, which is a size
test rather than an argument test.

## busybox `awk` treats `split()`'s separator as a regex

    split(s, arr, "},{")
    awk: bad regex '},{': Unmatched \{

`{` is the interval metacharacter. This aborts the whole program — and if you
redirected stderr, your parser just stops producing output halfway through with
no indication why.

    gsub(/\},\{/, "@@", s); n = split(s, arr, "@@")

## `dmesg` is frozen

`klogd` reads `/proc/kmsg`, which **consumes** messages from the ring buffer.
New kernel messages only ever reach syslog. `dmesg` output is a snapshot from
early boot and never changes.

Anything that measures kernel-log deltas via `dmesg` is structurally incapable
of detecting anything. Measure against `/tmp/syslog.log`.

## Reading `/proc/fcache/nflist` can stream forever

Normally it returns about a dozen lines instantly. Under load — thousands of
short-lived flows — the iterator does not terminate. One captured read had
produced **4.2 million lines** before being killed.

The knock-on effect is worse than the hang. A supervisor that restarts a
stalled reader without reaping its children turns one stuck process into one
per cycle; eighteen of them took load to 19.5 and left 33 MB of RAM free.

Bound the read, and use a **single child process** rather than a pipeline —
`cmd | grep -c` gives you two PIDs and `$!` is only the last one, so the first
survives your timeout kill.

## `wl` ioctls hang during DFS events

Any `wl` call can block indefinitely while the driver handles radar detection
on a DFS channel. A collector polling wireless stats will eventually wedge and
stay wedged. One did, for 3.4 days.

Wrap every `wl` call in a timeout. And judge collector health by **output
freshness**, not process existence — a hung process is still very much in the
process table.

## Matching process command lines kills your own SSH session

    for p in $(ls /proc | grep -E '^[0-9]+$'); do
      case "$(tr '\0' ' ' < /proc/$p/cmdline)" in
        *fcache*) kill -9 $p ;;
      esac
    done

The shell running that loop has `fcache` in its own command line. It matches
itself and dies. This happened twice here, with two different patterns.

Match on `/proc/PID/comm` (the executable name, truncated to 15 characters),
skip `$$` explicitly, and pipe the script to `sh -s` so its own cmdline is just
`sh -s`.

## `blkid` logs a kernel error on every call

    ubi0 error: ubi_open_volume: cannot open device 0, volume 0, error -16

`blkid` opens every block device it can find, including the UBI volume holding
the read-only rootfs. The open is refused with `EBUSY` and the kernel logs it.
Harmless in itself — but polling `blkid` once every 30 seconds produced about
2,880 lines a day, which was **76% of syslog**, burying everything else and
rotating real history away early.

Only probe when the volume is actually missing.

## dnsmasq is built with `HAVE_BROKEN_RTC`

The first field of `/var/lib/misc/dnsmasq.leases` is **seconds remaining**, not
an absolute expiry time. Parse it as an epoch and every lease appears to have
expired in 1970.

## Firewall rules must go above the trailing DROP

    iptables -A INPUT ...    # lands below the chain's final DROP; never matches
    iptables -I INPUT 1 ...  # correct

An appended rule looks present in `iptables -L` and does nothing, because the
packet was already dropped. Check the packet counters, not just the listing.

## `ip6tables` is a completely separate table

Nothing in `iptables` affects IPv6. Every rule needs writing twice. The
characteristic symptom is a service that works over one address family and
hangs over the other — and because the default is `DROP` rather than `REJECT`,
it hangs rather than failing cleanly.

## The GUI shows settings that do nothing

A recurring pattern: ASUS ships the presentation layer of a feature — the nvram
variable, sometimes a whole GUI page — without the code that consumes it. The
value saves, persists across reboots, and is never read.

Confirmed inert on this firmware: `script_usbmount`, `/jffs/scripts/`,
`/etc/init.d/`, and the VLAN `vlan_rulelist`. Verify behaviour before trusting
a setting, no matter how official it looks.
