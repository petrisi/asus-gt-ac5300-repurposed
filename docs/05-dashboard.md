# The status dashboard

A single-page status portal: CPU and per-core load, temperature, memory,
connection counts, WAN/LAN throughput graphs, firewall drops, wireless radio
detail, DHCP leases, storage.

`scripts/portal/www/index.html` is the whole front end — one file, no
frameworks, no external requests.

## The architecture, and why it is worth copying

Three processes, deliberately decoupled:

    portal_collector.sh   samples every 2s  ->  /tmp/portal/status.json
    lighttpd              serves the page and that JSON
    start.sh              supervises both, re-applies firewall rules

**The dashboard has no dependency on the USB stick or on Entware.** It uses the
firmware's own `lighttpd` (there is one, at `/usr/sbin/lighttpd`) and writes to
tmpfs. Pull the stick out and the dashboard keeps working.

That constraint is worth keeping if you extend it. The optional history layer
in `07-rrd-history.md` is bolted on as a separate, failure-isolated stage
precisely so that it cannot take the live view down with it.

Everything is in tmpfs, so the sampling never touches flash.

## Install

    mkdir -p /jffs/portal/www
    cp portal/*.sh /jffs/portal/
    cp portal/www/index.html /jffs/portal/www/
    chmod 755 /jffs/portal/*.sh

`killsvc.sh` starts it 55 seconds after boot — late enough that `rc` has
finished building its firewall chains, so the rules added by `start.sh` are not
immediately overwritten.

## Protecting it

The generated lighttpd config uses **digest** auth rather than basic. This is
plain HTTP, and basic auth would put the password on the wire with every single
request.

Create the credentials file with `htdigest` if you have it, or any tool that
produces the standard `user:realm:md5hash` line. The realm must match the one
in the generated config — a digest hash is computed over the realm, so a
mismatch means every login silently fails.

The file lives outside the document root on purpose. Inside it, it would be
downloadable, which would hand over the hash.

`start.sh` also maintains iptables rules for the dashboard port — accepted on
one interface, dropped on the other. Edit `ensure_fw()` to match your intent.

## Serving it on both address families

If you run dual-stack, note that lighttpd binds IPv4 only by default. The
generated config sets:

    server.use-ipv6      = "enable"
    server.set-v6only    = "disable"

which produces a single dual-stack socket. `set-v6only` must stay disabled or
the page disappears over IPv4 — which is the path that still works when a
DNS AAAA record has gone stale.

And remember `ip6tables` is a separate table. Opening the port in `iptables`
does nothing for IPv6.

## Per-station airtime

The wireless card includes a per-station table from `wl bs_data` — airtime
consumed, retry rate, and negotiated PHY rate against actual throughput. None of
that exists anywhere in the ASUS GUI, and it is the fastest way to spot a
marginal client that is consuming airtime out of proportion to the data it
moves.

**Read it with `-noreset`.** A bare `bs_data` resets the counters, and the
band-steering daemon reads the same ones — polling without it silently corrupts
steering decisions, because the daemon then sees near-zero airtime for every
station. The collector does this correctly; if you adapt it, keep the flag.

## Two things learned the hard way

**Judge liveness by data freshness, not process existence.** A hung collector
stays in the process table indefinitely. The supervisor checks the age of
`status.json` and restarts on staleness; the UI reports "data stale" rather
than showing a frozen chart that looks live. An earlier version checked "is the
process running" and sat happily for over three days with a wedged collector.

**Bound everything that reads `/proc` or calls `wl`.** Both can block forever on
this platform, and one of them will eventually. The collector wraps them in a
timeout helper. See `99-gotchas.md` — that section exists because of two
separate multi-day outages.
