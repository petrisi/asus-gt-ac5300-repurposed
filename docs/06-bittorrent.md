# Transmission

The box makes a decent low-power seedbox: four cores, gigabit WAN, and it is
already powered on anyway.

Distribute things you have the right to distribute. Linux images are the
obvious case and the one this was built for.

## Install

    unset LD_LIBRARY_PATH LD_PRELOAD
    opkg install transmission-daemon transmission-remote-web

## Lock down the RPC before starting it

In `/opt/etc/transmission/settings.json`:

    "rpc-enabled": true,
    "rpc-bind-address": "127.0.0.1",
    "rpc-whitelist": "127.0.0.1",
    "rpc-whitelist-enabled": true,
    "rpc-authentication-required": true,
    "peer-port": 51413,
    "download-dir": "/tmp/mnt/ROUTERDATA/torrents"

Bound to loopback, whitelisted, and password protected. Set a username and
password too; the daemon rewrites the password as a salted hash on first run,
which is expected and not a problem.

## Reaching the web UI

Do not open 9091 to the network. Tunnel it:

    ssh -L 9091:127.0.0.1:9091 router

Then browse to `http://127.0.0.1:9091/`. The RPC never leaves the box and
access is gated by your SSH key.

## Peer port

The peer port does need to be reachable, on both address families if you run
dual-stack:

    iptables  -I INPUT 1 -i eth0 -p tcp --dport 51413 -j ACCEPT
    iptables  -I INPUT 1 -i eth0 -p udp --dport 51413 -j ACCEPT
    ip6tables -I INPUT 1 -i eth0 -p tcp --dport 51413 -j ACCEPT
    ip6tables -I INPUT 1 -i eth0 -p udp --dport 51413 -j ACCEPT

UDP matters — µTP and DHT both use it.

`ip6tables` is a **separate table**. A rule in `iptables` has no effect on IPv6
whatsoever, so a dual-stack seed with only v4 rules quietly serves no v6 peers
at all. Check the rule counters if the v6 peer count is suspiciously zero.

Insert these above any `RELATED,ESTABLISHED` rule if you want their byte
counters to see every packet of those flows rather than only the first.

## Starting it reliably

Launch the daemon directly rather than through
`/opt/etc/init.d/S88transmission`. `rc.func` discards stderr, so a failure to
start is completely invisible — and on this platform it *will* fail, because of
the `LD_LIBRARY_PATH` problem in `04-usb-and-entware.md`.

`ensure_transmission()` in `scripts/portal/start.sh` handles it: unsets the
environment, refuses to start unless the USB volume is genuinely mounted, and
takes a lock so a slow start cannot be launched twice.

That last part is not theoretical. An earlier version waited three seconds,
decided the start had failed, and let the next supervision pass launch a second
instance. The two fought over the config lock and both died — every 30 seconds,
indefinitely. If a daemon can take 20 seconds to appear on slow storage, your
supervisor has to know that.

**Never let `download-dir` resolve into tmpfs.** If the USB volume is missing
and the path falls back into `/tmp`, Transmission downloads into RAM, appears
to work, and eventually takes the router down. Hence the mount check before
every start.

## Accounting

Transmission's lifetime totals live in `/opt/etc/transmission/stats.json`,
readable without the RPC password:

    "uploaded-bytes": ...,
    "downloaded-bytes": ...

That file is only rewritten every few minutes, so it is exact for totals and
lumpy for rates. If you want a smooth throughput graph, `07-rrd-history.md`
covers the alternative and the significant caveats that come with it.
