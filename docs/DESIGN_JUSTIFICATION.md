# Part A — Design Justification

Why the network is built this way. This document addresses the *Technical
Justification* criterion, and supplies the argument behind the *Topology & Design*
criterion, by explaining each decision, the alternatives considered, and the
trade-offs accepted.

Addressing is in [`IP_ADDRESSING.md`](IP_ADDRESSING.md); cabling in
[`TOPOLOGY.md`](TOPOLOGY.md); per-node roles in
[`NODE_INVENTORY.md`](NODE_INVENTORY.md); defects found during review in
[`REVIEW_FINDINGS.md`](REVIEW_FINDINGS.md).

---

## 1. Architecture

Four zones connected by a routed OSPF backbone, with a dedicated security boundary
at the Internet edge.

| Zone | Role | OSPF area | Gateway | Trust |
|------|------|-----------|---------|-------|
| Internet edge / DMZ | Perimeter enforcement, PAT, Internet-facing services | 0 | `FW-EDGE` | untrusted / semi-trusted |
| WAN backbone | Site interconnect only, no end hosts | 0 | all five routers | trusted |
| Headquarters | Users, corporate, management, automation | 10 | `HQ-DIST` | trusted |
| Data Centre | Shared infrastructure and internal services | 20 | `DC-EDGE` | trusted |
| Branch Office | Staff plus an isolated guest network | 30 | `BR-EDGE` | trusted / untrusted guest |

### 1.1 Why a dedicated edge router

The obvious alternative — and the design's own earlier revision — put PAT, the
perimeter filter, default-route origination and the area 0 backbone hub all on
`HQ-CORE`. Separating them onto `FW-EDGE` buys three things:

1. **A blast radius boundary.** `HQ-CORE` has four adjacencies and is the busiest
   change surface in the topology. A change to the *backbone* should not be able to
   modify the *Internet edge*, and on a single device it can.
2. **A zone where an inbound session can terminate.** Without a separate edge there
   is no DMZ, so an Internet-facing service would have to live on an internal VLAN or
   be port-forwarded into the user population. With `FW-EDGE`, the DMZ is the only
   place an inbound-initiated flow lands, and it lands somewhere that cannot reach
   inward.
3. **Single-owner semantics for the default route.** One device originates
   `0.0.0.0/0`, so `show ip route 0.0.0.0` anywhere in the domain is unambiguous
   evidence of where Internet traffic leaves. The earlier revision had two
   originators and produced source-dependent Internet behaviour
   ([R-04](REVIEW_FINDINGS.md#r-04)).

The cost is one more router — roughly 150 MB of the 4 GB GNS3 VM. §6 explains why
that budget was spent here rather than on emulated switches.

### 1.2 Why the Data Centre is the WAN transit point

The primary WAN is a chain, `FW-EDGE — HQ-CORE — DC-EDGE — BR-EDGE`, rather than a
direct HQ-to-Branch link. Two reasons:

- **Traffic locality.** Most Branch traffic targets shared services — DNS, NTP,
  syslog, the file share, and in Part B the Ansible targets. Putting the Data Centre
  in the middle makes that one hop, not two.
- **One chokepoint for policy.** Every Branch packet toward the Data Centre or HQ
  crosses `DC-EDGE Fa1/0`, which is where the second guest-containment ACL is
  enforced. One interface carries policy for a whole remote site.

The honest cost is that `DC-EDGE` becomes a single point of failure for the Branch —
which is exactly what the redundant WAN addresses.

### 1.3 Why the redundant WAN is deliberately *not* equal-cost

`WAN-Cloud` gives `BR-EDGE` a second uplink to `HQ-CORE` on `10.255.0.20/30`. Every
link in the topology is FastEthernet, so the default OSPF cost is a uniform 1
(`10^8 / 10^8`), which makes the direct Branch-to-HQ path **one hop** against **two**
through the Data Centre. Left at defaults, OSPF prefers the new link, and all Branch
traffic abandons the `DC-EDGE` enforcement point.

`ip ospf cost 50` on both ends inverts the preference: the Data Centre path costs 2
and wins; the backup costs 50 and is used only when the primary fails.

Equal-cost multipath was considered and rejected. It would split Branch traffic
roughly evenly over both links, which halves the effective coverage of any
per-interface ACL counter and makes packet paths non-deterministic — a poor property
in a lab whose security evidence *is* per-interface hit counts. A deliberately less
preferred backup gives resilience without giving up determinism.

The design lesson worth stating: adding a redundant path silently invalidated a
security control that depended on topology. The fix was both cost engineering **and**
applying `ACL_WAN_BR_IN` on `HQ-CORE Fa3/0` as well, so policy follows the packet
rather than the path ([R-05](REVIEW_FINDINGS.md#r-05)).

### 1.4 What the two hubs are for

`ISP-Cloud` and `WAN-Cloud` are Ethernet hubs — transparent at Layer 2, holding no
address. They model the provider handoff and a carrier Ethernet service as distinct
segments, so the perimeter is a boundary between two *named networks* rather than a
cable, which is how a real ISP demarcation is documented.

Because a hub floods rather than forwards, the `/30` mask does real work: only two
host addresses exist, so no third device can be addressed onto a shared segment even
though the hub would happily flood to it. Inserting a hub requires no configuration
change on either router, which is worth being able to explain — the subnet spans the
hub and OSPF forms a single adjacency across it.

One consequence is accepted: OSPF treats the segment as broadcast and elects a
DR/BDR, which a true point-to-point link would not. `ip ospf network point-to-point`
on both ends would suppress the election and the type-2 network LSA. It is left at
the default so the election is visible in `show ip ospf neighbor` as evidence; the
optimisation is noted as a production improvement.

---

## 2. Layer 2 and inter-VLAN routing

### 2.1 Router-on-a-stick, and its limits

Each site router terminates one 802.1Q trunk carrying every VLAN for that site, with
a subinterface per VLAN providing the gateway. This is the only inter-VLAN mechanism
available: the GNS3 built-in switch has no SVI capability, and there is no RAM budget
for emulated Layer 3 switches.

The limitation should be stated plainly rather than glossed over. All inter-VLAN
traffic for a site shares one 100 Mbit/s trunk, and the router CPU forwards every
inter-VLAN packet — so the trunk is both a bandwidth and a latency chokepoint. In
production the remedy is a Layer 3 switch doing SVI routing in hardware; the
addressing and OSPF configuration transfer unchanged, which is a property of the
design worth having.

### 2.2 Two-tier switching, and why the density is justified

Each site has an aggregation switch fanning out to access switches. That is more
switches than the brief's minimum of six, so the density has to earn its place:

- **The trunk fans out once.** `HQ-DIST` spends one physical port; `SW-HQ-DIST`
  turns it into four access switches. Adding a fifth access block costs a switch, not
  a router port — and router ports are the scarce resource.
- **Fault domains.** In the Data Centre, `DNS`/`NTP`/`SYSLOG` (management plane),
  `FILE-SRV` (user service) and `MON-SRV` (observability and break-glass access) are
  on three different access switches. On one switch, a single failure would remove
  name resolution, time, logging, file access *and* the ability to observe any of it
  simultaneously.
- **The staff/guest split is physical, not just logical.** Branch staff are on
  `SW-BR-1`/`SW-BR-3` and guests on `SW-BR-2`/`SW-BR-4`. This is what makes the
  isolation evidence meaningful: `PC3` and `PC4` are not merely tagged differently,
  they are on different access switches converging on one enforcement point.
- **`MGMT-SW` is reached over an access port, not a trunk.** It carries only VLAN 99,
  so the segment is physically incapable of carrying a user VLAN — a mis-set trunk
  cannot leak one onto the management island.

### 2.3 VLAN 1 unused, everything tagged

Every data VLAN is tagged and VLAN 1 carries nothing. This removes the
native-VLAN mismatch class of fault entirely: a router subinterface accepts only
tagged frames, so anything arriving untagged is discarded. It also makes the most
common build error fail *loudly* — a GNS3 access port left at its default of
`1 / access` leaves the host with no DHCP lease, rather than silently joining a live
VLAN.

The value of that discipline was demonstrated during review: `SW-DMZ-1`'s trunk had
native VLAN 60, so DMZ frames left the trunk untagged and the DMZ gateway discarded
all of them. Because every other trunk used native VLAN 1, the outlier was
identifiable as a typo ([R-13](REVIEW_FINDINGS.md#r-13)).

### 2.4 No spanning tree: a design constraint, not an omission

The built-in switch has no STP, no port security, no LACP and no trunk VLAN pruning.
There is no mechanism to block a redundant Layer 2 path, so the Layer 2 topology must
be a loop-free tree **by construction**. Two consequences:

- Six router ports are cabled to access switches and held administratively down,
  because each router also reaches those switches through its aggregation switch.
  They are pre-cabled recovery paths, not mistakes.
- Layer 2 redundancy is out of scope. Redundancy lives at Layer 3, where OSPF
  provides it — which is where this design would put it in production anyway.

A loop here does not degrade gracefully: broadcast frames circulate indefinitely and
saturate the host, and the symptom presents as GNS3 being slow rather than as a
cabling fault. Review found three such loops still closed in the live topology
([R-02](REVIEW_FINDINGS.md#r-02)).

---

## 3. Routing design

### 3.1 Why OSPF, and why multi-area

| Alternative | Why rejected |
|-------------|--------------|
| Static routing | Five routers, seventeen internal prefixes and a redundant path. Static routing gives no automatic reconvergence, so the backup WAN could not fail over at all — the feature would exist and not work |
| RIP | 15-hop diameter and 30-second periodic updates. Convergence measured in minutes is incompatible with a design whose resilience story is sub-minute failover |
| EIGRP | Simpler to configure, but Cisco-proprietary. OSPF (RFC 2328) lets any site gateway be replaced with non-Cisco hardware without redesigning the routing protocol |

Multi-area is used even though the lab is small, because the areas are the mechanism
that makes the design *scale*:

- Area 0 contains only the WAN /30s, the backbone loopbacks and the DMZ. Its LSDB is
  small and stable.
- Each site's LANs sit in their own area, so a flapping access subinterface at the
  Branch triggers SPF only inside area 30 and emits a single type-3 summary into the
  backbone, instead of a domain-wide SPF run.
- Every non-backbone area touches area 0 through exactly one ABR, satisfying OSPF's
  connectivity requirement with no virtual links.

### 3.2 Specific routing decisions

| Decision | Reason |
|----------|--------|
| DMZ in area 0 rather than its own area | `Fa2/0.60` is `FW-EDGE`'s only non-backbone segment. A separate area would make it an ABR generating type-3 summaries for a single /24 — LSDB complexity for no scaling benefit. The interface is passive, so no adjacency can form in the DMZ |
| `passive-interface default` with explicit `no passive-interface` per WAN link | Hellos are sent only where a neighbour is expected. No user, server, guest or DMZ segment receives them, so a rogue host cannot form an adjacency. LAN prefixes are still advertised — what is suppressed is neighbour formation, not reachability |
| `Loopback0` as router ID, and as syslog / NTP / DNS source and Ansible target | One always-up interface defines one identity per device. A physical interface flapping never changes the router ID, so no adjacency reset and no LSDB churn — and log, time and automation records stay keyed to one address regardless of which of `BR-EDGE`'s two WAN paths is active |
| `default-information originate always` on `FW-EDGE` only | The upstream default comes from a DHCP lease whose renewal timing is outside our control. `always` keeps the domain default stable across a renewal rather than black-holing four zones for its duration |
| OSPF area 0 MD5 authentication | Five adjacencies including a redundant path. Any device reaching a WAN segment could otherwise inject LSAs and attract or black-hole traffic for the whole enterprise. Applied per-area so a new backbone link cannot come up unauthenticated by omission |
| Non-backbone areas not authenticated | Those areas carry no adjacencies at all — every LAN interface is passive. Authenticating them would add key management with no threat reduction. The asymmetry is a decision, not an oversight |
| Default cost everywhere except the backup WAN | Every link is FastEthernet, so cost is a uniform 1 and the metric equals hop count. That makes the routing table predictable and the one deliberate exception (50) unambiguous. If faster media were introduced, `auto-cost reference-bandwidth` would become mandatory to keep the metric meaningful |
| No route redistribution | One routing protocol, one externally originated route. Nothing needs redistributing, so there is no risk of a redistribution loop or a metric-translation error |

---

## 4. Security design

Defence in depth across three planes. Each control names the specific attack or
failure it addresses.

### 4.1 Management plane

| Control | Implementation | What it prevents |
|---------|----------------|------------------|
| No plaintext remote access | `ip ssh version 2` + `transport input ssh` on every VTY line | Credentials crossing the WAN in clear text. Telnet is disabled outright, not merely deprioritised |
| Source-restricted administration | `ACL_VTY` with `access-class … in` on `line vty 0 4` **and** `line vty 5 15` | Administration from anywhere but the two named management hosts and the DC break-glass subnet. Guarding only `0 4` leaves lines 5–15 unfiltered once five sessions are open — a control that looks applied and is bypassable under load ([R-15](REVIEW_FINDINGS.md#r-15)) |
| Least privilege on origins | `permit tcp host 10.10.99.10` and `host 10.10.99.11` rather than a /24 | A device plugged into a management access port inheriting administrative reach. There are exactly two legitimate administrators of network equipment, so they are named |
| Static-only management VLAN | No DHCP pool on VLAN 99 | Auto-addressing an unknown host into the one subnet `ACL_VTY` trusts — turning physical access into management access ([R-08](REVIEW_FINDINGS.md#r-08)) |
| Separated administrative paths | `AUTO-SRV` for automation, `JUMP-SRV` for interactive access | A single compromised credential covering both change paths. The two have distinct audit trails |
| Logged refusals | `deny ip any any log` closing `ACL_VTY` | Silent drops. A refused administrative attempt is the single most useful line in the log |
| Credential hygiene | `enable secret`, `username … secret`, `service password-encryption` | Reversible cleartext passwords in `show running-config` |
| Session hygiene | `exec-timeout 10 0` VTY, `15 0` console, `ip ssh time-out 60`, `authentication-retries 2` | Abandoned-session hijacking, and fast credential guessing |
| Unused paths closed | `line aux 0` with `no exec`; `no ip http server`; `no ip http secure-server`; `no service pad` | Management surfaces that are on by default and never used |
| Reconnaissance limited | `no cdp enable` on the untrusted, DMZ and guest interfaces | Advertising platform, IOS version, hostname and native VLAN to an untrusted neighbour. CDP is retained on internal WAN links, where its neighbour table genuinely helps verify cabling against the link table |
| Attribution | `login on-success log`, `login on-failure log`, `archive log config` with `hidekeys` | Unattributable changes. Every login attempt and every configuration line entered is exported off-box. `hidekeys` matters specifically: without it the archive ships secrets in clear text to the collector, turning an audit control into a credential leak |
| Legal notice | `banner login` and `banner motd` on all five | Enforceability of unauthorised-access claims |

### 4.2 Data plane — segmentation

Seven ACLs at seven enforcement points.

| Control | Where | Rationale |
|---------|-------|-----------|
| Guest containment, first hop | `ACL_GUEST_IN` in on `BR-EDGE Fa3/0.50` | Enforced at the **first** Layer 3 hop, so denied guest traffic never enters the WAN and consumes no backbone bandwidth |
| Guest containment, second pass | `ACL_WAN_BR_IN` in on `DC-EDGE Fa1/0` **and** `HQ-CORE Fa3/0` | Defence in depth that survives failover. If the branch ACL is removed during a change, or a guest reaches the staff VLAN, both WAN egress points still refuse guest-sourced traffic |
| Management VLAN isolation | `ACL_HQ_USERS_IN` in on `HQ-DIST Fa2/0.10` | Ordinary workstations have no business reaching the host that holds router credentials |
| Perimeter ingress filter | `ACL_OUTSIDE_IN` in on `FW-EDGE Fa0/0` | RFC 2827 anti-spoofing plus an allow-list ending in an explicit deny |
| DMZ egress containment | `ACL_DMZ_IN` in on `FW-EDGE Fa2/0.60` | The DMZ is the most likely zone to be compromised, so it must not be able to initiate inward. This is what stops a web application vulnerability becoming an internal foothold |
| Administrative access | `ACL_VTY` on both VTY ranges, all five routers | §4.1 |
| NAT scope | `ACL_NAT` on `FW-EDGE` | Names the four zones that are translated and deliberately excludes WAN transit |
| No proxy ARP / no redirects | all host-facing and WAN interfaces | A host being tricked into using the router as a MITM relay for off-subnet addresses |

**ACL entry ordering is a design element, not an accident.** In `ACL_GUEST_IN`, the
DHCP permit — which must source from `any`, because a DISCOVER comes from `0.0.0.0` —
and the DNS permits to `10.20.30.10` sit **above** the deny rules. Move them below
and the guest network is dead rather than restricted: no address, no name resolution.
Every ACL also closes with an explicit entry, so the implicit deny never makes the
decision and drops are always counted and logged.

### 4.3 Anti-spoofing: enumerate what you own, not what looks private

The intuitive perimeter filter is `deny ip 10.0.0.0 0.255.255.255 any`. It is wrong
here. `FW-EDGE Fa0/0` takes its address by DHCP from the NAT cloud, and a GNS3 VM on
a host network inside `10.0.0.0/8` — common on university and corporate Wi-Fi — would
have its own DHCP `OFFER` dropped by that entry. The outside interface would never
bind, and all four zones would lose Internet access with a symptom that points at the
NAT cloud rather than at the ACL.

The filter therefore enumerates only the address space this enterprise owns —
`10.10.0.0/16`, `10.20.0.0/16`, `10.30.0.0/16`, `10.60.60.0/24`, `10.255.0.0/24`,
plus loopback and link-local. That is also strictly *stronger*: it blocks spoofed WAN
transit sources, which the single `/8` entry covered only incidentally.

### 4.4 The structural weakness of deny-lists

The most instructive defect found during review was `ACL_GUEST` denying two /24s and
then permitting everything else. It was very likely correct when written; every
subnet added to the network since had silently widened it, until guests could reach
the Branch staff VLAN on the adjacent switch ([R-06](REVIEW_FINDINGS.md#r-06)).

Two conclusions carried into the design:

1. **Every deny-list ACL now enumerates zones by name**, and adding a zone is a
   documented change-control obligation ([`IP_ADDRESSING.md`](IP_ADDRESSING.md) §8),
   not a thing to remember.
2. **Allow-lists are used where the trust gradient is steepest.** `ACL_OUTSIDE_IN`
   is an allow-list closing in `deny ip any any log`. Deny-lists remain internally,
   where the cost of a missed entry is lower and the readability benefit is real.

### 4.5 NAT as a security control, and its order of operations

Outbound PAT gives four zones Internet access through one address, so no internal
address is routable from outside. Inbound, exactly two services are published by
static port translation.

The subtlety that broke the original configuration is worth stating because it is
counter-intuitive: for traffic arriving on a NAT **outside** interface, IOS evaluates
the inbound ACL **before** outside-to-inside translation. The destination in the
packet is therefore still the outside global address, not the DMZ server. An ACL
written against `10.60.60.10` can never match
([R-03](REVIEW_FINDINGS.md#r-03)). The corrected entries match the pre-translation
destination and say so in a `remark`.

TCP 443 was deliberately *not* published: nothing in the DMZ terminates TLS, so
publishing it would advertise a port with no listener.

### 4.6 Control plane

- Adjacencies can form only on the WAN interfaces, because everything else is
  passive. This is the single most effective control-plane protection available
  before authentication.
- Area 0 carries MD5 authentication (§3.2).
- `ACL_WAN_BR_IN` permits `ospf any any` explicitly rather than relying on its
  trailing `permit ip any any`, so the adjacency survives any future tightening of
  the tail — a common cause of self-inflicted outages.

---

## 5. Service design

| Service | Placement | Why there |
|---------|-----------|-----------|
| DNS, NTP, Syslog | Data Centre VLAN 30 | Consumed by all four zones, and the Data Centre is the WAN transit point — the topological centre. One subnet becomes the trust anchor for the management plane, which is expressible as a single ACL entry |
| `FILE-SRV` | Data Centre VLAN 30, **not** published | The counter-example that makes the DMZ boundary meaningful: something deliberately not reachable from outside. It is also the cleanest segmentation demonstration available, since Branch staff reach it and Branch guests do not, from adjacent switches |
| `MON-SRV` | Data Centre VLAN 30 | Completes the management plane — NTP gives a common clock, syslog records what happened, monitoring answers what is up now. Also the break-glass SSH origin |
| `WEB-SRV`, `APP-SRV` | DMZ VLAN 60 | Internet-facing, therefore outside every trusted zone by definition |
| `AUTO-SRV` | HQ VLAN 99 | The automation server the brief requires. On the management VLAN so it is subject to `ACL_VTY` exactly as a human administrator is — which is what makes that ACL a real control |
| `JUMP-SRV` | HQ VLAN 99, behind `MGMT-SW` | Interactive administration, separated from automation |

### 5.1 Why NTP is a prerequisite, not a peer requirement

Centralised logging is only useful if entries from five devices can be ordered.
Correlating an ACL denial on `BR-EDGE` with the OSPF adjacency change on `DC-EDGE`
that caused it requires comparable timestamps, which requires a common clock. So
`clock timezone`, `service timestamps log datetime msec localtime show-timezone` and
the NTP client are all prerequisites for the logging evidence rather than independent
boxes to tick.

Review found `service timestamps` missing on all five routers, which meant messages
arrived carrying only an uptime counter — the clocks were correct and nothing was
stamping the messages with them ([R-14](REVIEW_FINDINGS.md#r-14)).

`NTP` is configured `local stratum 10` so it is authoritative with no Internet
reachability, because the lab must be demonstrable offline. Routers therefore
synchronise at **stratum 11** — one level below — which is the correct expected value,
not an error.

### 5.2 DNS forwarding, and a failure that hides in plain sight

`dnsmasq` is authoritative for `corp.local` and forwards everything else. It must be
told its upstreams explicitly (`no-resolv`, `server=8.8.8.8`), because otherwise it
reads `/etc/resolv.conf` — which on that host points at itself. The result is a
forwarding loop where internal names resolve perfectly and every external name fails
([R-09](REVIEW_FINDINGS.md#r-09)). Partial success is what makes this class of fault
expensive to find, which is why the setup script now ends with a self-check that
resolves both an internal and an external name.

Zone data uses `host-record` rather than `address`, so every entry gets a reverse
`PTR` as well as a forward `A` record — reverse lookups are what make log analysis
readable.

---

## 6. Platform choices

Every platform decision follows from one constraint: the GNS3 VM has **4 GB of RAM**,
on an Apple silicon host.

| Requirement | Choice | Alternative rejected | Why |
|-------------|--------|----------------------|-----|
| Routers | Cisco c7200 / Dynamips, 5 instances | IOSv or IOSvL2 under QEMU | IOSv needs 512 MB–1 GB of *real* RAM each; five would exceed the whole VM. On arm64 an x86 image must run under software emulation (TCG), roughly an order of magnitude slower — boot times of many minutes and unstable OSPF hellos |
| Switching, 17 instances | GNS3 built-in Ethernet switch | IOSvL2 | 17 IOSvL2 instances need ~8 GB against 4 GB available. The built-in switch provides access-port VLANs and 802.1Q tagging, which is exactly what is needed to prove segmentation, inter-VLAN routing, per-VLAN DHCP and VLAN-based ACLs |
| Servers, 9 instances | Docker Ubuntu | A VM per service | Containers share the VM kernel, so on Apple silicon they run native arm64 with no emulation penalty, at tens of megabytes each. Nine QEMU VMs would need ~9 GB |
| Endpoints, 10 instances | VPCS | Docker or VM | VPCS is a userspace process with a DHCP client and `ping`/`trace` — everything needed, at negligible cost |

**Consequence for the configurations.** Dynamips c7200 hardware is an I/O controller
in slot 0 plus port adapters in slots 1–6. `C7200-IO-FE` in slot 0 and `PA-FE-TX` in
slots 1–3 yields `Fa0/0`, `Fa1/0`, `Fa2/0`, `Fa3/0`. This is why **every interface in
the project is FastEthernet**. A configuration referencing `GigabitEthernet0/0` looks
plausible, applies without error, and does nothing — so interface naming discipline
is a correctness requirement, not cosmetics. It is checked mechanically by
[`scripts/validate_configs.py`](../scripts/validate_configs.py).

A useful side effect: uniform 100 Mbit/s links mean a uniform OSPF cost of 1, so the
metric equals hop count and the single deliberate exception is obvious.

**Accepted limitations, stated rather than omitted:** no STP, port security, BPDU
guard, LACP or trunk VLAN pruning on the switching layer; no stateful inspection at
the edge (CBAC is provided as a commented, costed upgrade path). Docker nodes do not
persist filesystem changes outside their configured directories, which is why every
setup script is idempotent and re-runnable after a container restart.

---

## 7. Scalability analysis

### 7.1 Adding a site

No renumbering. Allocate the next zone octet and the next WAN /30
(`10.255.0.12/30`), configure the new gateway as an ABR with its WAN link in area 0
and its LANs in a new area, add local DHCP pools, and point it at
`10.20.30.10/.11/.12`. No existing router changes beyond one interface and one
`network` statement, because the new site's internal topology is hidden behind its
ABR.

The one non-obvious step: **extend every ACL that enumerates enterprise address
space** — `ACL_NAT`, `ACL_OUTSIDE_IN`, `ACL_DMZ_IN`, `ACL_GUEST_IN`,
`ACL_WAN_BR_IN`. Skipping it is precisely how R-06 happened.

### 7.2 Growing a site

The third octet is the VLAN ID, so each zone has 254 VLAN-aligned /24s available.
Each new VLAN needs one subinterface, one DHCP pool, one `network … area <n>`
statement and switch access ports. `HQ-DIST Fa3/0` is reserved for a further access
block, and `SW-DC-2` already has VLAN 30 ports provisioned for a new server.

### 7.3 Where this design stops scaling

| Limit | Symptom | Remedy |
|-------|---------|--------|
| Router-on-a-stick trunk | All inter-VLAN traffic per site shares one 100 Mbit/s trunk, CPU-forwarded | Layer 3 switch with SVIs; addressing and OSPF transfer unchanged |
| One router per area | Area summarisation and stub areas have no effect yet | Add `area <n> range` on each ABR; make leaf areas stub or totally stubby to shrink remote LSDBs |
| No STP | No redundant Layer 2 paths possible | IOSvL2 with RSTP, once the VM has ≥8 GB |
| Single instance of each service | Any one container is a single point of failure for the management plane | Second instance per service in a different VLAN; the configurations already accept multiple `ip name-server`, `ntp server` and `logging host` entries |
| Stateless edge | Structural rather than session-based return-traffic matching | Enable the CBAC block in `configs/FW-EDGE.cfg` |
| No first-hop gateway redundancy | A site router failure isolates its VLANs | `.2`–`.9` is reserved in every /24 for HSRP/VRRP, so this needs no readdressing |
| Manual per-device configuration | Configuration drift across five devices | Exactly what Part B addresses: `AUTO-SRV` renders and pushes these configurations from Jinja2 templates, which makes these five files the intended source of truth |

### 7.4 Operational scalability

The configurations are written to be *maintained*, and specifically to be
template-generated in Part B: named ACLs with `remark` lines instead of numbered
lists; a `description` on every interface naming both ends of the link; ACLs defined
before the objects that reference them so the files replay cleanly top to bottom; and
exactly one block per interface and per line range.

That last property is the one that matters most for Part B. IOS merges duplicate
`interface` blocks, so a configuration with two blocks for the same interface works
by accident — but it cannot be reliably rendered from a template or idempotently
re-applied, and an interface's complete policy cannot be read in one place. The
validator enforces it.
