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

## Two hazards when sweeping

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

The sweep is reads only and records radio state either side so you can confirm
nothing moved. Run it on a radio with no clients.
