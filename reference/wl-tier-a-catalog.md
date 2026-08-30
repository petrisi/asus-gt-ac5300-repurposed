# Tier A command catalogue

Every Tier A command — those where a bare `wl <cmd>` is a read — with what it
does, its usage form, and what it actually returned on this hardware.

- **476 commands** documented here
- **327** returned something on this firmware; the rest report `Unsupported`
- Descriptions come from the binary&#39;s own `wl -h <cmd>` text
- The *returns* column is live output from a GT-AC5300 on firmware 3.0.0.4.386_51582,
  captured with the radio idle. Values are illustrative, not normative.

Regenerate with `scripts/wl-inventory.sh`. See `docs/10-wl-commands.md` for the tier model
and the safety rules — in particular, do not run this sweep against Tier B or D.

## Contents

- [Identity, capability and driver state](#identity-capability-and-driver-state) — 14
- [Associated stations and peers](#associated-stations-and-peers) — 14
- [Channel, chanspec and regulatory view](#channel-chanspec-and-regulatory-view) — 10
- [Interference, radar and DFS](#interference-radar-and-dfs) — 23
- [Transmit power](#transmit-power) — 8
- [Rates, MCS and aggregation](#rates-mcs-and-aggregation) — 52
- [MIMO, beamforming and spatial streams](#mimo-beamforming-and-spatial-streams) — 11
- [Scanning and discovery](#scanning-and-discovery) — 27
- [Roaming, 802.11k/v/r and steering](#roaming-80211kvr-and-steering) — 41
- [Security and encryption](#security-and-encryption) — 17
- [QoS, WME and traffic management](#qos-wme-and-traffic-management) — 29
- [Power save and wake-on-wireless](#power-save-and-wakeonwireless) — 20
- [Statistics and counters](#statistics-and-counters) — 12
- [Offload: ARP, ND, TOE, packet filters](#offload-arp-nd-toe-packet-filters) — 25
- [WDS, bridging and virtual interfaces](#wds-bridging-and-virtual-interfaces) — 21
- [P2P, ANQP, Hotspot and TDLS](#p2p-anqp-hotspot-and-tdls) — 27
- [PHY and radio internals](#phy-and-radio-internals) — 40
- [Driver debug, events and logging](#driver-debug-events-and-logging) — 37
- [Information elements](#information-elements) — 4
- [802.11h spectrum management](#80211h-spectrum-management) — 9
- [Board, NVRAM and low-level hardware](#board-nvram-and-lowlevel-hardware) — 20
- [Naming and identity strings](#naming-and-identity-strings) — 3
- [Other](#other) — 12


## Identity, capability and driver state

Start here when working on an unfamiliar unit. `cap` is the single most useful command in the whole set — it lists what the *firmware* supports, which is frequently narrower than what the command table implies. If a feature is missing from `cap`, no amount of configuration will enable it. `ver` identifies the driver and firmware build; `isup` and `bss` tell you whether a radio is running and whether its BSS is up, which is the first thing to check when a radio appears dead.

| command | what it does | returns here |
|---|---|---|
| `ap` | Set AP mode: 0 (STA) or 1 (AP) | `1` |
| `band` | Returns or sets the current band | `b` |
| `bands` | Return the list of available 802.11 bands | `b` |
| `bss` | set/get BSS enabled status: up/down | `up` |
| `cap` | driver capabilities | `ap sta wet toe led wme 802.11d 802.11h rm cqa ccx cac ` |
| `cur_etheraddr` | Get/set the current hw address | `cur_etheraddr xx:xx:xx:xx:xx:xx` |
| `infra` | Set Infrastructure mode: 0 (IBSS) or 1 (Infra BSS) | `1` |
| `isup` | Get driver operational state (0=down, 1=up) | `1` |
| `phylist` | Return the list of available phytypes | `v` |
| `phytype` | Get phy type | `11` |
| `rclass` | Get operation class: | `rclass	Get operation class: chanspec` |
| `status` | Print information about current network association. | `SSID: "MYSSID" Mode: Managed	RSSI: 0 dBm	SNR: 0 dB	noi` |
| `ver` | get version information | `1.363 RC45.18479 wl0: Jul 14 2022 14:05:35 version 10.` |
| `wlc_ver` | returns wlc interface version | **Unsupported** |

## Associated stations and peers

The practical toolkit for "who is connected and how well". `assoclist` gives MAC addresses only; `bss_peer_info` is considerably better, returning RSSI, TX and RX rate, the negotiated rateset and idle time for every peer in one call. `sta_info <mac>` goes further still, with per-antenna RSSI and cumulative packet and byte counters for a single station. Prefer `bss_peer_info` for dashboards and `sta_info` for diagnosing one troublesome client.

| command | what it does | returns here |
|---|---|---|
| `assoc` | Print information about current network association. | `SSID: "MYSSID" Mode: Managed	RSSI: 0 dBm	SNR: 0 dB	noi` |
| `assoc_info` | Returns the assoc req and resp information [STA only] | `Assoc req: len 0x0 Assoc resp: len 0x0` |
| `assoclist` | AP only: Get the list of associated MAC addresses. | _(silent)_ |
| `auth` | set/get 802.11 authentication type. 0 = OpenSystem, 1= SharedKey, 3=Open/Shared | `0` |
| `authe_sta_list` | Get authenticated sta mac address list | _(silent)_ |
| `autho_sta_list` | Get authorized sta mac address list | _(silent)_ |
| `bs_data` | Display per station band steering data<br>`bs_data [options]` | `No stations are currently associated.` |
| `bss_peer_info` | Get BSS peer info of all the peer's in the indivudual interface<br>`wl bss_peer_info [MAC address]` | _(silent)_ |
| `bssmax` | get number of BSSes | `8` |
| `reassoc` | Initiate a (re)association request.<br>`wl reassoc <bssid> [options]` | _needs args_ |
| `scb_timeout` | AP only: inactivity timeout value for authenticated stas | `60` |
| `sta_info` | wl sta_info <xx:xx:xx:xx:xx:xx> | `sta_info wl sta_info <xx:xx:xx:xx:xx:xx> ERROR: no val` |
| `sta_monitor` | wl sta_monitor [enable/disable/counters/reset_cnts] / [<add/del> <xx:xx:xx:xx:xx:xx>] | _(silent)_ |
| `staprio` | Set/Get sta priority<br>`wl staprio <xx:xx:xx:xx:xx:xx> <prio>` | _(silent)_ |

## Channel, chanspec and regulatory view

A *chanspec* is Broadcom's encoding of channel, bandwidth and sideband in one 16-bit value — `0x1007` and `0xe23a` are chanspecs, not channel numbers. `chanspec` reads the current one, `chanspecs` enumerates what is legal in the active regulatory domain. `chan_info` describes a specific channel including whether it is restricted or radar-affected, which is how you tell in advance whether a target channel carries DFS obligations.

| command | what it does | returns here |
|---|---|---|
| `bw_cap` | Get/set the per-band bandwidth.<br>`wl bw_cap <2g/5g> [<cap>]` | _needs args_ |
| `chan_info` | channel info | `Channel 1	B Band Channel 2	B Band Channel 3	B Band Cha` |
| `channel` | Set the channel: | `No scan in progress. current mac channel	6 target chan` |
| `channel_qa` | Get last channel quality measurment | `0` |
| `channel_qa_start` | Start a channel quality measurment | _error_ |
| `dyn_bwsw_params` | Configure the params for dynamic bandswitch | `Version=1 actvcfm=3 noactcfm=6 noactincr=5 psense=500 ` |
| `force_vsdb_chans` | Set/get channels for forced vsdb mode<br>`wl force_vsdb_chans chan1 chan2` | `wl_phy_maxpower: fail to get maxpower` |
| `obss_prot` | Get/set OBSS protection (-1=auto, 0=disable, 1=enable) | `off 0 auto` |
| `obss_scan_params` | set/get Overlapping BSS scan parameters<br>`wl obss_scan a b c d e ...; where` | `20 10 300 200 20 5 25` |
| `rsdb_mode` | Set/Get the RSDB mode. Possible values auto(-1), mimo(0), rsdb(1), 80p80(2) | **Unsupported** |

## Interference, radar and DFS

`chanim_stats` is the workhorse: per-channel noise floor, glitch count, airtime busy and idle percentages. It is the right basis for judging whether a radio's environment is actually clean, and comparing it across radios will often explain a throughput complaint that looks like a client problem. `radar_status` and `dfs_status` report radar detection state on DFS channels. Note that `wl` calls in this family can block during an active DFS event — bound them.

| command | what it does | returns here |
|---|---|---|
| `cca_get_stats` | -c channel: Optional. specify channel. 0 = All channels. Default = current channel<br>`wl cca_stats [-c channel] [-s num seconds][-n]` | _needs args_ |
| `chanim_acs_record` | get the auto channel scan record.<br>`wl acs_record` | `There is no ACS recorded` |
| `chanim_mode` | get/set channel interference measure (chanim) mode<br>`wl chanim_mode <value>` | `CHANIM mode: external (acsd).` |
| `chanim_state` | get channel interference state<br>`wl chanim_state channel` | _needs args_ |
| `chanim_stats` | get chanim stats<br>`wl chanim_stats` | `version: 2 chanspec tx   inbss   obss   nocat   nopkt ` |
| `dfs_channel_forced` | Set <channel>[a,b][n][u,l] | `DFS Preferred Channel:: 0x0 (None)` |
| `dfs_status` | Get dfs status | `state IDLE time elapsed 0ms radar channel cleared by d` |
| `glacialtimer` | Deprecated. Use glacial_timer. | `glacialtimer Deprecated. Use glacial_timer.` |
| `interference` | NON-ACPHY. Get/Set interference mitigation mode. Choices are: | `Mode = 25. Following ACI modes are enabled: bit-mask 1` |
| `interference_override` | NON-ACPHY. Get/Set interference mitigation override. Choices are: | `Interference override disabled.` |
| `intfer_params` | set/get intfer params<br>`wl intfer_params period (in sec) cnt(0~4) txfail_thresh tcptxfail_thresh` | `Intference params: period[1] cnt[3] txfail_thresh[5] t` |
| `itfr_detect` | issue an interference detection request | **Unsupported** |
| `itfr_enab` | get/set STA interference detection mode(STA only) | **Unsupported** |
| `itfr_get_stats` | get interference source information | **Unsupported** |
| `noise` | Get noise (moving average) right after tx in dBm | `-88` |
| `radar` | Enable/Disable radar. One-shot Radar simulation with optional sub-band | `0` |
| `radar_sc_status` | Get/clear sc radar detection status | `NO RADAR_SC DETECTED` |
| `radar_status` | Get radar detection status | `NO RADAR DETECTED` |
| `radar_subband_status` | Get/clear subband radar detection status | `NO RADAR SUBBAND DETECTED` |
| `radarargs` | Get/Set Radar parameters in | `version 2 npulses 7 ncontig 54832 min_pw 6 max_pw 690 ` |
| `radarargs40` | Get/Set Radar parameters for 40Mhz channel in | **Unsupported** |
| `radarthrs` | Set Radar threshold for both 20 & 40MHz & 80MHz BW: | **Unsupported** |
| `radarthrs2` | Set Radar threshold for both 20 & 40MHz & 80MHz BW: | `version 2 thresh0_sc_20_lo 0x6b4 thresh1_sc_20_lo 0x30` |

## Transmit power

Support here is thinner than the command list suggests. `qtxpower` works and reports power in quarter-dBm; `curppr` dumps the current power-per-rate table for the operating channel. Several familiar names — `txpwrlimit`, `curpower`, `sar_limit` — are either unsupported on this build or produce nothing. Anything that *writes* power or regulatory limits is Tier D and excluded from this catalogue.

| command | what it does | returns here |
|---|---|---|
| `atten` | Set the transmit attenuation for B band. Args: bb radio txctl1. | **Unsupported** |
| `curppr` | Return current tx power per rate offset. | `Current channel:	 6 BSS channel:		 6 Power/Rate Dump (` |
| `pwr_percent` | Get/Set power output percentage | `100` |
| `txchain_pwr_offset` | Get/Set the current offsets for each core in qdBm (quarter dBm)<br>`wl txchain_pwr_offset [qdBm offsets]` | `txcore offsets qdBm: 0 0 0 0` |
| `txcore` | Usage: wl txcore -k <CCK core mask> -o <OFDM core mask> -s <1..4> -c <core bitmap> | `txcore enabled bitmap (Nsts {4..1}) 0x0f 0x0f 0x0f 0x0` |
| `txcore_override` | get the user override of txcore<br>`wl txcore_override` | `txcore enabled bitmap (Nsts {4..1}) 0x00 0x00 0x00 0x0` |
| `txinstpwr` | Return tx power based on instant TSSI | **Unsupported** |
| `txpathpwr` | Turn the tx path power on or off on 2050 radios | **Unsupported** |

## Rates, MCS and aggregation

The largest family, covering legacy rates, HT/VHT MCS selection, frame aggregation and the protection mechanisms that keep older clients working. `nrate` reads the current rate override including MCS index and STF mode. The `ampdu_*` group tunes aggregation depth and retry behaviour per traffic class — these are the knobs that matter for throughput tuning, and also the ones most likely to make things worse if changed without measurement.

| command | what it does | returns here |
|---|---|---|
| `a_mrate` | force a fixed multicast rate for the A PHY: | `auto` |
| `a_rate` | force a fixed rate for the A PHY: | `auto` |
| `ampdu_activate_test` | actiate | `ampdu_activate_test actiate` |
| `ampdu_retry_limit_tid` | Set per-tid ampdu retry limit; usage: wl ampdu_retry_limit_tid <tid> [0~31] | _needs args_ |
| `ampdu_rr_retry_limit_tid` | Set per-tid ampdu regular rate retry limit; usage: wl ampdu_rr_retry_limit_tid <tid> [0~31] | _needs args_ |
| `ampdu_rxaggr` | enable/disable rx aggregation per tid or all tid for specific interface; | `ampdu_rxaggr_override: AUTO tid:0 status:1 tid:1 statu` |
| `ampdu_tid` | enable/disable per-tid ampdu; usage: wl ampdu_tid <tid> [0/1] | _needs args_ |
| `ampdu_txaggr` | enable/disable tx aggregation per tid or all tid for specific interface; | `ampdu_txaggr_override: AUTO tid:0 status:1 tid:1 statu` |
| `ampdu_txq_prof_dump` | show txq histogram | **Unsupported** |
| `ampdu_txq_prof_start` | start sample txq profiling data | **Unsupported** |
| `ampdu_txq_ss` | take txq snapshot | **Unsupported** |
| `atim` | Set/Get the current ATIM window size | `0` |
| `bg_mrate` | force a fixed multicast rate for the B/G PHY: | `auto` |
| `bg_rate` | force a fixed rate for the B/G PHY: | `auto` |
| `bi` | Get/Set the beacon period (bi=beacon interval) | `100` |
| `cck_txbw` | get/set cck txbw (2=20Mhz(lower), 3=20Mhz upper) | **Unsupported** |
| `cur_mcsset` | Get the current mcs set | `MCS SET : [ 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 1` |
| `cwmax` | Set the cwmax. (integer [256, 2047]) | `1023` |
| `cwmin` | Set the cwmin. (integer [1, 255]) | `15` |
| `default_rateset` | Returns supported rateset of given phy.<br>`wl del_ie <pktflag> length OUI hexdata` | _needs args_ |
| `frag` | Deprecated. Use fragthresh. | `frag	Deprecated. Use fragthresh.` |
| `frameburst` | Disable/Enable frameburst mode | `1` |
| `gmode` | Set the 54g Mode (LegacyB/Auto//GOnly/BDeferred/Performance/LRS) | `54g Auto (1)` |
| `gmode_protection` | Get G protection mode. (0=disabled, 1=enabled) | `0` |
| `gmode_protection_control` | Get/Set 11g protection mode control alg.(0=always off, 1=monitor local association, 2=monitor overlapping BSS) | `2` |
| `gmode_protection_override` | Get/Set 11g protection mode override. (-1=auto, 0=disable, 1=enable) | `-1` |
| `ht_features` | disable/enable/force proprietary 11n rates support. Interface must be down. | `0` |
| `legacy_erp` | Get/Set 11g legacy ERP inclusion (0=disable, 1=enable) | `1` |
| `lifetime` | Set Lifetime parameter (milliseconds) for each ac. | `lifetime Set Lifetime parameter (milliseconds) for eac` |
| `lrl` | Set the long retry limit. (integer [1, 255]) | `6` |
| `mac_rate_histo` | (MAC address e.g. 00:11:20:11:33:33)<br>`wl mac_rate_histo <mac address> <access category> <num_pkts>` | _needs args_ |
| `mimo_ss_stf` | get/set SS STF mode.<br>`wl mimo_ss_stf <value> <-b a / b>` | `0x0` |
| `mode_reqd` | Set/Get operational capabilities required for STA to associate to the BSS supported by the interface.<br>`wl [-i ifname] mode_reqd [value]` | `0` |
| `mrate` | force a fixed multicast rate: | `auto` |
| `nrate` | "auto" to clear a rate override, or: | `mcs index 11 stf mode 3 auto` |
| `ofdm_txbw` | get/set ofdm txbw (2=20Mhz(lower), 3=20Mhz upper, 4(not allowed), 5=40Mhz dup) | **Unsupported** |
| `plcphdr` | Set the plcp header. | `long` |
| `rate` | force a fixed rate: | `52 Mbps` |
| `rate_histo` | Get rate hostrogram | **Unsupported** |
| `rateparam` | set driver rate selection tunables | `rateparam set driver rate selection tunables arg 1: tu` |
| `rateset` | Returns or sets the supported and basic rateset, (b) indicates basic | `[ 1(b) 2(b) 5.5(b) 6 9 11(b) 12 18 24 36 48 54 ] MCS S` |
| `ratetbl_ppr` | For set: wl ratetbl_ppr <rate> <ppr><br>`For get: wl ratetbl_ppr` | **Unsupported** |
| `rifs` | set/get the rifs status; usage: wl rifs <1/0> (On/Off) | `Off` |
| `rifs_advert` | set/get the rifs mode advertisement status; usage: wl rifs_advert <-1/0> (Auto/Off) | `On` |
| `rts` | Deprecated. Use rtsthresh. | `rts	Deprecated. Use rtsthresh.` |
| `rxmcsset` | get Receive MCS rateset for 11N device | **Unsupported** |
| `shortslot` | Get current 11g Short Slot Timing mode. (0=long, 1=short) | `1` |
| `shortslot_override` | Get/Set 11g Short Slot Timing mode override. (-1=auto, 0=long, 1=short) | `-1` |
| `shortslot_restrict` | Get/Set AP Restriction on associations for 11g Short Slot Timing capable STAs. | `0` |
| `srl` | Set the short retry limit. (integer [1, 255]) | `7` |
| `suprates` | Returns or sets the 11g override for the supported rateset | `[ ]` |
| `txdelay_params` | get chanim stats<br>`wl txdelay_params ratio cnt period tune` | **Unsupported** |

## MIMO, beamforming and spatial streams

Beamforming and spatial-stream configuration. `txbf_*` covers transmit beamforming, `mu_*` covers multi-user MIMO, and `txchain`/`rxchain` report which radio chains are active — useful for confirming that all four chains on this hardware are actually in use. `antdiv` reports receive antenna diversity selection.

| command | what it does | returns here |
|---|---|---|
| `antdiv` | Set antenna diversity for rx | **Unsupported** |
| `antdiv_bcnloss` | 0 - Disable Rx antenna flip feature based on consecutive beacon loss<br>`wl antdiv_bcnloss <beaconloss_count>` | **Unsupported** |
| `mimo_ps` | get/set mimo power save mode, (0=Dont send MIMO, 1=proceed MIMO with RTS, 2=N/A, 3=No restriction) | `0` |
| `mimo_txbw` | get/set mimo txbw (2=20Mhz(lower), 3=20Mhz upper, 4=40Mhz, 4=40Mhz(DUP) | **Unsupported** |
| `mu_group` | Force the group recommendation result or set parameters for VASIP group recomendation<br>`no parameters means getting configs` | _needs args_ |
| `mu_policy` | Configure the MU admission control policies<br>`no parameters means getting configs` | `Current MU policy settings: scheduler: ON, timer: 60 s` |
| `mu_rate` | Force the tranmission rate for each user, rate0 is for user0; rate1 is for user1...<br>`wl mu_rate { [auto / -1] / [[rate0] [rate1] [rate2] [rate3]]` | `Error reading svmp memory mu_rate -45 wl: Unsupported` |
| `phy_antsel` | get/set antenna configuration | `C3C2C1C0: 0x0010 fixed 0x0010 fixed 0x0010 fixed 0x001` |
| `spatial_policy` | set/get spatial_policy<br>`wl spatial_policy <-1: auto / 0: turn off / 1: turn on>` | `1` |
| `txant` | Set the transmit antenna | **Unsupported** |
| `txbf_rateset` | Get rateset consisting of OFDM, HT and VHT rates, and Broadcom-to-Broadcom | `OFDM: [ ] MCS : [ 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 1` |

## Scanning and discovery

Scanning is largely unavailable while an interface is operating as an AP — `escanresults` returns `Scan Rejected` — so treat this family as read-only reporting of cached state rather than an active survey tool on a running AP. `scan_*_time` and `scan_nprobes` expose the scan engine's timing parameters. `beacon_info` dumps the currently transmitted beacon frame, which is a convenient way to inspect exactly what the AP is advertising.

| command | what it does | returns here |
|---|---|---|
| `ap_isolate` | set/get AP isolation | `1` |
| `autochannel` | auto channel selection: | _error_ |
| `bcnlenhist` | bcnlenhist<br>`wl bcnlenhist [0]` | **Unsupported** |
| `bcntrim_stats` | Get Beacon Trim Statistics<br>`wl bcntrim_stats` | **Unsupported** |
| `beacon_info` | Returns the 802.11 management frame beacon information<br>`wl beacon_info [-f file] [-r]` | `Data: 0xca3b8 Len: 315 bytes Frame Ctl: 0x0000 Duratio` |
| `bssid` | Get the BSSID value, error if STA and not associated | `xx:xx:xx:xx:xx:xx` |
| `closed` | hides the network from active scans, 0 or 1. | `0` |
| `closednet` | set/get BSS closed network attribute | `0` |
| `csscantimer` | auto channel scan timer in minutes (0 to disable) | **Unsupported** |
| `desired_bssid` | Set or get the desired BSS ID value<br>`wl desired_bssid [BSSID]` | `xx:xx:xx:xx:xx:xx` |
| `findserver` | Used to find the remote server with proper mac address given by the user,this cmd is specific to wifi protocol. | **hangs** |
| `ignore_bcns` | AP only (G mode): Check for beacons without NONERP element(0=Examine beacons, 1=Ignore beacons) | **Unsupported** |
| `passive` | Puts scan engine into passive mode | `0` |
| `pfn` | Enable/disable preferred network off load monitoring | **Unsupported** |
| `pfn_roam_alert_thresh` | Get/Set PFN and roam alert threshold<br>`wl pfn_roam_alert_thresh [pfn_alert_thresh] [roam_alert_thresh]` | **Unsupported** |
| `pfnadd` | Adding SSID based preferred networks to monitor and connect | `pfn_add fail wl: Unsupported` |
| `pfnadd_bssid` | Adding BSSID based preferred networks to monitor and connect | `Invalid command pfnadd_bssid Adding BSSID based prefer` |
| `pfnbest` | Get the best n networks in each of up to m scans, with 16bit timestamp | `pfnbest fail wl: Unsupported` |
| `pfncfg` | Configures channel list and report type<br>`pfncfg [channel <list>] [report <type>] [prohibited 1/0]` | `pfn_cfg fail wl: Unsupported` |
| `pfneventchk` | Listen and prints the preferred network off load event from dongle | **hangs** |
| `pfnlbest` | Get the best n networks in each scan, up to m scans, with 32bit timestmp | `pfnbest fail wl: Unsupported` |
| `pfnmem` | Get supported mscan with given bestn | `Missing bestn option` |
| `pfnset` | Configures preferred network offload parameter | **Unsupported** |
| `pfnsuspend` | Suspend/resume pno scan | **Unsupported** |
| `probe_resp_info` | Returns the 802.11 management frame probe response information<br>`wl probe_resp_info [-f file] [-r]` | _(silent)_ |
| `probresp_mac_filter` | Set/Get MAC filter based Probe response mode. | `1` |
| `ssid` | Set or get a configuration's SSID. | `Current SSID: "MYSSID"` |

## Roaming, 802.11k/v/r and steering

The machinery underneath Smart Connect. `wnm_*` is 802.11v BSS transition management — the same request the band steering daemon sends. `rrm_*` is 802.11k radio measurement, which asks a client to measure and report back. `roam_trigger`, `roam_delta` and `roam_prof` tune the driver's own roaming thresholds. Most of the interesting members transmit frames and therefore sit in Tier C rather than here; what remains is the readable state.

| command | what it does | returns here |
|---|---|---|
| `assoc_pref` | Set/Get association preference.<br>`wl assoc_pref [auto/a/b/g]` | `auto` |
| `bssload_event_check` | Listens forever for BSS Load events and prints them.<br>`wl bssload_event_check` | **hangs** |
| `bssload_report` | Get the latest BSS Load IE data from the associated AP's beacon<br>`bssload_report` | **Unsupported** |
| `bssload_report_event` | Get/Set BSS load threshold for sending WLC_E_BSS_LOAD event<br>`wl bssload_report_event [rate_limit_msec] [level] [level] ...` | **Unsupported** |
| `bssload_static` | get or set static BSS load<br>`wl bssload_static [off / <sta_count> <chan_util> <acc>]` | _(silent)_ |
| `fbt_auth_resp` | Get/Set fbt auth response for an interface<br>`wl fbt_auth_resp <string>` | **Unsupported** |
| `fbt_r0kh_id` | Get/Set R0 Key Holder Idenitifer for an interface<br>`wl fbt_r0kh_id <string>` | **Unsupported** |
| `fbt_r1kh_id` | Get/Set 802.11r R1 Key Holder Idenitifer for an interface<br>`wl fbt_r1kh_id <mac-address>` | **Unsupported** |
| `rmc_ackmac` | Set/Get ACK required multicast mac address<br>`wl rmc_ackmac -i [index] -t [multicast mac address]` | **Unsupported** |
| `rmc_ackreq` | Set/Get ACK rmc_mode 0 disable, 1 enable transmitter, 2 enable initiator<br>`wl rmc_ackreq [mode]` | `Error getting variable (null) wl: Unsupported` |
| `rmc_ar` | Set active receiver to the one that matches the provided mac address<br>`wl rmc_ar [mac address]` | **Unsupported** |
| `rmc_ar_timeout` | Set/Get rmc active receiver timeout in ms<br>`wl rmc_ar_timeout [duration in ms]` | **Unsupported** |
| `rmc_rssi_delta` | Display/Set RSSI delta to switch receive leader<br>`wl rmc_rssi_delta [arg]` | **Unsupported** |
| `rmc_rssi_thresh` | Set/Get minimum rssi needed for a station to be an active receiver<br>`wl rmc_rssi_thresh [value]` | **Unsupported** |
| `rmc_stats` | Display/Clear reliable multicast client statistical counters<br>`wl rmc_stats [arg]` | **Unsupported** |
| `rmc_status` | Display reliable multicast client status | **Unsupported** |
| `rmc_vsie` | Display/Set vendor specific IE contents<br>`wl rmc_vsie [OUI] [Data]` | **Unsupported** |
| `roam_channels_in_cache` | Get a list of channels in roam cache | `���� (0x635f) ���� (0x6e6e) ���� (0x5f73) ���� (0x` |
| `roam_channels_in_hotlist` | Get a list of channels in roam hot channel list | `���� (0x635f) ���� (0x6e6e) ���� (0x5f73) ���� (0x` |
| `roam_prof` | get/set roaming profiles (need to specify band)<br>`wl roam_prof_2g a/b/2g/5g flags rssi_upper rssi_lower delta, boost_thresh boot_delta nfs` | _(silent)_ |
| `roam_scan_period` | Set the roam candidate qualification delta. (integer) | `10` |
| `roam_trigger` | Get or Set the roam trigger RSSI threshold: | `roam_trigger is 0xffb5(-75)` |
| `roamscan_parms` | set/get roam scan parameters | `Error retrieving roamscan params: -45 wl: Not Ready` |
| `rrm` | enable or disable RRM feature<br>`wl rrm [0/1] to disable/enable RRM feature` | `0x30  Beacon_Passive Beacon_Active` |
| `rrm_config` | Configure information (LCI/Civic location) for self<br>`wl rrm_config lci [lci_location]` | _needs args_ |
| `rrm_nbr_add_nbr` | add node to 11k neighbor report list<br>`wl rrm_nbr_add_nbr [bssid] [bssid info] [regulatory] [channel] [phytype]` | _needs args_ |
| `rrm_nbr_del_nbr` | delete node from 11k neighbor report list<br>`wl rrm_nbr_del_nbr [bssid]` | _needs args_ |
| `rrm_nbr_list` | get 11k neighbor report list<br>`wl rrm_nbr_list` | **Unsupported** |
| `rrm_stat_rpt` | Read 11k stat measurement report from STA<br>`wl rrm_stat_rpt [mac]` | _(silent)_ |
| `wnm` | set driver wnm feature mask | `0x1:  BSS-Transition` |
| `wnm_bsstrans_roamthrottle` | Get/Set number of roam scans allowed in throttle period<br>`wl wnm_bsstrans_roamthrottle [throttle_period] [scans_allowed]` | _error_ |
| `wnm_bsstrans_rssi_rate_map` | Get/Set rssi to rate map<br>`wl wnm_bsstrans_rssi_rate_map mode data` | `Mode is required` |
| `wnm_dms_set` | Optionally add pending DMS desc (after tclas_add) and optionally register all desc | `Missing <send> argument` |
| `wnm_dms_status` | list all DMS descriptors and provide their internal and AP status<br>`wl wl_wnm_dms_status` | **Unsupported** |
| `wnm_dms_term` | Disable registered DMS des on AP side and optionally discard them<br>`wl wnm_dms_term <del> [<user_id>]` | `Missing <del> argument` |
| `wnm_keepalives_max_idle` | set/get the number of keepalives, mkeep-alive index and max_interval configured per BSS-Idle period.<br>`wl wnm_keepalives_max_idle <keepalives_per_bss_max_idle> <mkeepalive_index> [<max_interv` | `Keepalives_max_idle parameters - num_of_keepalives_per` |
| `wnm_maxidle` | setup WNM BSS Max Idle Period interval and option<br>`wl wnm_maxidle <Idle Period> <Option>` | `BSS Max Idle Period: 0` |
| `wnm_service_term` | Disable service. Check specific wnm_XXX_term for more info<br>`wl wnm_service_term <srv> <service realted params>` | `Missing <service> argument` |
| `wnm_timbc_offset` | get/set TIM broadcast offset by -32768 period > offset(us) > 32768<br>`wl wnm_timbc_offset <offset> [<tsf_present> [<fix_interval> [<rate_ovreride>]]]` | `TIMBC offset: 10, tsf_present: 1, fix_interval: 0, rat` |
| `wnm_timbc_status` | Retrieve TIM Broadcast configuration set with current AP | _error_ |
| `wnm_url` | set/get wnm session information url | `wnm_url URL len 0 wnm_url URL:` |

## Security and encryption

`wsec` is a bit vector describing which ciphers are enabled; `wpa_auth` describes the authorisation modes. These are useful for confirming what a BSS actually negotiated rather than what the GUI claims. The WEP-era commands survive for compatibility and are of historical interest only.

| command | what it does | returns here |
|---|---|---|
| `addwep` | Set an encryption key. The key must be 5, 13 or 16 bytes long, or | `addwep	Set an encryption key.  The key must be 5, 13 o` |
| `eap` | restrict traffic to 802.1X packets until 802.1X authorization succeeds | `1` |
| `eap_restrict` | set/get EAP restriction | `1` |
| `keys` | Prints a list of the current WEP keys | _(silent)_ |
| `mfp_config` | Config PMF capability<br>`wl mfp 0/disable, 1/capable, 2/requred` | _(silent)_ |
| `mfp_sha256` | Config SHA256 capability<br>`wl sha256 0/disable, 1/enable` | **Unsupported** |
| `pmkid_info` | Returns the pmkid table | `pmkid entries : 0` |
| `primary_key` | Set or get index of primary key | `No primary key set` |
| `rmwep` | Remove the encryption key at the specified key index. | `rmwep	Remove the encryption key at the specified key i` |
| `set_pmk` | Set passphrase for PMK in driver-resident supplicant. | `set_pmk	Set passphrase for PMK in driver-resident supp` |
| `tsc` | Print Tx Sequence Couter for key at specified key index. | `tsc	Print Tx Sequence Couter for key at specified key ` |
| `wepstatus` | Set or Get WEP status | `0` |
| `wpa_auth` | Bitvector of WPA authorization modes: | `0x80 WPA2-PSK` |
| `wpa_cap` | set/get 802.11i RSN capabilities | `12` |
| `wsec` | wireless security bit vector | `0` |
| `wsec_restrict` | Drop unencrypted packets if WSEC is enabled | `1` |
| `wsec_test` | Generate wsec errors | `wsec test_type may be a number or name from the follow` |

## QoS, WME and traffic management

WME is Broadcom's name for WMM. `wme_counters` gives per-access-category packet counts, which is the honest way to see whether traffic classification is doing anything. `trf_mgmt_*` is a separate rate-limiting and classification subsystem; on this firmware most of it reports unsupported. `cac_*` covers admission control.

| command | what it does | returns here |
|---|---|---|
| `cac_addts` | add TSPEC, error if STA is not associated or WME is not enabled | `This command can ONLY be executed on a STA or APSTA` |
| `cac_delts` | delete TSPEC, error if STA is not associated or WME is not enabled | `This command can ONLY be executed on a STA or APSTA` |
| `cac_delts_ea` | delete TSPEC, error if STA is not associated or WME is not enabled | _needs args_ |
| `cac_tslist` | Get the list of TSINFO in driver | `This command can ONLY be executed on a STA or APSTA` |
| `cac_tslist_ea` | Get the list of TSINFO for given STA in driver | `cac_tslist_ea Get the list of TSINFO for given STA in ` |
| `cac_tspec` | Get specific TSPEC with matching TSINFO | `This command can only be executed on the STA` |
| `cac_tspec_ea` | Get specific TSPEC for given STA with matching TSINFO | _needs args_ |
| `taf` | wl taf <MAC> [<scheduler_id> [<priority>]] | _needs args_ |
| `tclas_list` | list the added tclas frame classifier type entry<br>`wl tclas_list` | **Unsupported** |
| `trf_mgmt_bandwidth` | Sets/gets traffic management bandwidth configuration.<br>`wl trf_mgmt_bandwidth` | **Unsupported** |
| `trf_mgmt_config` | Sets/gets traffic management configuration.<br>`wl trf_mgmt_config [<enable>` | `Enabled                   : 0 Host IP Address         ` |
| `trf_mgmt_filters_addex` | Adds a traffic management filter.<br>`wl trf_mgmt_filter_add flag [dst_port src_port prot priority]` | _needs args_ |
| `trf_mgmt_filters_list` | Lists all traffic management filters.<br>`wl trf_mgmt_filter_list` | `Number of filters : 0` |
| `trf_mgmt_filters_remove` | Removes a traffic management filter.<br>`wl trf_mgmt_filter_remove [dst_port src_port prot]` | _needs args_ |
| `trf_mgmt_filters_removeex` | Removes a traffic management filter.<br>`wl trf_mgmt_filter_remove flag [dst_port src_port prot]` | _needs args_ |
| `trf_mgmt_flags` | Sets/gets traffic management operational flags.<br>`wl trf_mgmt_flags [flags]` | `Flags : 0x0000` |
| `trf_mgmt_shaping_info` | Gets traffic management shaping parameters.<br>`wl trf_mgmt_shaping_info [index]` | **Unsupported** |
| `trf_mgmt_stats` | Gets traffic management statistics.<br>`wl trf_mgmt_stats [index]` | `Statistics for Tx Queue[0] Num. packets processed : 0 ` |
| `wme` | Set WME (Wireless Multimedia Extensions) mode (0=off, 1=on, -1=auto) | `1` |
| `wme_ac` | wl wme_ac ap/sta [be/bk/vi/vo [ecwmax/ecwmin/txop/aifsn/acm <value>] ...] | `wme_ac	wl wme_ac ap/sta [be/bk/vi/vo [ecwmax/ecwmin/tx` |
| `wme_apsd` | Set APSD (Automatic Power Save Delivery) mode on AP (0=off, 1=on) | `1` |
| `wme_apsd_sta` | Set APSD parameters on STA. Driver must be down.<br>`wl wme_apsd_sta <max_sp_len> <be> <bk> <vi> <vo>` | `wme_apsd_sta: STA only` |
| `wme_apsd_trigger` | Set Periodic APSD Trigger Frame Timer timeout in ms (0=off) | _error_ |
| `wme_autotrigger` | Enable/Disable sending of APSD Trigger frame when all ac are delivery enabled | **Unsupported** |
| `wme_clear_counters` | clear WMM counters | _(silent)_ |
| `wme_counters` | print WMM stats<br>`wl wme_dp <be> <bk> <vi> <vo>` | `AC_BE: tx frames: 0 bytes: 0 failed frames: 0 failed b` |
| `wme_dp` | Set AC queue discard policy.<br>`wl wme_dp <be> <bk> <vi> <vo>` | `Discard oldest first: BE=0 BK=0 VI=0 VO=0` |
| `wme_maxbw_params` | wl wme_maxbw_params [be/bk/vi/vo <value> ....] | **Unsupported** |
| `wme_tx_params` | wl wme_tx_params [be/bk/vi/vo [short/sfb/long/lfb/max_rate <value>] ...] | **Unsupported** |

## Power save and wake-on-wireless

`pm` reports the power management mode of the interface. The `wowl_*` family is wake-on-wireless-LAN — pattern matching that wakes a sleeping host on specific frames. Largely irrelevant on a mains-powered router acting as an AP, but present and readable.

| command | what it does | returns here |
|---|---|---|
| `dtim` | Get/Set DTIM | `3` |
| `lpc_params` | Set/Get Link Power Control params<br>`wl powersel_params <tp_ratio_thresh> <rate_stab_thresh>` | **Unsupported** |
| `mpc_dur` | Retrieve accumulated MPC duration information in ms (GET) or clear accumulator (SET)<br>`wl mpc_dur <any-number-to-clear>` | `0` |
| `pm2_sleep_ret_ext` | Get/Set Dynamic Fast Return To Sleep params | `logic: 0 (DISABLED)` |
| `pm_dur` | Retrieve accumulated PM duration information (GET only) | `0` |
| `pm_mute_tx` | Sets parameters for power save mode with muted transmission path. Usage: | _(silent)_ |
| `pmac` | Get mac obj values such as of SHM and IHR<br>`wl pmac <type> <addresses up to 16> -s <step size> -n <num> -b <bitmap> -w <write val> -` | _needs args_ |
| `rpmt` | rpmt <pm1-to> <pm0-to> | `rpmt	rpmt <pm1-to> <pm0-to>` |
| `sr_dump_pmu` | Dump value of PMU registers | **Unsupported** |
| `sr_pmu_keep_on` | Keep resource on | **Unsupported** |
| `sr_power_island` | Keep power islands on/off.<br>`For get:wl sr_power_island` | **Unsupported** |
| `tbow_doho` | Trigger the BT-WiFi handover/handback | `wl tbow_doho <opmode> <chanspec> <ssid> <passphrase> <` |
| `wake` | set driver power-save mode sleep state: | **Unsupported** |
| `wowl` | Enable/disable WOWL events | `0` |
| `wowl_bcn_loss` | Set #of seconds of beacon loss for wakeup event | **Unsupported** |
| `wowl_ext_magic` | Set 6-byte extended magic pattern<br>`wl wowl_ext_magic 0x112233445566` | **Unsupported** |
| `wowl_pattern` | No options -- lists existing pattern list<br>`wowl_pattern [ [clr / [[ add / del ] offset mask value ]]]` | `#of patterns :0` |
| `wowl_status` | Shows last system wakeup setting<br>`wowl_status [clear]` | `Status of last wakeup: flags:0x0` |
| `wowl_wakeind` | Shows last system wakeup event indications from PCI and D11 cores<br>`wowl_wakeind [clear]` | `No wakeup indication set` |
| `wowl_wakeup_reason` | Returns pattern id and associated wakeup reason | **Unsupported** |

## Statistics and counters

`counters` returns the full driver statistics block — hundreds of fields covering transmit, receive, retries, errors and PHY events. It is the single richest diagnostic in the set and worth capturing periodically if you are chasing an intermittent problem. `pktq_stats` covers queue depth and drops; `delta_stats` gives change-since-last-call rather than cumulative totals, which is usually what you want.

| command | what it does | returns here |
|---|---|---|
| `arp_stats` | Display ARP offload statistics | **Unsupported** |
| `assertlog` | get external assert logs<br>`wl assertlog` | **Unsupported** |
| `counters` | Return driver counter values | `counters_version 30 reinit 1 reinitreason_counts: 0(0)` |
| `delta_stats` | get the delta statistics for the last interval | _error_ |
| `delta_stats_interval` | set/get the delta statistics interval in seconds (0 to disable) | `0` |
| `malloc_dump` | Deprecated. Folded under 'wl dump malloc | `malloc_dump Deprecated. Folded under 'wl dump malloc` |
| `memuse` | Get memory usage statistics<br>`wl memuse` | `Heap Total: 1659580(1621K), Heap Free: 593256(580K)` |
| `ol_stats` | Give suboption "list" to list various suboptions | **Unsupported** |
| `pktcnt` | Get the summary of good and bad packets. | `Receive: good packet 209333, bad packet 70, othercast ` |
| `pktq_stats` | Dumps packet queue log info for [C] common, [A] AMPDU, [N] NAR or [P] power save queues | `Common queue: prec:   rqstd,  stored, dropped, retried` |
| `smfstats` | get/clear selected management frame (smf) stats wl smfstats [-C num]/[--cfg=num] [auth]/[assoc]/[reassoc]/[clear]<br>`wl spatial_policy <-1: auto / 0: turn off / 1: turn on>` | `Frame type: Authentication_Request Ignored Count: 0 Ma` |
| `toe_stats` | Display checksum offload statistics | **Unsupported** |

## Offload: ARP, ND, TOE, packet filters

Broadcom can offload ARP and IPv6 neighbour discovery responses to the firmware so the host does not wake for them, and `pkt_filter_*` installs frame filters in the same place. On an always-on router this is mostly moot, but `arp_stats` and `toe_stats` are useful for confirming whether offload is engaged at all.

| command | what it does | returns here |
|---|---|---|
| `arp_hostip` | Add a host-ip address or display them | **Unsupported** |
| `arp_ol` | Get/Set arp offload components | **Unsupported** |
| `arp_peerage` | Get/Set age of the arp entry in minutes | **Unsupported** |
| `arpoe` | Enable/Disable arp agent offload feature | `0` |
| `nd_hostip` | Add a local host-ipv6 address or display them | _(silent)_ |
| `nd_macaddr` | Get/set the MAC address for offload | `nd_macaddr xx:xx:xx:xx:xx:xx` |
| `nd_remoteip` | Add a local remote ipv6 address or display them | **Unsupported** |
| `nd_solicitip` | Add a local host solicit ipv6 address or display them | **Unsupported** |
| `nd_status` | Displays Neighbor Discovery Status | `host_ip_entries 0 host_ip_overflow 0 peer_request 0 pe` |
| `ns_hostip` | Add a ns-ip address or display then | **Unsupported** |
| `ol_arp_hostip` | Add a host-ip address or display them | **Unsupported** |
| `ol_clr` | Give suboption "list" to list various suboptions | **Unsupported** |
| `ol_cons` | Display the ARM console or issue a command to the ARM console<br>`ol_cons [<cmd>]` | **Unsupported** |
| `ol_eventlog` | Give suboption "list" to list various suboptions | **Unsupported** |
| `ol_nd_hostip` | Add a local host-ipv6 address or display them | **Unsupported** |
| `ol_notify_bcn_ie` | Enable/Disable IE ID notification | **Unsupported** |
| `ol_wowl_cons` | Give suboption "list" to list various suboptions | **Unsupported** |
| `pkt_filter_delete` | Uninstall a packet filter.<br>`wl pkt_filter_delete <id>` | **Unsupported** |
| `pkt_filter_enable` | Enable/disable a packet filter.<br>`wl pkt_filter_enable <id> <0/1>` | _needs args_ |
| `pkt_filter_list` | List installed packet filters.<br>`wl pkt_filter_list [val]` | _needs args_ |
| `pkt_filter_mode` | Set packet filter match action.<br>`wl pkt_filter_mode <value>` | `1` |
| `pkt_filter_ports` | Set up additional port filters for TCP and UDP packets.<br>`wl pkt_filter_ports [<port-number>] ...` | **Unsupported** |
| `pkt_filter_stats` | Retrieve packet filter statistic counter values.<br>`wl pkt_filter_stats <id>` | _needs args_ |
| `toe` | Enable/Disable tcpip offload feature | `0` |
| `toe_ol` | Get/Set tcpip offload components | **Unsupported** |

## WDS, bridging and virtual interfaces

WDS and the various bridging modes — `wet` is wireless ethernet bridging, `dwds` dynamic WDS, `psta` proxy STA. `interface_create` and `interface_remove` add or remove virtual BSSes, and are Tier B because a bare call acts. `proxd_*` is proximity/ranging (802.11mc fine timing measurement), largely unsupported here.

| command | what it does | returns here |
|---|---|---|
| `aibss_bcn_force_config` | Get/Set AIBSS beacon force configuration | **Unsupported** |
| `aibss_txfail_config` | Set/Get txfail configuration for bcn_timeout, max tx retries and max atim failures<br>`wl aibss_txfail_config [bcn_timeout max_retry max_atim_failure]` | **Unsupported** |
| `ibss_route_tbl` | Get/Set ibss route table<br>`wl ibss_route_tbl num_entries [{ip_addr1, mac_addr1}, ...]` | **Unsupported** |
| `proxd` | Enable/Disable Proximity Detection | **Unsupported** |
| `proxd_bssid` | Set/Get BSSID to be used in proximity detection frames<br>`wl proxd_bssid <xx:xx:xx:xx:xx:xx>` | **Unsupported** |
| `proxd_collect` | collect the debugging informations of Proximity Detection | **Unsupported** |
| `proxd_event_check` | Listen and print Location Based Service events | `<ifname> param is missing` |
| `proxd_mcastaddr` | Set/Get Multicast MAC address of Proximity Detection Frames<br>`wl proxd_mcastaddr <xx:xx:xx:xx:xx:xx>` | **Unsupported** |
| `proxd_monitor` | Monitor detected peer status in proximity<br>`wl proxd_monitor <xx:xx:xx:xx:xx:xx>` | **Unsupported** |
| `proxd_params` | Set/Get operational parameters for a method of Proximity Detection<br>`wl proxd_params method [-c channel] [-i interval] [-d duration] [-s rssi_thresh] [-p tx_` | _needs args_ |
| `proxd_payload` | Get/Set payload content transferred between the proximity detected peers<br>`wl proxd_payload [len hexstring]` | **Unsupported** |
| `proxd_report` | Get/Set report distance results list<br>`wl proxd_report [mac address list]` | **Unsupported** |
| `proxd_status` | Get status of Proximity Detection | **Unsupported** |
| `proxd_tune` | Set/Get tune parameters for TOF method of Proximity Detection<br>`wl proxd_tune method [operations]` | _needs args_ |
| `wds` | Set or get the list of WDS member MAC addresses. | _(silent)_ |
| `wds_ap_ifname` | Get associated AP interface name for WDS interface. | **Unsupported** |
| `wds_remote_mac` | Get WDS link remote endpoint's MAC address | _error_ |
| `wds_type` | Indicate whether the interface to which this IOVAR is sent is of WDS or DWDS type.<br>`wl wds_type -i <ifname>` | `0` |
| `wds_wpa_role` | Get/Set WDS link local endpoint's WPA role | _error_ |
| `wds_wpa_role_old` | Get WDS link local endpoint's WPA role (old) | _error_ |
| `wet` | Get/Set wireless ethernet bridging mode | **Unsupported** |

## P2P, ANQP, Hotspot and TDLS

Wi-Fi Direct, Hotspot 2.0 / Passpoint service discovery, and Tunnelled Direct Link Setup. The firmware advertises `p2po` and `anqpo` in its capability string, so parts of this are genuinely implemented, but it is aimed at client and mobile use cases rather than an AP acting as infrastructure.

| command | what it does | returns here |
|---|---|---|
| `anqpo_auto_hotspot` | automatic ANQP query to maximum number of hotspot APs, default 0 (disabled)<br>`anqpo_auto_hotspot [max]` | **Unsupported** |
| `anqpo_ignore_bssid_list` | get, clear, set, or append to ANQP offload ignore BSSID list<br>`wl anqpo_ignore_bssid_list [clear /` | **Unsupported** |
| `anqpo_ignore_mode` | ignore duplicate SSIDs or BSSIDs, default 0 (SSID)<br>`anqpo_ignore_mode [0 (SSID) / 1 (BSSID)]` | **Unsupported** |
| `anqpo_ignore_ssid_list` | get, clear, set, or append to ANQP offload ignore SSID list<br>`wl anqpo_ignore_ssid_list [clear /` | **Unsupported** |
| `anqpo_results` | Listens and displays ANQP results. | **hangs** |
| `anqpo_set` | set ANQP offload parameters<br>`anqpo_set [max_retransmit <number>]` | **Unsupported** |
| `hs20_ie` | set hotspot 2.0 indication IE<br>`wl hs20_ie <length> <hexdata>` | _needs args_ |
| `p2p_da_override` | Get/Set WiFi P2P device interface addr<br>`wl p2p_da_override <MAC-address>` | **Unsupported** |
| `p2p_if` | query WiFi P2P interface bsscfg index<br>`wl p2p_if <MAC-address>` | _needs args_ |
| `p2p_ifadd` | add WiFi P2P interface<br>`wl p2p_ifadd <MAC-address> go/client/dyngo [chanspec]` | _needs args_ |
| `p2p_ifdel` | delete WiFi P2P interface<br>`wl p2p_ifdel <MAC-address>` | _needs args_ |
| `p2p_ifupd` | update an interface to WiFi P2P interface<br>`wl p2p_ifupd <MAC-address> go/client` | _needs args_ |
| `p2p_noa` | set/get WiFi P2P NoA schedule<br>`wl p2p_noa <type> <type-specific-params>` | `p2p_noa: error -45 wl: Unsupported` |
| `p2p_ops` | set/get WiFi P2P OppPS and CTWindow<br>`wl p2p_ops <ops> [<ctw>]` | `p2p_ops: error -45 wl: Unsupported` |
| `p2p_scan` | initiate WiFi P2P scan.<br>`wl p2p_scan S/E <scan parms>` | `wrong syntax, need 'S' or 'E'` |
| `p2p_ssid` | set WiFi P2P wildcard ssid.<br>`wl p2p_ssid <ssid>` | **Unsupported** |
| `p2p_state` | set WiFi P2P discovery state.<br>`wl p2p_state <state> [<chanspec> <dwell time>]` | _needs args_ |
| `p2po_addsvc` | add query-service pair<br>`p2po_addsvc <protocol> <"query"> <"response">` | _needs args_ |
| `p2po_delsvc` | delete query-service pair<br>`p2po_delsvc <protocol> <"query">` | _needs args_ |
| `p2po_gas_config` | set GAS state machine tunable parameters<br>`p2po_gas_config <max_retrans> <resp_timeout> <max_comeback_delay> <max_retries>` | **Unsupported** |
| `p2po_results` | Listens and displays P2PO results. | **hangs** |
| `p2po_sd_cancel` | cancel finding a service | **Unsupported** |
| `p2po_sd_req_resp` | find a service<br>`p2po_sd_req_resp <protocol> <"query">` | _needs args_ |
| `p2po_wfds_seek_dump` | dump WFDS services to seek | **Unsupported** |
| `tdls_endpoint` | Available TDLS operations to each TDLS peer.<br>`wl tdls_endpoint <disc, create, delete, PM, wake, cw> <ea> [chanspec]` | _needs args_ |
| `tdls_sta_info` | wl tdls_sta_info <xx:xx:xx:xx:xx:xx> | `tdls_sta_info wl tdls_sta_info <xx:xx:xx:xx:xx:xx> ERR` |
| `tdls_wfd_ie` | To set, get and clear additional WFD IE in setup_req and setup_resp<br>`wl tdls_wfd_ie get <own/peer_eth_addr#> [ip] [port]` | _needs args_ |

## PHY and radio internals

The lowest readable layer: per-antenna RSSI, gain tables, TSSI, and PHY register access. `phy_rssi_ant` is genuinely useful — per-antenna RSSI for a receive path. Most of the rest is calibration and manufacturing territory, and the corresponding *write* commands are Tier D for good reason. `sample_collect` captures raw PHY samples with a trigger condition and is the closest thing this platform has to a spectrum tool.

| command | what it does | returns here |
|---|---|---|
| `evm` | Start an EVM test on the given channel, or stop EVM test. | `Need to specify at least one parameter evm	Start an EV` |
| `fem` | Set temp fem2g/5g value<br>`wl fem (tssipos2g=0x1 extpagain2g=0x2 pdetrange2g=0x1 triso2g=0x1 antswctl2g=0)` | `wl_phy_fem: fail to get fem2g wl_phy_fem: fail to get ` |
| `fqacurcy` | Manufacturing test: set frequency accuracy mode. | _(silent)_ |
| `lcnphy_papdepstbl` | print papd eps table; Usage: wl lcnphy_papdepstbl | **Unsupported** |
| `longtrain` | Manufacturing test: set longtraining mode. | _(silent)_ |
| `macreg` | Get/Set any mac registers(include IHR and SB): | `macreg	Get/Set any mac registers(include IHR and SB): ` |
| `macregx` | Get/Set any mac registers(include IHR and SB) of PSMX: | `macregx	Get/Set any mac registers(include IHR and SB) ` |
| `phy_dyn_switch_th` | Set wighting number for dynamic switch: | `version 1 rssi_gain_80_3 2 rssi_gain_80_2 3 rssi_gain_` |
| `phy_force_crsmin` | Auto crsmin: | _(silent)_ |
| `phy_forceimpbf` | force the beamformer into implicit TXBF mode and ready to construct steering matrix<br>`wl phy_forceimpbf` | **Unsupported** |
| `phy_forcesteer` | force the beamformer to apply steering matrix when TXBF is turned on<br>`wl phy_forcesteer 1/0` | _needs args_ |
| `phy_rssi_ant` | Get RSSI per antenna (only gives RSSI of current antenna for SISO PHY) | `rssi[0] -55  rssi[1] 0  rssi[2] 0  rssi[3] 0` |
| `phy_rssi_gain_delta_2g` | Set/get rssi gain delta values<br>`phy_rssi_gain_delta_2g [val0 val1 ....]` | **Unsupported** |
| `phy_rssi_gain_delta_2gb0` | Number of arguments can be - 8 for single core (4345 and 4350) 9 by specifying core_num followed by 8 arguments (4345 <br>`phy_rssi_gain_delta_2gb0 [val0 val1 ....]` | **Unsupported** |
| `phy_rssi_gain_delta_2gb1` | Number of arguments can be - 8 for single core (4345 and 4350) 9 by specifying core_num followed by 8 arguments (4345 <br>`phy_rssi_gain_delta_2gb1 [val0 val1 ....]` | **Unsupported** |
| `phy_rssi_gain_delta_2gb2` | Number of arguments can be - 8 for single core (4345 and 4350) 9 by specifying core_num followed by 8 arguments (4345 <br>`phy_rssi_gain_delta_2gb2 [val0 val1 ....]` | **Unsupported** |
| `phy_rssi_gain_delta_2gb3` | Number of arguments can be - 8 for single core (4345 and 4350) 9 by specifying core_num followed by 8 arguments (4345 <br>`phy_rssi_gain_delta_2gb3 [val0 val1 ....]` | **Unsupported** |
| `phy_rssi_gain_delta_2gb4` | Number of arguments can be - 8 for single core (4345 and 4350) 9 by specifying core_num followed by 8 arguments (4345 <br>`phy_rssi_gain_delta_2gb4 [val0 val1 ....]` | **Unsupported** |
| `phy_rssi_gain_delta_5gh` | Set/get rssi gain delta values<br>`phy_rssi_gain_delta_5gh [val0 val1 ....]` | **Unsupported** |
| `phy_rssi_gain_delta_5gl` | Set/get rssi gain delta values<br>`phy_rssi_gain_delta_5gl [val0 val1 ....]` | **Unsupported** |
| `phy_rssi_gain_delta_5gml` | Set/get rssi gain delta values<br>`phy_rssi_gain_delta_5gml [val0 val1 ....]` | **Unsupported** |
| `phy_rssi_gain_delta_5gmu` | Set/get rssi gain delta values<br>`phy_rssi_gain_delta_5gmu [val0 val1 ....]` | **Unsupported** |
| `phy_rssiant` | wl phy_rssiant antindex(0-3) | _needs args_ |
| `phy_rxgainerr_2g` | Set/get rx gain delta values<br>`phy_rxgainerr_2g [val0 val1 ....]` | **Unsupported** |
| `phy_rxgainerr_5gh` | Set/get rx gain delta values<br>`phy_rxgainerr_5gmu [val0 val1 ....]` | **Unsupported** |
| `phy_rxgainerr_5gl` | Set/get rx gain delta values<br>`phy_rxgainerr_5gl [val0 val1 ....]` | **Unsupported** |
| `phy_rxgainerr_5gm` | Set/get rx gain delta values<br>`phy_rxgainerr_5gml [val0 val1 ....]` | **Unsupported** |
| `phy_rxgainerr_5gu` | Set/get rx gain delta values<br>`phy_rxgainerr_5gh [val0 val1 ....]` | **Unsupported** |
| `phy_rxiqest` | Get phy RX IQ noise in dBm: | `-92dBm -116dBm -116dBm -116dBm` |
| `phy_txpwrindex` | phy_txpwrindex<br>`(set) phy_txpwrindex core0_idx core1_idx core2_idx core3_idx (get) phy_txpwrindex, retur` | **Unsupported** |
| `phymsglevel` | set phy debugging message bitvector | _(silent)_ |
| `phyreg` | Get/Set a phy register: | `phyreg	Get/Set a phy register: offset [ value ] [ band` |
| `radio` | Set the radio on or off. | `0x0000` |
| `rssi` | Get the current RSSI val, for an AP you must specify the mac addr of the STA | _error_ |
| `rssi_cal_freq_grp_2g` | Each of the variables like - chan_1_2 is a byteUpper nibble of this byte is for chan1 and lower for chan2MSB of the ni<br>`wl_rssi_cal_freq_grp_2g [chan_1_2,chan_3_4,...,chan_13_14]` | **Unsupported** |
| `rssi_event` | Set parameters associated with RSSI event notification<br>`wl rssi_event <rate_limit> <rssi_levels>` | `0` |
| `sample_collect` | Optional parameters ACPHY/HTPHY/(NPHY with NREV >= 7) are: | **Unsupported** |
| `svmp_mem` | With 2 params, read svmp memory at offset for len of 16-bit width.<br>`wl svmp_mem <offset> <len> [ <val> ]` | _needs args_ |
| `tssi` | Get the tssi value from radio | **Unsupported** |
| `ucflags` | Get/Set ucode flags 1, 2, 3(16 bits each) | `ucflags	Get/Set ucode flags 1, 2, 3(16 bits each) offs` |

## Driver debug, events and logging

`msglevel` is a bit vector controlling driver console verbosity — raise it and messages appear in syslog. `event_msgs` is the event subscription mask. `monitor` and `promisc` belong here on this firmware because, although the control surface is complete, no frames are ever delivered — see `docs/00-hardware.md`. `assertlog` and the dump commands expose internal driver state.

| command | what it does | returns here |
|---|---|---|
| `assert_type` | set/get the asset_bypass flag; usage: wl assert_type <1/0> (On/Off) | `0` |
| `bcmerrorstr` | errorstring | `Bad Argument` |
| `bmon_bssid` | Set monitored BSSID<br>`bmon_bssid xx:xx:xx:xx:xx:xx 0/1` | _needs args_ |
| `btc_dynctl` | [-d dflt_dsns_level] [-l low_dsns_level] [-m mid_dsns_level] [-h high_dsns_level] | `btc_dynctl: getbuf ioctl failed` |
| `btc_dynctl_sim` | btc_dynctl_sim<br>`wl btc_dynctl_sim [1/0] [-b bt_sim_pwr] [-r bt_sim_rssi] [-w wl_sim_rssi]` | `btc_dynctl: getbuf ioctl failed` |
| `btc_dynctl_status` | btc_dynctl_status<br>`command doeesn't take any arguments]` | `btc_dynctl: getbuf ioctl failed` |
| `btc_flags` | g/set BT Coex flags | `btc_flags g/set BT Coex flags` |
| `btc_params` | g/set BT Coex parameters | `btc_params g/set BT Coex parameters` |
| `chq_event` | Set parameters associated with channel quality event notification<br>`wl chq_event <rate_limit> <cca_levels> <nf_levels> <nf_lte_levels>` | **Unsupported** |
| `clk` | set board clock state. return error for set_clk attempt if the driver is not down | `1` |
| `cmds` | generate a short list of available commands | `a_rate            event_log_set_init phy_rssi_gain_del` |
| `dngl_wd` | enable or disable dongle keep alive watchdog timer<br>`wl dngl_wd 0\1 (to turn off\on)` | **Unsupported** |
| `dump` | Give suboption "list" to list various suboptions | `N/A` |
| `event_filter` | Set/get event filter | _(silent)_ |
| `event_log_set_expand` | Increase the size of an event log set<br>`wl event_log_set_expand <set> <size>` | _needs args_ |
| `event_log_set_init` | Initialize an event log set<br>`wl event_log_set_init <set> <size>` | _needs args_ |
| `event_log_set_shrink` | Decrease the size of an event log set<br>`wl event_log_set_expand <set>` | _needs args_ |
| `event_log_tag_control` | Modify the state of an event log tag<br>`wl event_log_tag_control <tag> <set> <flags>` | _needs args_ |
| `event_msgs` | set/get hex filter bitmask for MAC event reporting via packet indications | `0x0c00000000000600010000` |
| `event_msgs_ext` | set/get bit arbitrary size hex filter bitmask for MAC | `0x091008300000000000000c00000000000600010000` |
| `eventing` | set/get hex filter bitmask for MAC event reporting up to application layer | **Unsupported** |
| `extlog` | get external logs<br>`wl extlog <from_last> <number>` | **Unsupported** |
| `extlog_cfg` | get/set external log configuration | **Unsupported** |
| `extlog_clr` | clear external log records | **Unsupported** |
| `fasttimer` | Deprecated. Use fast_timer. | `fasttimer Deprecated. Use fast_timer.` |
| `led_blink_sync` | set/get led_blink_sync<br>`wl led_blink_sync [0-3] [0/1]` | _needs args_ |
| `ledbh` | set/get led behavior<br>`wl ledbh [0-3] [0-15]` | _needs args_ |
| `monitor` | set monitor mode | `0` |
| `monitor_lq` | Start/Stop monitoring link quality metrics - RSSI and SNR<br>`wl monitor_lq <0: turn off / 1: turn on` | **Unsupported** |
| `monitor_lq_status` | Returns averaged link quality metrics - RSSI and SNR values | **Unsupported** |
| `monitor_promisc_level` | Set a bitmap of different MAC promiscuous level of monitor mode.<br>`wl monitor_promisc_level [<bitmap> / <+/-name>]` | `0x0` |
| `msglevel` | set driver console debugging message bitvector | `0x101  error assoc` |
| `mws_debug_msg` | Get/Set LTE coex BT-SIG message<br>`wl mws_debug_msg <Message> <Interval 20us-32000us> <Repeats>` | **Unsupported** |
| `nvget` | get the value of an nvram variable | `nvget	get the value of an nvram variable nvget: missin` |
| `promisc` | set promiscuous mode ethernet address reception | `1` |
| `slowtimer` | Deprecated. Use slow_timer. | `slowtimer Deprecated. Use slow_timer.` |
| `wci2_config` | Get/Set LTE coex MWS signaling config<br>`wl wci2_config <rxassert_off> <rxassert_jit> <rxdeassert_off> <rxdeassert_jit> <txassert` | **Unsupported** |

## Information elements

Vendor-specific information elements added to beacons and probe responses. `add_ie` and `del_ie` write them; `list_ie` reads what is currently attached. Useful if you want the AP to advertise something custom, and one of the few genuinely creative things this interface allows.

| command | what it does | returns here |
|---|---|---|
| `add_ie` | Add a vendor proprietary IE to 802.11 management packets<br>`wl add_ie <pktflag> length OUI hexdata` | _needs args_ |
| `del_ie` | Delete a vendor proprietary IE from 802.11 management packets<br>`wl del_ie <pktflag> length OUI hexdata` | _needs args_ |
| `ie` | set/get IE<br>`For set: wl ie type length hexdata` | _needs args_ |
| `list_ie` | Dump the list of vendor proprietary IEs | `Total IEs 1 IE index = 0 ----------------- Pkt Flg = 0` |

## 802.11h spectrum management

Dynamic frequency selection and transmit power control as required in regulatory domains that mandate them. `spect` reports the spectrum management mode; `tpc_*` covers transmit power control reporting. `csa` announces a channel switch and transmits, so it is not in this tier.

| command | what it does | returns here |
|---|---|---|
| `antgain` | Set temp ag0/1 value<br>`wl antgain ag0=0x1 ag1=0x2` | `wl_antgain: fail to get antgain` |
| `csa` | Send an 802.11h channel switch anouncement with chanspec: | `csa	Send an 802.11h channel switch anouncement with ch` |
| `maxpower` | Set temp maxp2g(5g)a0(a1) value<br>`wl maxpower maxp2ga0=0x1 maxp2ga1=0x2 maxp5ga0=0xff maxp5ga1=0xff` | `wl_phy_maxpower: fail to get maxpower` |
| `quiet` | Send an 802.11h quiet command.<br>`wl quiet <TBTTs until start>, <duration (in TUs)>, <offset (in TUs)>` | _needs args_ |
| `rm_rep` | Get current radio measurement report | **Unsupported** |
| `spect` | Get/Set 802.11h Spectrum Management mode. | `Off` |
| `tpc_lm` | Get current link margins. | _error_ |
| `tpc_mode` | Enable/disable AP TPC.<br>`wl tpc_mode <mode>` | `0` |
| `tpc_period` | Set AP TPC periodicity in secs.<br>`wl tpc_period <secs>` | `0` |

## Board, NVRAM and low-level hardware

Board configuration, SPROM contents and PCIe internals. Reads are harmless and occasionally informative — `srdump` prints the SPROM, `pavars`/`povars` the power amplifier calibration variables. The corresponding writes are the most dangerous commands in the entire set and are all Tier D.

| command | what it does | returns here |
|---|---|---|
| `caldump` | Dump calibration data and save it with calibration storage format.<br>`wl caldump <cal file name> to dump current calibration info to file` | _(silent)_ |
| `devpath` | print device path | **Unsupported** |
| `gpioout` | Set any GPIO pins to any value. Use with caution as GPIOs would be assigned to chipcommon<br>`gpiomask gpioval` | **Unsupported** |
| `mempool` | Get memory pool statistics | `Name           SZ      Max     Curr  HiWater   Failed ` |
| `nvotpw` | Write nvram to on-chip otp<br>`wl nvotpw file` | _(silent)_ |
| `nvset` | set an nvram variable | `nvset	set an nvram variable name=value (no spaces arou` |
| `overlay` | overlay virt_addr phy_addr size | `overlay	overlay virt_addr phy_addr size required args:` |
| `pavars` | Set/get temp PA parameters<br>`wl down` | **Unsupported** |
| `pcie_bus_tput` | Measure the pcie bus througput<br>`wl pcie_bus_tput -n 64` | `Failed to get stats. wl: Unsupported` |
| `pcieserdesreg` | g/set SERDES registers: dev offset [val] | `pcieserdesreg g/set SERDES registers: dev offset [val]` |
| `povars` | Set/get temp power offset<br>`wl down` | **Unsupported** |
| `rand` | Get a 2-byte Random Number from the MAC's PRNG<br>`wl rand` | **Unsupported** |
| `rdvar` | Read a named variable to the srom | `rdvar	Read a named variable to the srom` |
| `reinit` | Reinitialize device | _(silent)_ |
| `sc_chan` | Set current or configured channel: | **Unsupported** |
| `srchmem` | g/set ucode srch engine memory | `srchmem	g/set ucode srch engine memory` |
| `srcrc` | Get the CRC for input binary file | `srcrc	Get the CRC for input binary file` |
| `srdump` | print contents of SPROM to stdout | **Unsupported** |
| `txfifo_sz` | set/get the txfifo size; usage: wl txfifo_sz <fifonum> <size_in_bytes> | _needs args_ |
| `wrvar` | Write a named variable to the srom | `wrvar	Write a named variable to the srom` |

## Naming and identity strings

Cosmetic identity strings used by the vendor's own management tooling.

| command | what it does | returns here |
|---|---|---|
| `apname` | get AP name | **Unsupported** |
| `customvar1` | print the value of customvar1 in hex format | `0x00000000` |
| `staname` | get/set station name: | **Unsupported** |

## Other

Commands that do not group cleanly. `mac` and `macmode` implement the MAC address filter list. `tsf` reads the timing synchronisation function counter. `pwrstats` reports power-state statistics. `lazywds` and `protection_control` are legacy compatibility switches.

| command | what it does | returns here |
|---|---|---|
| `clear_radar_status` | Clear radar detection status | `Clear Radar Status` |
| `clmver` | Get version information for CLM data and tools | `API: 18.0 Data: 9.15.7 Compiler: 1.29.15 ClmImport: 1.` |
| `freqtrack` | Set Frequency Tracking Mode (0=Auto, 1=On, 2=OFF) | `0` |
| `ip_route_table` | Get/Set ip route table<br>`wl ip_route_tbl num_entries [{ip_addr1, mac_addr1}, ...]` | **Unsupported** |
| `lazywds` | Set or get "lazy" WDS mode (dynamically grant WDS membership to anyone). | `0` |
| `mac` | Set or get the list of source MAC address matches. | _(silent)_ |
| `macmode` | Set the mode of the MAC list. | `1` |
| `modesw_timecal` | wl modesw_timecal 0~1 for disable /enable | **Unsupported** |
| `protection_control` | Get/Set protection mode control alg.(0=always off, 1=monitor local association, 2=monitor overlapping BSS) | `2` |
| `pwrstats` | Get power usage statistics<br>`wl pwrstats [<type>] ...` | **Unsupported** |
| `send_nulldata` | Sed a null frame to the specified hw address | _error_ |
| `tsf` | set/get tsf register<br>`wl tsf [<high> <low>]` | **Unsupported** |

---

## Sources

Per-command descriptions are the vendor&#39;s own, from `wl -h <cmd>` in the shipped
binary. Where a command is long-standing across Broadcom drivers, the community
references below give fuller context and examples:

- [WikiDevi — DD-WRT wl command reference](https://wikidevi.wi-cat.ru/WikiDevi.Wi-Cat.RU:DD-WRT/Wl_command)
- [OpenWrt forum — Broadcom wl command set](https://forum.openwrt.org/t/broadcom-wl-command-set/2243)
- [wlu.c — open-source portion of the wl utility](https://github.com/allwinner-ics/lichee_linux-3.0/blob/master/modules/wifi/bcm40181/open-src/src/wl/exe/wlu.c)
- [Broadcom wireless — ArchWiki](https://wiki.archlinux.org/title/Broadcom_wireless)

Those describe older and mobile-oriented driver builds, so they cover a subset of
what this firmware exposes and occasionally differ in detail. Where they disagree
with `wl -h` on this box, trust the box.
