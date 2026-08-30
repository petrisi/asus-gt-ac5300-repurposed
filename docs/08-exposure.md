# If it faces the internet

A repurposed router often ends up on a public address — as a seedbox, a jump
host, or something in a DMZ. This firmware will never be patched again, so
treat the box as untrusted infrastructure and plan accordingly.

## Close the admin interface first

The single most important step. ASUS offers "web access from WAN", and on a
public address that exposes an unpatched 2022 web stack to the entire internet.

    nvram get misc_http_x        # must be 0
    nvram set misc_http_x=0
    nvram commit

Verify what is actually listening, and on which addresses:

    netstat -tuln

You want the GUI bound to the LAN address and loopback only. Reach it through
an SSH tunnel instead:

    ssh -L 8443:127.0.0.1:8443 router

## SSH will be scanned continuously

Within hours of appearing on a public address you will see a steady stream of
rejected logins for users that do not exist. That is background noise, not a
targeted attack, but it is a good argument for:

- **key-only authentication** — `nvram set sshd_pass=0`
- **moving off port 22**, which removes essentially all of it
- restricting the source address if your situation allows it

`dropbear` logs these without the source address on this build, so you cannot
easily fail2ban them. Moving the port is the effective lever.

## Both firewall tables

    iptables  -L INPUT -n -v
    ip6tables -L INPUT -n -v

These are **independent**. Every rule you care about needs writing twice. A
common and quiet failure is a service reachable over IPv4 and silently dropped
over IPv6 — or, worse, open on IPv6 when you believed you had closed it.

Note that `DROP` produces a silent hang for the client rather than a clean
refusal, which makes it hard to distinguish "blocked" from "broken". Keep that
in mind when diagnosing.

## Rules do not survive on their own

`rc` rebuilds the firewall chains on various events, discarding anything you
added by hand. `ensure_fw()` in `start.sh` reasserts the rules on every
supervision pass, using `iptables -C` to test before inserting so it is
idempotent.

Insert with `-I INPUT 1` rather than `-A`. Appended rules land below the
chain's trailing `DROP` and never match — which looks exactly like the rule not
working, because it is not.

## Devices behind it inherit its trust level

If clients use this box as their gateway and DNS resolver, they are trusting an
unpatched device that faces the internet. That is a design decision worth
making deliberately rather than by accident — it is not an argument against
doing it, just against not noticing.

If you run an SSID on it, consider client isolation:

    nvram get wl0_ap_isolate     # 0 = clients can reach each other

## What to check periodically

    cat /jffs/killsvc.log                     # did the daemons stay dead
    grep -c "nonexistent user" /tmp/syslog.log  # scan volume
    ip6tables -L INPUT -n -v | head           # v6 rules still present
    nvram get misc_http_x                     # still 0

The dashboard's firewall-drop and rejected-login series make the first three
visible over time rather than requiring you to remember to look.
