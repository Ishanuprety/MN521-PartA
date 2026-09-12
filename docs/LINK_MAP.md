# LINK_MAP — raw live export

**This is the unedited export from the live GNS3 project.** It is kept as-is because it
is the record of what is actually cabled, which is what screenshots will show.

For the interpreted, canonical topology — link IDs `L1`–`L50`, addressing, VLANs, OSPF
areas and costs — use [`TOPOLOGY.md`](TOPOLOGY.md) §3. Where the two differ, this file
describes the lab as found and `TOPOLOGY.md` describes the lab as designed.

Three differences are deliberate and important:

| Difference | Detail |
|------------|--------|
| `ISP-Cloud` and `WAN-Cloud` are missing from this export | Links 18 and 24 appear as direct router-to-router adjacencies. The hubs sit mid-path and some exports omit transparent L2 nodes as named endpoints. Inserting them splits those two links into four, which is how the 48 rows below reconcile to the 50 links in `TOPOLOGY.md` §6 |
| Three links must be **deleted** | Rows 1, 4 and 5 each close a Layer 2 loop. See the annotation below and `REVIEW_FINDINGS.md` R-02 |
| Three links are cabled but **held down** | Rows 11, 13 and 17 terminate on router ports that are administratively shut by design, not by omission |

Adapter N on a dynamips node = `FastEthernetN/0`.

| # | Node A | Interface | Node B | Interface | Role |
|---|--------|-----------|--------|-----------|------|
| 1 | SW-HQ-1 | Eth7 | SW-HQ-2 | Eth0 |  |
| 2 | SW-HQ-1 | Eth1 | PC1 | e0 |  |
| 3 | SW-HQ-2 | Eth1 | PC2 | e0 |  |
| 4 | SW-DC-1 | Eth7 | SW-DC-2 | Eth0 |  |
| 5 | SW-BR-1 | Eth7 | SW-BR-2 | Eth0 |  |
| 6 | SW-BR-1 | Eth1 | PC3 | e0 |  |
| 7 | SW-BR-2 | Eth1 | PC4 | e0 |  |
| 8 | HQ-CORE | Fa1/0 | DC-EDGE | Fa0/0 | Primary WAN HQ↔DC /30 10.255.0.0 |
| 9 | HQ-CORE | Fa2/0 | HQ-DIST | Fa0/0 | HQ core↔dist /30 10.255.0.8 |
| 10 | DC-EDGE | Fa1/0 | BR-EDGE | Fa0/0 | Primary WAN DC↔BR /30 10.255.0.4 |
| 11 | HQ-DIST | Fa1/0 | SW-HQ-1 | Eth0 |  |
| 12 | SW-HQ-1 | Eth2 | AUTO-SRV | eth0 |  |
| 13 | DC-EDGE | Fa2/0 | SW-DC-1 | Eth0 |  |
| 14 | SW-DC-1 | Eth1 | DNS | eth0 |  |
| 15 | SW-DC-1 | Eth2 | NTP | eth0 |  |
| 16 | SW-DC-1 | Eth3 | Syslog | eth0 |  |
| 17 | BR-EDGE | Fa1/0 | SW-BR-1 | Eth0 |  |
| 18 | Internet-NAT | nat0 | FW-EDGE | Fa0/0 | Internet edge (export direct; design may insert ISP-Cloud) |
| 19 | FW-EDGE | Fa1/0 | HQ-CORE | Fa0/0 | FW↔HQ /30 10.255.0.16 |
| 20 | FW-EDGE | Fa2/0 | SW-DMZ-1 | Eth0 | DMZ trunk VLAN60 |
| 21 | SW-DMZ-1 | Eth1 | WEB-SRV | eth0 |  |
| 22 | SW-DMZ-1 | Eth2 | APP-SRV | eth0 |  |
| 23 | SW-DMZ-1 | Eth3 | PC-DMZ | e0 |  |
| 24 | HQ-CORE | Fa3/0 | BR-EDGE | Fa2/0 | Backup WAN (export direct; design via WAN-Cloud) /30 10.255.0.20 |
| 25 | HQ-DIST | Fa2/0 | SW-HQ-DIST | Eth0 |  |
| 26 | SW-HQ-DIST | Eth2 | SW-HQ-2 | Eth2 |  |
| 27 | SW-HQ-DIST | Eth3 | SW-HQ-3 | Eth0 |  |
| 28 | SW-HQ-3 | Eth1 | PC5 | e0 |  |
| 29 | DC-EDGE | Fa3/0 | SW-DC-CORE | Eth0 |  |
| 30 | SW-DC-CORE | Eth1 | SW-DC-1 | Eth6 |  |
| 31 | SW-DC-CORE | Eth2 | SW-DC-2 | Eth6 |  |
| 32 | SW-DC-CORE | Eth3 | SW-DC-3 | Eth0 |  |
| 33 | SW-DC-3 | Eth1 | FILE-SRV | eth0 |  |
| 34 | SW-BR-DIST | Eth1 | SW-BR-1 | Eth6 |  |
| 35 | SW-BR-DIST | Eth2 | SW-BR-2 | Eth6 |  |
| 36 | SW-BR-DIST | Eth3 | SW-BR-3 | Eth0 |  |
| 37 | SW-BR-3 | Eth1 | PC6 | e0 |  |
| 38 | SW-BR-1 | Eth3 | PC7 | e0 |  |
| 39 | SW-HQ-DIST | Eth1 | SW-HQ-1 | Eth4 |  |
| 40 | BR-EDGE | Fa3/0 | SW-BR-DIST | Eth0 |  |
| 41 | SW-HQ-1 | Eth5 | MGMT-SW | Eth0 |  |
| 42 | MGMT-SW | Eth1 | JUMP-SRV | eth0 |  |
| 43 | SW-HQ-DIST | Eth5 | SW-HQ-4 | Eth0 |  |
| 44 | SW-HQ-4 | Eth1 | PC8 | e0 |  |
| 45 | SW-DC-CORE | Eth5 | SW-DC-4 | Eth0 |  |
| 46 | SW-DC-4 | Eth1 | MON-SRV | eth0 |  |
| 47 | SW-BR-DIST | Eth5 | SW-BR-4 | Eth0 |  |
| 48 | SW-BR-4 | Eth1 | PC9 | e0 |  |

## Annotation — rows needing action

### Rows to DELETE — each closes a Layer 2 loop

| Row | Link | Loop closed | Why it must go |
|----:|------|-------------|----------------|
| 1 | `SW-HQ-1 Eth7` ↔ `SW-HQ-2 Eth0` | with rows 26 and 39 via `SW-HQ-DIST` | The GNS3 built-in switch has **no STP**, so nothing breaks the loop |
| 4 | `SW-DC-1 Eth7` ↔ `SW-DC-2 Eth0` | with rows 30 and 31 via `SW-DC-CORE` | as above |
| 5 | `SW-BR-1 Eth7` ↔ `SW-BR-2 Eth0` | with rows 34 and 35 via `SW-BR-DIST` | as above |

Deleting these disconnects nothing: `SW-HQ-2` keeps row 26, `SW-DC-2` keeps row 31 and
`SW-BR-2` keeps row 35, each an uplink to its aggregation switch. A loop here presents
as the whole GNS3 project becoming unresponsive rather than as an error, which is why
it went unnoticed. Procedure: [`APPLY_STEPS.md`](APPLY_STEPS.md) §3.

### Rows cabled but held administratively DOWN — by design

| Row | Link | Router port state |
|----:|------|-------------------|
| 11 | `HQ-DIST Fa1/0` ↔ `SW-HQ-1 Eth0` | `shutdown` — `SW-HQ-1` is reached via `SW-HQ-DIST` (row 39) instead |
| 13 | `DC-EDGE Fa2/0` ↔ `SW-DC-1 Eth0` | `shutdown` — `SW-DC-1` is reached via `SW-DC-CORE` (row 30) |
| 17 | `BR-EDGE Fa1/0` ↔ `SW-BR-1 Eth0` | `shutdown` — `SW-BR-1` is reached via `SW-BR-DIST` (row 34) |

These are pre-cabled standby paths: if an aggregation switch fails, bringing up the
router port and moving the VLAN subinterfaces restores that access switch without
recabling. **Do not delete them, and do not `no shutdown` them** — either would create
the second loop, between a router's two attachments to the same access switch.

### Rows where the transit hub is not shown

| Row | Export shows | Actually traverses | Addressing |
|----:|--------------|--------------------|------------|
| 18 | `Internet-NAT nat0` ↔ `FW-EDGE Fa0/0` | `Internet-NAT` → **`ISP-Cloud`** → `FW-EDGE Fa0/0` | DHCP on `Fa0/0` (NAT outside) |
| 24 | `HQ-CORE Fa3/0` ↔ `BR-EDGE Fa2/0` | `HQ-CORE Fa3/0` → **`WAN-Cloud`** → `BR-EDGE Fa2/0` | `10.255.0.20/30` — `.21` and `.22` |

Both hubs are functional path segments, not decoration: `ISP-Cloud` models the ISP
handoff and `WAN-Cloud` models a carrier Ethernet backup service. Because an Ethernet
hub is transparent at Layer 2 and holds no address, the IP subnet spans it and OSPF
forms a single adjacency across it — so **inserting a hub requires no configuration
change on either router**. The `/30` mask does the real work of keeping the segment
point-to-point: with only two host addresses, no third device can be addressed onto a
shared segment that would otherwise flood to it.

### Verify the current wiring

`scripts/apply_on_mac.py` writes a fresh `LINK_MAP_LIVE.md` each run. Diff it against
this file after the deletions in `APPLY_STEPS.md` §3 to confirm the topology matches
[`TOPOLOGY.md`](TOPOLOGY.md) §3 — 44 forwarding links plus 3 held-down standby links.
