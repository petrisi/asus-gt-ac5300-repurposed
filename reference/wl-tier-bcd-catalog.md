# Tier B, C and D command catalogue

The 160 `wl` commands that are **not** safe to call blindly, with what each one
does and what happens if you run it.

Unlike `wl-tier-a-catalog.md`, **none of these were executed.** Only `wl -h <cmd>`
was called, which prints help without issuing the command. That is the whole point
of the tier: Tier A is documented by observation, B/C/D by reading.

| tier | | count |
|---|---|---|
| **B** | a bare call performs an action | 72 |
| **C** | transmits, or needs arguments | 42 |
| **D** | persistent / regulatory / calibration | 46 |

See `docs/10-wl-commands.md` for how the tiers are derived.


## Tier B — a bare call performs an action

These break the get/set convention that makes the rest of `wl` safe to explore.
`wl down` does not report the down state; it takes the radio down. **Exclude every
command here from any automated sweep.**

Most are counter resets and merely annoying. The first group below is the one that
interrupts service.

### Service-affecting — clients will drop

| command | what it does | if you run it |
|---|---|---|
| `authorize` | restrict traffic to 802.1X packets until 802.1X authorization succeeds | Grants 802.1X authorisation for a station. |
| `deauthenticate` | a STA from the AP with optional reason code (AP ONLY) | Deauthenticates a station from the AP. |
| `deauthorize` | do not restrict traffic to 802.1X packets until 802.1X authorization succeeds | Revokes 802.1X authorisation for a station. |
| `dfs_ap_move` | Move the AP interface to dfs channel specified: | Moves the AP to a DFS channel. Service interruption plus a CAC wait. |
| `disassoc` | Disassociate from the current BSS/IBSS. | Disassociates from the current BSS. |
| `down` | reset and mark adapter down (disabled) | Takes the radio down. Clients drop. |
| `escan` | Start an escan. | Starts an extended scan. |
| `escanabort` | Abort an escan. | Aborts an extended scan in progress. |
| `interface_create` | create an AP/STA interface on a WLC instance that receives the IOVAR<br>`wl interface_create ap/sta [MAC-address]` | Creates a virtual AP or STA interface. |
| `interface_remove` | Deletes the interface on which this command is received | Removes a virtual interface. |
| `join` | Join a specified network SSID.<br>`join <ssid> [key <0-3>:xxxxx] [imode bss/ibss] [amode open/shared/openshared/wpa/wpa` | Attempts to associate to a network as a client. |
| `out` | mark adapter down but do not reset hardware(disabled) | Marks the adapter down without resetting hardware. Clients drop. |
| `reboot` | Reboot platform | Reboots the platform. |
| `restart` | Restart driver. Driver must already be down. | Restarts the driver. All radios drop. |
| `scan` | Initiate a scan. | Starts a scan. Interrupts AP service on that radio. |
| `scanabort` | Abort a scan. | Aborts a scan in progress. |
| `tkip_countermeasures` | Enable or disable TKIP countermeasures (TKIP-enabled AP only) | Triggers TKIP countermeasures: disconnects clients for 60s. |
| `up` | reinitialize and mark adapter up (operational) | Reinitialises and brings the radio up. |

### Starts or stops a background operation

| command | what it does | if you run it |
|---|---|---|
| `anqpo_start_query` | start ANQP query to peer(s)<br>`anqpo_start_query <channel> <xx:xx:xx:xx:xx:xx>` | Starts or stops a discovery/ranging operation. |
| `anqpo_stop_query` | stop ANQP query<br>`anqpo_stop_query` | Starts or stops a discovery/ranging operation. |
| `escan_event_check` | Listen and prints the escan events from the dongle | Acts on a bare call. |
| `ota_loadtest` | picks up ota_test.txt if file is not given<br>`ota_loadtest [filename]` | Manufacturing over-the-air load test. Transmits. |
| `ota_stream` | wl ota_stream ota_sync<br>`wl ota_stream start : to start the test` | Manufacturing over-the-air stream test. Transmits. |
| `ota_teststatus` | ota_teststatus<br>`otatest_status Displays current running test details otatest_status n displays test ` | Acts on a bare call. |
| `ota_teststop` | ota_teststop<br>`ota_teststop` | Stops an over-the-air test. |
| `p2po_find` | start discovery | Starts or stops a discovery/ranging operation. |
| `p2po_find_config` | set/get the parameters for the p2po_find command<br>`p2po_find_config <flags> <home_time> <social channels>` | Starts or stops a discovery/ranging operation. |
| `p2po_listen` | start/get listen<br>`p2po_listen [period(ms)] [interval(ms)]` | Starts or stops a discovery/ranging operation. |
| `p2po_listen_channel` | set listen channel to channel 1, 6, 11, or default<br>`p2po_listen_channel <1/6/11/0>` | Starts or stops a discovery/ranging operation. |
| `p2po_stop` | stop both P2P listen and P2P device discovery offload<br>`p2po_stop` | Starts or stops a discovery/ranging operation. |
| `pkteng_start` | start packet engine tx usage: wl pkteng_start <xx:xx:xx:xx:xx:xx> <tx/txwithack> [(async)/sync] [ipg] [len] [nframes | Starts the packet engine transmitting. Occupies the channel. |
| `pkteng_stats` | packet engine stats; usage: wl pkteng_stats | Acts on a bare call. |
| `pkteng_stop` | stop packet engine; usage: wl pkteng_stop <tx/rx> | Stops the packet engine. |
| `proxd_find` | Start Proximity Detection | Starts or stops a discovery/ranging operation. |
| `proxd_stop` | Stop Proximity Detection | Starts or stops a discovery/ranging operation. |
| `seq_delay` | Driver should spin for the indicated amount of time. | Acts on a bare call. |
| `seq_error_index` | Used to retrieve the index (starting at 1) of the command that failed within a batch | Acts on a bare call. |
| `seq_start` | Initiates command batching sequence. Subsequent IOCTLs will be queued until | Acts on a bare call. |
| `seq_stop` | Defines the end of command batching sequence. Queued IOCTLs will be executed. | Acts on a bare call. |

### Clears counters or cached state

| command | what it does | if you run it |
|---|---|---|
| `ampdu_clear_dump` | clear ampdu counters | Clears counters or cached state. |
| `arp_hostip_clear` | Clear all host-ip addresses | Clears counters or cached state. |
| `arp_stats_clear` | Clear ARP offload statistics | Clears counters or cached state. |
| `arp_table_clear` | Clear arp cache | Clears counters or cached state. |
| `drift_stats_reset` | Reset drift statistics | Clears counters or cached state. |
| `escanresults` | Start escan and display results. | Acts on a bare call. |
| `iscan_c` | Continue an incremental scan. | Acts on a bare call. |
| `iscan_s` | Initiate an incremental scan. | Acts on a bare call. |
| `iscanresults` | Return results from last iscan. Specify a buflen (max 8188) | Acts on a bare call. |
| `join_pref` | Set/Get join target preferences. | Acts on a bare call. |
| `nar_clear_dump` | Clear non-aggregated regulation counters | Clears counters or cached state. |
| `nd_hostip_clear` | Clear all host-ip addresses | Clears counters or cached state. |
| `nd_status_clear` | Clear neighbor discovery status | Clears counters or cached state. |
| `ns_hostip_clear` | Clear all ns-ip addresses | Clears counters or cached state. |
| `pfnclear` | Clear the preferred network list | Clears counters or cached state. |
| `pkt_filter_clear_stats` | Clear packet filter statistic counter values.<br>`wl pkt_filter_clear_stats <id>` | Clears counters or cached state. |
| `reset_cnts` | Clear driver counter values | Clears counters or cached state. |
| `reset_d11cnts` | reset 802.11 MIB counters | Clears counters or cached state. |
| `scan_channel_time` | Get/Set scan channel time | Acts on a bare call. |
| `scan_home_time` | Get/Set scan home channel dwell time | Acts on a bare call. |
| `scan_nprobes` | Get/Set scan parameter for number of probes to use per channel scanned | Acts on a bare call. |
| `scan_passive_time` | Get/Set passive scan channel dwell time | Acts on a bare call. |
| `scan_ps` | Get/Set scan power optimization enable/disable | Acts on a bare call. |
| `scan_unassoc_time` | Get/Set unassociated scan channel dwell time | Acts on a bare call. |
| `scancache_clear` | clear the scan cache | Clears counters or cached state. |
| `scanmac` | Configure scan MAC using subcommands: | Acts on a bare call. |
| `scanresults` | Return results from last scan. | Acts on a bare call. |
| `scansuppress` | Suppress all scans for testing. | Acts on a bare call. |
| `toe_stats_clear` | Clear checksum offload statistics | Clears counters or cached state. |
| `trf_mgmt_filters_clear` | Clears all traffic management filters.<br>`wl trf_mgmt_filters_clear` | Clears counters or cached state. |
| `trf_mgmt_stats_clear` | Clears traffic management statistics.<br>`wl trf_mgmt_stats_clear` | Clears counters or cached state. |
| `upgrade` | Upgrade the firmware on an embedded device | Acts on a bare call. |
| `vasip_counters_clear` | clear vasip counters | Clears counters or cached state. |


## Tier C — transmits, or needs arguments

Running these bare is usually harmless — they print usage — but with arguments they
put frames on the air or act on a specific client. Two are directly useful for
experimenting with band steering: `wnm_bsstrans_req` sends the same 802.11v request
the steering daemon uses, and the `rrm_*` family asks a client to perform an 802.11k
measurement and report back.

Transmitting is a deliberate act. Know which client you are aiming at.

### Transmits a frame

| command | what it does | if you run it |
|---|---|---|
| `actframe` | Send a Vendor specific Action frame to a channel<br>`wl actframe <Dest Mac Addr> <data> channel dwell-time <BSSID>` | Transmits a vendor-specific action frame. |
| `measure_req` | Send an 802.11h measurement request.<br>`wl measure_req <type> <target MAC addr>` | Transmits a request frame. |
| `rm_req` | Request a radio measurement of type basic, cca, or rpi | Transmits a request frame. |
| `rrm_bcn_req` | send 11k beacon measurement request<br>`wl rrm_bcn_req [bcn mode] [da] [duration] [random int] [channel] [ssid] [repetitions` | Transmits an 802.11k radio measurement request. |
| `rrm_chload_req` | send 11k channel load measurement request<br>`wl rrm_chload_req [regulatory] [da] [duration] [random int] [channel] [repetitions]` | Transmits an 802.11k radio measurement request. |
| `rrm_civic_req` | Send 802.11k Location Civic request frame<br>`wl rrm_civic_req [da] [repetitions] [locaton sbj] [location type] [siu] [si]` | Transmits an 802.11k radio measurement request. |
| `rrm_frame_req` | send 11k frame measurement request<br>`wl rrm_frame_req [regulatory] [da] [duration] [random int] [channel] [ta] [repetitio` | Transmits an 802.11k radio measurement request. |
| `rrm_lci_req` | Send 802.11k Location Configuration Information (LCI) request frame<br>`wl rrm_lci_req [da] [repetitions] [locaton sbj] [latitude resln] [longitude resln] [` | Transmits an 802.11k radio measurement request. |
| `rrm_lm_req` | send 11k link measurement request<br>`wl rrm_lm_req [da]` | Transmits an 802.11k radio measurement request. |
| `rrm_locid_req` | Send 802.11k Location Identifier request frame<br>`wl rrm_locid_req [da] [repetitions] [locaton sbj] [siu] [si]` | Transmits an 802.11k radio measurement request. |
| `rrm_nbr_req` | send 11k neighbor report measurement request<br>`wl rrm_nbr_req [ssid]` | Transmits an 802.11k radio measurement request. |
| `rrm_noise_req` | send 11k noise measurement request<br>`wl rrm_noise_req [regulatory] [da] [duration] [random int] [channel] [repetitions]` | Transmits an 802.11k radio measurement request. |
| `rrm_stat_req` | send 11k stat measurement request<br>`wl rrm_stat_req [da] [random int] [duration] [peer] [group id] [repetitions]` | Transmits an 802.11k radio measurement request. |
| `rrm_txstrm_req` | Send 802.11k Transmit Stream/Category measurement request frame<br>`wl rrm_txstrm_req [da] [random int] [duration] [repetitions] [peer mac] [tid] [bin0_` | Transmits an 802.11k radio measurement request. |
| `wnm_bsstq` | send 11v BSS transition management query<br>`wl wnm_bsstq [ssid]` | Requires arguments; may transmit. |
| `wnm_bsstrans_query` | send 11v BSS transition management query<br>`wl wnm_bsstrans_query [ssid]` | Requires arguments; may transmit. |
| `wnm_bsstrans_req` | send BSS transition management request frame with BSS termination included bit set<br>`wl wnm_bsstrans_req <reqmode> <tbtt> <dur> [unicast]` | Transmits an 802.11v BSS transition request to a client. |
| `wnm_tfsreq_add` | add one tfs request element and send tfs request frame<br>`wl wnm_tfsreq_add <tfs_id> <tfs_action_code> <tfs_subelem_id> <send>` | Modifies a driver-side list. Needs arguments. |
| `wnm_timbc_set` | Enable/disable TIM Broadcast. Station will send appropriate request if AP suport TIMBC<br>`wl wnm_timbc_set <interval> [<flags> [<min_rate> [<max_rate>]]]` | Requires arguments; may transmit. |
| `wowl_pkt` | Send a wakeup frame to wakup a sleeping STA in WAKE mode<br>`wl wowl_pkt <len> <dst ea / bcast / ucast <STA ea>>[ magic [<STA ea>] / net <offset>` | Transmits a wake-up frame. |

### Requires arguments to do anything

| command | what it does | if you run it |
|---|---|---|
| `ampdu_send_addba` | send addba to specified ea-tid; usage: wl ampdu_send_addba <tid> <ea> | Requires arguments; may transmit. |
| `ampdu_send_delba` | send delba to specified ea-tid; usage: wl ampdu_send_delba <tid> <ea> [initiator] | Requires arguments; may transmit. |
| `constraint` | Send an 802.11h Power Constraint IE<br>`wl constraint 1-255 db` | Requires arguments; may transmit. |
| `keep_alive` | Send specified "keep-alive" packet periodically.<br>`wl keep_alive <period> <packet>` | Requires arguments; may transmit. |
| `mfp_assoc` | send assoc<br>`wl mfp_assoc` | Requires arguments; may transmit. |
| `mfp_auth` | send auth<br>`wl mfp_auth` | Requires arguments; may transmit. |
| `mfp_deauth` | send bogus deauth<br>`wl mfp_dedauth` | Requires arguments; may transmit. |
| `mfp_disassoc` | send bogus disassoc<br>`wl mfp_disassoc` | Requires arguments; may transmit. |
| `mfp_reassoc` | send reassoc<br>`wl mfp_reassoc` | Requires arguments; may transmit. |
| `mfp_sa_query` | Send a sa query req/resp to a peer<br>`wl mfp_sa_query flag action id` | Requires arguments; may transmit. |
| `mkeep_alive` | Send specified "mkeep-alive" packet periodically.<br>`wl mkeep_alive <index0-3> <period> <packet>` | Requires arguments; may transmit. |
| `obss_coex_action` | send OBSS 20/40 Coexistence Mangement Action Frame<br>`wl obss_coex_action -i <1/0> -w <1/0> -c <channel list>` | Requires arguments; may transmit. |
| `p2po_wfds_advertise_del` | <hdl> the hdl specified in a previous p2po_wfds_advertise_add<br>`p2po_wfds_advertise_del <adv_hdl>` | Starts or stops a discovery/ranging operation. |
| `p2po_wfds_seek_add` | Set usage: p2po_wfds_seek_add <seek_hdl> <service_hash> <macaddr> <service_name> [service_info_req] | Starts or stops a discovery/ranging operation. |
| `p2po_wfds_seek_del` | delete a WFDS service to seek<br>`p2po_wfds_seek_del <seek_hdl>` | Starts or stops a discovery/ranging operation. |
| `pkt_filter_add` | Install a packet filter.<br>`wl pkt_filter_add <id> <polarity> <type> <offset> <bitmask> <pattern>` | Modifies a driver-side list. Needs arguments. |
| `powerindex` | Set the transmit power for A band(0-63). | Requires arguments; may transmit. |
| `rmc_txrate` | Set/Get a fixed transmit rate for the reliable multicast: | Requires arguments; may transmit. |
| `tclas_add` | add tclas frame classifier type entry<br>`wl tclas_add <user priority> <type> <mask> <...>` | Modifies a driver-side list. Needs arguments. |
| `tclas_del` | delete tclas frame classifier type entry<br>`wl tclas_del [<idx> [<len>]]` | Modifies a driver-side list. Needs arguments. |
| `trf_mgmt_filters_add` | Adds a traffic management filter.<br>`wl trf_mgmt_filter_add [dst_port src_port prot priority]` | Modifies a driver-side list. Needs arguments. |
| `txmcsset` | get Transmit MCS rateset for 11N device | Requires arguments; may transmit. |


## Tier D — do not touch

Writes here are persistent and several are irreversible. There is no undo, no revert
from backup, and in the OTP case no physical possibility of rewriting.

Reading most of them is harmless. They are grouped as do-not-touch because the read
and write forms differ by a single argument, and a typo is permanent.

**If you are reading this to decide whether to run one: do not.** The only
legitimate reason to use most of these is factory calibration with vendor tooling.

### Writes non-volatile storage — irreversible

| command | what it does | if you run it |
|---|---|---|
| `cis_source` | Display which source is used for the SDIO CIS | Reports where CIS data is read from. |
| `cisconvert` | Print CIS tuple for given name=value pair | Rewrites CIS format. Persistent. |
| `cisdump` | Display the content of the SDIO CIS source | Reads the CIS. The write forms sit one argument away. |
| `cisupdate` | Write a hex byte stream to specified byte offset to the CIS source (either SROM or OTP) | WRITES the CIS. Persistent. |
| `ciswrite` | Write specified <file> to the SDIO/PCIe CIS source (either SROM or OTP) Usage: ciswrite [-p/--pciecis] <file> | WRITES the CIS. Persistent. Can permanently misconfigure the radio. |
| `otpdump` | Dump raw otp | Dumps OTP contents. |
| `otpraw` | Read/Write raw data to on-chip otp<br>`wl otpraw <offset> <bits> [<data>]` | Raw OTP access. The write path is irreversible. |
| `otpstat` | Dump OTP status | Reports OTP status. |
| `otpw` | Write an srom image to on-chip otp<br>`wl otpw file` | WRITES OTP memory. One-time programmable: physically irreversible. |
| `srclear` | Clears first 'len' bytes of the srom, len in decimal or hex<br>`srclear <len>` | ERASES the start of the SPROM. Persistent and destructive. |
| `srwrite` | Write the srom: srwrite byteoffset value | WRITES the SPROM. Persistent. Holds calibration and identity. |

### Calibration data

| command | what it does | if you run it |
|---|---|---|
| `calload` | Download CAL data into a driver. Driver must be down.<br>`wl calload <cal file name> to download existing calibration data file` | Loads calibration data. |
| `olpc_anchoridx` | Get the saved tx power idx and temperature at the olpc anchor power level: | Open-loop power control anchor index. Calibration adjacent. |
| `phy_read_estpwrlut` | Read EstPwr LUT: wl phy_read_estpwrlut core | Reads the estimated power lookup table. |
| `phy_setrptbl` | populate the reciprocity compensation table based on SROM cal content<br>`wl phy_setrptbl` | Writes a PHY rate power table. |
| `phy_test_idletssi` | get idletssi for the given core; wl phy_test_idletssi corenum | Manufacturing idle TSSI test. |
| `phy_test_tssi` | wl phy_test_tssi val | Manufacturing TSSI test mode. |
| `phy_test_tssi_offs` | wl phy_test_tssi_offs val | Manufacturing TSSI offset test. |
| `phy_txiqcc` | Set/get the iqcc a, b values<br>`phy_txiqcc [a b]` | TX IQ calibration coefficients. |
| `phy_txlocc` | Set/get locc di dq ei eq fi fq values<br>`phy_txlocc [di dq ei eq fi fq]` | TX LO calibration coefficients. |
| `rpcalvars` | Set/get temp RPCAL parameters<br>`wl down` | Reads or writes RF power calibration variables. |
| `txcal_gainsweep` | start Gain Sweep for TX Cal: wl txcal_gainsweep <xx:xx:xx:xx:xx:xx> [ipg] [len] [nframes] [gidx_start:step:gidx_stop | Runs a TX calibration gain sweep. Rewrites calibration state. |
| `txcal_gainsweep_meas` | Get TSSI/PWR measurments from last TX Cal Gain Sweep: wl txcal_gainsweep_meas | TX calibration measurement pass. |
| `txcal_pwr_tssi_tbl` | Get the saved consolidated TSSI/PWR table: wl txcal_pwr_tssi_tbl <core> <chan> | Rewrites the TX power/TSSI table. Calibration data. |

### Regulatory and transmit limits

| command | what it does | if you run it |
|---|---|---|
| `autocountry_default` | Select Country Code for use with Auto Contry Discovery | Sets the default country for auto-country. |
| `clm_data_ver` | get CLM data version information | Reports the CLM data version. |
| `clmload` | Download CLM data into a driver. Driver must be down.<br>`wl clmload <clm blob file name>` | Loads CLM regulatory data. Changes what the radio may transmit. |
| `country` | Select Country Code for driver operational region | Changes the country/regulatory domain. Legal implications. |
| `country_ie_override` | To set/get country ie | Overrides the advertised country IE. |
| `regulatory` | Get/Set regulatory domain mode (802.11d). Driver must be down. | Changes 802.11d regulatory mode. Legal implications. |
| `sar_limit` | Set/Get sar_limit<br>`(set) sar_limit <2Gcore0 2Gcore1 2Gcore2 2Gcore3 5G[0]core0 5G[0]core1...>` | Sets SAR transmit limits. Regulatory and safety relevant. |

### Direct hardware access

| command | what it does | if you run it |
|---|---|---|
| `bmac_reboot` | Reboot BMAC | Reboots the MAC core. |
| `diag` | diag testindex(1-interrupt, 2-loopback, 3-memory, 4-led); precede by 'wl down' and follow by 'wl up' | Runs hardware diagnostics (interrupt, loopback, memory). |
| `dongleset` | Enable uart driver | Sets dongle-level parameters. |
| `phy_afeoverride` | g/set AFE override | Overrides the analogue front end. |
| `phy_vcore` | get virtual core related capabilities | PHY core voltage control. |
| `phytable` | Set/get table element of a table with the given ID at the given offset<br>`wl phytable table_id offset width_of_table_element [table_element]` | Direct PHY table access. |
| `radioreg` | Get/Set a radio register: | Direct radio register access. Undefined behaviour if written blind. |
| `shmem` | Get/Set a shared memory location: | Direct shared memory access. |
| `shmemx` | Get/Set a shared memory location of PSMX: | Direct PSMX shared memory access. |
| `ucantdiv` | Enable/disable ucode antenna diversity (1/0 or on/off) | Microcode antenna diversity control. |

### Identity and manufacturing data

| command | what it does | if you run it |
|---|---|---|
| `manfinfo` | show chip package info in OTP | Manufacturing information. |
| `nvram_get` | get the value of an nvram variable | Reads a driver NVRAM variable. |
| `nvram_source` | Display which source is used for nvram | Reports where NVRAM is sourced from. |
| `perm_etheraddr` | Get the permanent address from NVRAM | Reads the permanent MAC address burned into the device. |
| `revinfo` | get hardware revision information | Hardware revision information. |

---

## Sources

Descriptions are the vendor&#39;s own, from `wl -h <cmd>` in the shipped binary.
The consequence column is this project&#39;s assessment, derived from the help text and
from what the command is by nature — it is **not** the result of running them.

- [WikiDevi — DD-WRT wl command reference](https://wikidevi.wi-cat.ru/WikiDevi.Wi-Cat.RU:DD-WRT/Wl_command)
- [OpenWrt forum — Broadcom wl command set](https://forum.openwrt.org/t/broadcom-wl-command-set/2243)
- [wlu.c — open-source portion of the wl utility](https://github.com/allwinner-ics/lichee_linux-3.0/blob/master/modules/wifi/bcm40181/open-src/src/wl/exe/wlu.c)
