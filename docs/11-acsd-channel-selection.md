# Automatic channel selection (`acsd`)

`acsd` is Broadcom's auto channel selection daemon. It is separate from `bsd`,
the band steering daemon — `bsd` decides *which radio* a client uses, `acsd`
decides *which channel* each radio sits on. They share nothing but nvram.

    acs_ifnames=eth6 eth7 eth8

## Only one radio actually hops, and one flag decides it

The setting that matters is per-radio and easy to miss:

    wl0_acs_fcs_mode=1     <- 2.4 GHz
    wl1_acs_fcs_mode=0     <- 5 GHz-1
    wl2_acs_fcs_mode=0     <- 5 GHz-2

FCS mode is the continuous re-selection engine. With it off, `acsd` picks a
channel at interface-up and leaves it there. With it on, the radio is
re-evaluated forever.

On stock firmware here it ships **on for 2.4 GHz and off for both 5 GHz
radios** — which is why the 5 GHz radios hold one channel for weeks while 2.4
GHz wanders. If you are wondering why only one band moves, this is why.

## The cadence

    wl0_acs_cs_scan_timer=900

900 seconds. Every 15 minutes `acsd` re-evaluates and logs a decision:

    acsd: selected channel spec: 0x1006 (6)
    acsd: acs_set_chspec: 0x1006 (6) for reason APCS_CSTIMER

`APCS_CSTIMER` is that periodic timer; `APCS_INIT` is the boot-time pick. Not
every evaluation causes a move — observed here was roughly 22 actual changes in
a day, so about one evaluation in four.

Related knobs, all per-radio:

| variable | default | meaning |
|---|---|---|
| `acs_cs_scan_timer` | 900 | seconds between re-evaluations |
| `acs_chan_dwell_time` | 70 | minimum time on a channel |
| `acs_chan_flop_period` | 70 | anti-flap guard |
| `acs_boot_only` | 0 | if 1, select once at boot and stop |
| `acs_excl_chans` | *(empty)* | chanspecs `acsd` may not choose |
| `acs_use_escan` | 1 | use escan for the survey |

## It is not restricted to 1 / 6 / 11

    acs_2g_ch_no_restrict=1
    acs_no_restrict_align=1

With these set, `acsd` will select overlapping 2.4 GHz channels. Observed
selections across one day included 1, 3, 6, 7, 8 and 11 — the even and
in-between channels are not a bug, they are this policy.

Whether that is good depends on your neighbourhood. Overlapping channels can be
the right answer in a quiet band and are usually the wrong one in a busy one,
because a partially-overlapping AP interferes without being able to defer to you
politely the way a co-channel one does.

## Auditing what your radio can actually see

`acsd` keeps a scan cache you can read without transmitting anything:

    wl -i eth6 escanresults

Tally the neighbours by primary channel:

    wl -i eth6 escanresults </dev/null \
      | awk '/Primary channel:/{print $3}' | sort -n | uniq -c

And score each channel including adjacent-channel spill, since a 2.4 GHz AP
splatters roughly +/-2 channels:

    wl -i eth6 escanresults </dev/null | awk '
      /Primary channel:/{for(i=$3-2;i<=$3+2;i++) if(i>=1&&i<=13) c[i]++}
      END{for(i=1;i<=13;i++) printf "ch %-3s %s\n", i, c[i]+0}'

A real result from this box, anonymised — 9 APs visible:

    ch 1    0
    ch 2    0
    ch 3    1
    ch 5    4     <- 1 AP at -51 dBm
    ch 7    5     <- 3 APs, strongest -45 dBm
    ch 9    4
    ch 11   4
    ch 12   3     <- 3 APs, strongest -40 dBm

`acsd`'s next move put the radio on **channel 7** — the most congested channel
available — while channels 1 and 2 were completely clear. One snapshot is not a
proof of systematic misbehaviour, and its survey may legitimately have sampled
while those APs were idle. But it is worth checking rather than assuming the
daemon knows best.

Reading the decision policy itself (`wl0_acs_pol`, a twelve-field weight vector)
would settle it. That is not decoded here.

## If you want to change it

Least invasive first:

**Constrain the choice, keep adaptation.** Set `acs_excl_chans` to the
chanspecs you never want selected. `acsd` keeps adapting, but only within
channels you consider acceptable.

**Stop mid-flight hopping, keep boot-time selection.** Set `wl0_acs_fcs_mode=0`
(or `acs_boot_only=1`). The radio is chosen once and then left alone — but you
inherit whatever it picked at boot until the next reboot.

**Slow it down.** Raise `acs_cs_scan_timer`. Reduces churn without improving the
quality of the choices.

**Pin it.** Set a fixed channel in the GUI. Deterministic and disruption-free,
at the cost of never adapting — worth re-checking the neighbourhood occasionally.

Every one of these is an nvram change, so **`nvram commit` afterwards** or it
reverts on the next reboot. See `99-gotchas.md`.

## What it costs to leave it alone

Each channel change interrupts associated clients. 2.4 GHz tends to carry the
IoT and legacy devices with the worst roaming behaviour, so they are the ones
least able to follow gracefully. Against that, the band is often nearly empty on
a tri-band box where everything modern has been steered to 5 GHz — in which case
the hopping costs little and the adaptation is free insurance.

Measure how many clients are actually on 2.4 GHz before deciding it matters:

    wl -i eth6 assoclist | grep -c assoclist
