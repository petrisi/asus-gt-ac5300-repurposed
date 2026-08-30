# The `wl` command surface

`wl` is the only interface to the radios on this platform, and it documents far
less than it implements.

    wl -h            usage plus roughly 180 command descriptions
    wl cmds          a much longer list, about 650 entries
    wl -h <cmd>      per-command help — works for the undocumented ones too

`reference/wl-commands.tsv` in this repository is the full inventory for
firmware `3.0.0.4.386_51582`: 638 commands, each with a safety tier and the
first line of its built-in help. Regenerate it for your own firmware with
`scripts/wl-inventory.sh`.

## The convention that makes this tractable

Broadcom's iovars are get/set pairs:

    wl <cmd>            reads
    wl <cmd> <value>    writes

So most of the surface is safe to *read* and the risk lives almost entirely in
the argument form. That is what the tiers capture — not "is this command
dangerous" but **"is a bare call safe?"**

| tier | | count | share |
|---|---|---|---|
| **A** | bare call reads — safe to enumerate | 478 | 75% |
| **B** | bare call performs an **action** — exclude from sweeps | 72 | 11% |
| **C** | transmits, or needs arguments to do anything | 42 | 7% |
| **D** | persistent / regulatory / calibration — **do not touch** | 46 | 7% |

## Tier B — commands that act on a bare call

These break the get/set convention. `wl down` does not report the down state,
it takes the radio down. Any automated sweep must exclude them by name:

    ampdu_clear_dump anqpo_start_query anqpo_stop_query arp_hostip_clear
    arp_stats_clear arp_table_clear authorize clear_radar_status
    deauthenticate deauthorize dfs_ap_move disassoc down drift_stats_reset
    escan escan_event_check escanabort interface_create interface_remove join
    nar_clear_dump nd_hostip_clear nd_status_clear ns_hostip_clear ota_loadtest
    ota_stream ota_teststop out p2po_find p2po_listen p2po_stop pfnclear
    pkt_filter_clear_stats pkteng_start pkteng_stop proxd_find proxd_stop
    reboot reset_cnts reset_d11cnts restart scan scanabort scancache_clear
    seq_start seq_stop tkip_countermeasures toe_stats_clear
    trf_mgmt_filters_clear trf_mgmt_stats_clear up vasip_counters_clear
    wme_clear_counters

Most are counter resets — annoying rather than harmful. `down`, `out`,
`reboot`, `restart`, `deauthenticate`, `disassoc` and `interface_remove` are
the ones that will interrupt service.

## Tier D — do not touch

Writes here are persistent, and several can leave the radio permanently
misconfigured. There is no undo.

    autocountry_default bmac_reboot calload cis_source cisconvert cisdump
    cisupdate ciswrite clm_data_ver clmload country country_ie_override diag
    dongleset manfinfo nvram_get nvram_source olpc_anchoridx otpdump otpraw
    otpstat otpw perm_etheraddr phy_afeoverride phy_read_estpwrlut
    phy_setrptbl phy_test_idletssi phy_test_tssi phy_test_tssi_offs phy_txiqcc
    phy_txlocc phy_vcore phytable radioreg regulatory revinfo rpcalvars
    sar_limit shmem shmemx srclear srwrite txcal_gainsweep
    txcal_gainsweep_meas txcal_pwr_tssi_tbl ucantdiv

`ciswrite`, `srwrite`, `srclear` and `otpw` write the CIS, SROM and OTP — the
radio's identity and calibration data. `txcal_*` and the `phy_*` calibration
entries rewrite the transmit calibration tables. `regulatory`, `country` and
`clmload` change what the radio is legally permitted to transmit.

Reading most of these is harmless, but they are grouped as do-not-touch because
the read and write forms differ by one argument.

## Classify on the help text, not the name

A name-only pass put these in the "safe" bucket:

    srclear   "Clears first 'len' bytes of the srom"
    clmload   "Download CLM data"
    shmemx    "Get/Set a shared memory location of PSMX"
    diag      "diag testindex(1-interrupt, 2-loopback, 3-memory)"

Nothing in those names suggests danger. `scripts/wl-inventory.sh` matches
against the help text as well, which is why it catches them.

## What `wl` gives you that the GUI does not

The wireless GUI pages expose **180 `wl_*` nvram variables** — SSID, security,
channel, bandwidth, DTIM, beacon interval, frameburst, AMPDU, WMM, beamforming,
MU-MIMO, MAC filtering, WDS, RADIUS, transmit power, the roaming RSSI threshold.

Every one of them is a **setting**. Not one **reads** anything.

There is no per-client rate, no airtime figure, no noise floor, no retry count,
no driver counter anywhere in the GUI. That entire dimension is `wl`-only, and
it is the more useful half when something is actually wrong.

### The instrumentation gap

| command | what it gives you |
|---|---|
| `bs_data` | per-station airtime, retry rate, and PHY-rate versus actual throughput |
| `chanim_stats` | per-channel noise floor, glitch count, airtime busy/idle |
| `sta_info <mac>` | **per-antenna** RSSI (four values), cumulative packet and byte counters |
| `bss_peer_info` | RSSI, TX/RX rate, rateset and idle time for every peer, in one call |
| `counters` | the complete driver statistics block |
| `nrate` | current MCS, spatial streams and bandwidth; can force a fixed rate |
| `txbf_rateset` | beamforming enablement **per MCS** — the GUI offers only on/off |
| `scb_timeout` | station inactivity timeout (60 s by default) |
| `chanim_mode` | interference detect/avoid mode |
| `list_ie` / `add_ie` | inspect and inject vendor IEs in your own beacons |

`bs_data` is the standout. It reports what share of the radio's airtime each
client consumed and what fraction of its frames needed retransmitting — the
single most diagnostic view of a wireless problem, and completely absent from
every ASUS screen. A slow client at the edge of range can consume airtime out of
all proportion to the data it moves, and nothing in the GUI would ever show you.

**`bs_data` resets its counters when read.** Use `-noreset`. The band-steering
daemon reads the same counters (`bsd_retrieve_bs_data` appears in its symbols),
so polling without it silently corrupts steering decisions — the daemon sees
near-zero airtime for every station because you consumed the reading. With
`-noreset` the values accumulate over a window of unknown length: the
percentages stay meaningful, the absolute rates are indicative.

### More SSIDs than the GUI allows

    bssmax              8      BSSes the radio actually supports
    GUI guest networks  3

So four more SSIDs per radio than the interface will create, via
`interface_create`. Real, but you own the consequences: ASUS's configuration
layer knows nothing about them, so there is no nvram persistence, no GUI
representation, and you must recreate them at every boot from your own script.

### What is *not* a gap

The Professional page is richer than it is given credit for. `frameburst`,
`ampdu_mpdu`, `amsdu`, `wme`, `txbf`, `mumimo`, `dtim`, beacon interval,
`rts`/`frag`, `macmode`, WDS, transmit power, country code, 802.11h, DFS and
airtime fairness are all there. Setting those through `wl` gains nothing and
loses persistence across reboot.

### The pattern worth adopting

**Configure in the GUI, observe with `wl`.** GUI settings persist and survive
reboots; `wl` settings do not. But the GUI is blind, and every piece of
instrumentation on this platform lives behind `wl`.

## Three hazards when sweeping

**A full sweep can wedge the radio firmware.** Running the complete Tier A set
against one radio segfaulted three `wl` processes and left the scan engine
returning `Scan timeout!` indefinitely, with `acsd` pinning a core at 100%. It
survived every soft remedy — `scanabort`, `restart_acsd`, `restart_wireless`,
`wl down`/`up` — and cleared only on a reboot. Service was never interrupted:
all radios kept beaconing and clients stayed associated. Details in
`99-gotchas.md`.


**`wl -h` is not purely textual.** At least one command — observed with
`roam_channels_in_cache` — blocked in `__skb_recv_datagram` for 540 seconds and
stalled the harvest. It did not reproduce once stdin was redirected, so the
cause is not settled, but every call needs a timeout regardless.

**`wl` inherits stdin.** Inside `while read -r c; do wl ... ; done < list`, `wl`
consumes the list. A 650-command sweep silently processed 188 entries, reached
the end of the alphabet, and stopped — with no error. Redirect every
invocation: `wl ... < /dev/null`.

Both are handled in `scripts/wl-inventory.sh`.

## About a third of commands are not implemented

Sampling 42 Tier A commands on an idle radio:

    returned data : 24        hung    : 0
    Unsupported   : 14        errored : 0
    empty         :  4

    radio state before and after: identical

That "identical" holds for **this 42-command sample**. It does not generalise: a
later pass over the full Tier A set wedged the radio's scan engine hard enough
to need a reboot. See `99-gotchas.md` before running a bulk sweep.

The command table is generic across Broadcom's product range; this firmware
implements a subset. `sar_limit` and `rrm_nbr_list` both exist, carry help, and
return `wl: Unsupported`. **Presence in the list is not evidence of support** —
which is the same lesson as `99-gotchas.md` in a different costume.

## Commands worth knowing about

| | |
|---|---|
| `bss_peer_info` | per-client RSSI, TX/RX rate, rateset and age in one call — richer than `assoclist` |
| `chanim_stats` | per-channel noise, glitch count, airtime idle — the basis for judging a radio's RF environment |
| `cap` | what the firmware actually supports; check here before chasing a feature |
| `sta_info <mac>` | per-antenna RSSI, packet and byte counters for one client |
| `curppr` | current power/rate table for the operating channel |
| `wnm_bsstrans_req` | send an 802.11v transition request by hand (Tier C — it transmits) |
| `rrm_bcn_req` | ask a client to perform an 802.11k beacon measurement (Tier C) |

## The Tier A catalogue

`reference/wl-tier-a-catalog.md` documents all 476 Tier A commands, grouped into
23 functional families — identity and capability, associated stations, channel and
DFS, transmit power, rates and aggregation, roaming and 802.11k/v, offload, PHY
internals and the rest.

Each entry carries the command's own help text, its usage form, and what it
actually returned on this hardware, so you can see at a glance which commands are
live and which report `Unsupported`. Every family opens with a note on what it is
for and which members are worth knowing.

## The Tier B/C/D catalogue

`reference/wl-tier-bcd-catalog.md` covers the other 160 commands — the ones that
cannot be called blindly. **None of them were executed**; only `wl -h` was called.
Tier A is documented by observation, B/C/D by reading, and that distinction is the
point of the tiers.

Each entry states what happens if you do run it, subgrouped by consequence:
service-affecting versus counter resets in Tier B, transmitting versus
argument-requiring in Tier C, and in Tier D by what gets written — non-volatile
storage, calibration, regulatory limits, or raw hardware.

## Regenerating

    ./wl-inventory.sh > wl-commands.tsv          # inventory only, changes nothing
    ./wl-inventory.sh --sweep-a > sweep.txt      # also runs every Tier A command

The inventory pass changes nothing. **The sweep does not deserve the same
confidence.** Every command it runs is a bare read, and on one occasion that
was still enough to segfault three `wl` processes and wedge the radio's scan
engine until a reboot — see `99-gotchas.md`. Run it on a radio with no clients,
and only when you can afford to reboot the box.
