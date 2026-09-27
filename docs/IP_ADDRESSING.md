# MN521 Part A — Enterprise IP Addressing Plan

Authoritative addressing for the Part A network. Every other artefact — the IOS
configurations, the switch port matrix, the container setup scripts, the
verification plan and the report — derives its addresses from this document. Where
this document and another artefact disagree, this document is correct and the other
is a defect.

Cabling is in [`TOPOLOGY.md`](TOPOLOGY.md); per-node purpose in
[`NODE_INVENTORY.md`](NODE_INVENTORY.md); rationale in
[`DESIGN_JUSTIFICATION.md`](DESIGN_JUSTIFICATION.md).

---

## 1. Allocation scheme

The enterprise uses `10.0.0.0/8` with a **zone-aligned second octet** and a
**VLAN-aligned third octet**:

```
10 . <zone> . <vlan> . <host>
     ^^^^^^   ^^^^^^
     site     VLAN ID
```

| Block | Zone | OSPF area | Purpose |
|-------|------|-----------|---------|
| `10.10.0.0/16` | Headquarters | 10 | User, corporate and management VLANs |
| `10.20.0.0/16` | Data Centre | 20 | Server farm |
| `10.30.0.0/16` | Branch Office | 30 | Branch staff and isolated guest |
| `10.60.0.0/16` | Internet edge / DMZ | 0 | Semi-trusted, Internet-reachable services |
| `10.255.0.0/24` | WAN transit | 0 | Point-to-point /30s between routers |
| `1.1.1.0/24`, `2.2.2.0/24`, `3.3.3.0/24`, `4.4.4.0/24` | Router identity | various | `Loopback0` /32s |

Three properties follow, and each is relied on elsewhere:

1. **A whole zone is one ACL entry.** "All of Headquarters" is
   `10.10.0.0 0.0.255.255`. This is why `ACL_GUEST_IN` and `ACL_DMZ_IN` can exclude
   an entire zone per line instead of enumerating VLANs — and why adding a zone to
   the network creates an obligation to extend those ACLs (§8).
2. **A whole zone is one summary.** Each zone is a single /16 that its ABR can
   advertise with one `area <n> range` statement once a site grows past one router.
   The lab does not enable summarisation — with one router per area there is nothing
   to summarise — but no readdressing is needed to enable it.
3. **An address identifies itself.** `10.30.50.24` is unambiguously Branch,
   VLAN 50 (guest), host 24 — readable off a console or a syslog line without a
   lookup table. This matters most when reading ACL denial logs.

### Host-part convention, applied to every /24

| Range | Reserved for |
|-------|--------------|
| `.1` | Default gateway (router subinterface) |
| `.2`–`.9` | Future first-hop redundancy (HSRP/VRRP virtual and physical) |
| `.10`–`.19` | Statically addressed servers |
| `.20` | Boundary marker — never assigned |
| `.21`–`.254` | DHCP pool |

`ip dhcp excluded-address 10.x.y.1 10.x.y.20` on every pool enforces the boundary,
which is why every lease in the verification evidence begins at `.21`. The
convention means a static server address and a DHCP lease can never collide, and it
leaves room for first-hop redundancy without renumbering anything.

---

## 2. VLANs

Seven data VLANs. VLAN 1 is deliberately empty.

| VLAN | Name | Subnet | Gateway | Gateway interface | Zone | Area | Addressing |
|-----:|------|--------|---------|-------------------|------|-----:|------------|
| 10 | `HQ_USERS` | `10.10.10.0/24` | `10.10.10.1` | `HQ-DIST Fa2/0.10` | HQ | 10 | DHCP |
| 20 | `HQ_CORP` | `10.10.20.0/24` | `10.10.20.1` | `HQ-DIST Fa2/0.20` | HQ | 10 | DHCP |
| 99 | `HQ_MGMT` | `10.10.99.0/24` | `10.10.99.1` | `HQ-DIST Fa2/0.99` | HQ | 10 | **static only** |
| 30 | `DC_SERVERS` | `10.20.30.0/24` | `10.20.30.1` | `DC-EDGE Fa3/0.30` | DC | 20 | static + DHCP for staging |
| 40 | `BR_STAFF` | `10.30.40.0/24` | `10.30.40.1` | `BR-EDGE Fa3/0.40` | BR | 30 | DHCP |
| 50 | `BR_GUEST` | `10.30.50.0/24` | `10.30.50.1` | `BR-EDGE Fa3/0.50` | BR | 30 | DHCP, short lease |
| 60 | `DMZ` | `10.60.60.0/24` | `10.60.60.1` | `FW-EDGE Fa2/0.60` | DMZ | 0 | static + DHCP |
| 1 | *(default — unused)* | — | — | — | — | — | deliberately empty |

**Why VLAN 99 has no DHCP pool.** It is the only subnet from which `ACL_VTY`
accepts an administrative SSH session. A pool there would automatically address any
device plugged into an access port on `SW-HQ-1` or `MGMT-SW` into the one subnet
trusted to administer every router, converting a physical-access problem into a
management-plane-access problem. Hosts on VLAN 99 are named individually instead.

**Why VLAN 1 is empty and every VLAN is tagged.** It removes the native-VLAN
mismatch class of fault entirely: a router subinterface accepts only tagged frames,
so if a trunk's native VLAN carried data, those frames would arrive untagged and be
silently discarded. It also means a GNS3 access port left at its default of
`1 / access` fails obviously — the host gets no lease — rather than joining a live
VLAN by accident.

---

## 3. WAN transit links

All WAN transit is carved from `10.255.0.0/24` as /30s. Five of the 64 available
/30s are in use.

| Link | Network | A end | A address | B end | B address | Transit | Cost |
|------|---------|-------|-----------|-------|-----------|---------|------|
| Internet | GNS3 NAT pool | `Internet-NAT` | GNS3-managed | `FW-EDGE Fa0/0` | DHCP | via `ISP-Cloud` | — |
| Edge ↔ Core | `10.255.0.16/30` | `FW-EDGE Fa1/0` | `10.255.0.17` | `HQ-CORE Fa0/0` | `10.255.0.18` | direct | 1 |
| Core ↔ DC | `10.255.0.0/30` | `HQ-CORE Fa1/0` | `10.255.0.1` | `DC-EDGE Fa0/0` | `10.255.0.2` | direct | 1 |
| Core ↔ HQ dist | `10.255.0.8/30` | `HQ-CORE Fa2/0` | `10.255.0.9` | `HQ-DIST Fa0/0` | `10.255.0.10` | direct | 1 |
| DC ↔ Branch (primary) | `10.255.0.4/30` | `DC-EDGE Fa1/0` | `10.255.0.5` | `BR-EDGE Fa0/0` | `10.255.0.6` | direct | 1 |
| Core ↔ Branch (backup) | `10.255.0.20/30` | `HQ-CORE Fa3/0` | `10.255.0.21` | `BR-EDGE Fa2/0` | `10.255.0.22` | via `WAN-Cloud` | **50** |

`10.255.0.12/30` is unallocated. Free /30s, in allocation order:
`10.255.0.12/30`, `10.255.0.24/30`, `10.255.0.28/30` … `10.255.0.252/30` —
**59 remaining**.

### Why /30s, and why cost 50 on the backup

A point-to-point link needs exactly two host addresses. A /24 per WAN link would
waste 250 addresses each and put needlessly large prefixes in the routing table.
The /30 also does useful work on the two hub-transited segments: because only two
host addresses exist, no third device can be addressed onto a shared hub segment.

Every link is FastEthernet, so the default OSPF cost is a uniform
1 (`10^8 / 10^8`). That makes the direct `BR-EDGE → HQ-CORE` backup path *shorter*
(1 hop) than the primary path through the Data Centre (2 hops), so OSPF would
prefer it and pull all Branch traffic away from the `DC-EDGE` policy enforcement
point. Cost 50 on both ends of `10.255.0.20/30` inverts that: the Data Centre path
costs 2 and wins, while the backup still takes over within OSPF convergence time if
the primary fails. Making the redundant path deliberately *less preferred* rather
than equal-cost also keeps packet paths deterministic, which matters in a lab whose
evidence is per-interface ACL counters.

---

## 4. Router interfaces

Dynamips c7200 slots: **slot 0 = `C7200-IO-FE`** → `Fa0/0`; **slots 1–3 =
`PA-FE-TX`** → `Fa1/0`, `Fa2/0`, `Fa3/0`.

### 4.1 `FW-EDGE` — Internet edge, PAT, DMZ (`Lo0 4.4.4.4/32`)

| Interface | Address | Role | Key configuration |
|-----------|---------|------|-------------------|
| `Fa0/0` | DHCP | NAT outside, untrusted, via `ISP-Cloud` | `ip nat outside`, `ip access-group ACL_OUTSIDE_IN in`, `no cdp enable` |
| `Fa1/0` | `10.255.0.17/30` | To `HQ-CORE Fa0/0` | `ip nat inside`, area 0, MD5 |
| `Fa2/0` | none | 802.1Q trunk to `SW-DMZ-1` | parent trunk, no address |
| `Fa2/0.60` | `10.60.60.1/24` | DMZ gateway | `ip nat inside`, `ip access-group ACL_DMZ_IN in`, `no cdp enable` |
| `Fa3/0` | none | Reserved second ISP uplink | `shutdown` |
| `Lo0` | `4.4.4.4/32` | Router ID, log/NTP/DNS source | area 0 |

### 4.2 `HQ-CORE` — area 0 core (`Lo0 1.1.1.1/32`)

| Interface | Address | Role | Key configuration |
|-----------|---------|------|-------------------|
| `Fa0/0` | `10.255.0.18/30` | To `FW-EDGE Fa1/0` | area 0, MD5 |
| `Fa1/0` | `10.255.0.1/30` | To `DC-EDGE Fa0/0` | area 0, MD5 |
| `Fa2/0` | `10.255.0.9/30` | To `HQ-DIST Fa0/0` | area 0, MD5 |
| `Fa3/0` | `10.255.0.21/30` | To `BR-EDGE Fa2/0` via `WAN-Cloud` | `ip ospf cost 50`, `ip access-group ACL_WAN_BR_IN in`, MD5 |
| `Lo0` | `1.1.1.1/32` | Router ID, log source | area 0 |

No NAT and no external route origination: `HQ-CORE` is pure transit.

### 4.3 `HQ-DIST` — HQ distribution, DHCP (`Lo0 1.1.1.4/32`)

| Interface | Address | Role | Key configuration |
|-----------|---------|------|-------------------|
| `Fa0/0` | `10.255.0.10/30` | To `HQ-CORE Fa2/0` | area 0, MD5 |
| `Fa1/0` | none | Cabled to `SW-HQ-1 Eth0` | `shutdown` — loop avoidance |
| `Fa2/0` | none | 802.1Q trunk to `SW-HQ-DIST` | parent trunk, no address |
| `Fa2/0.10` | `10.10.10.1/24` | VLAN 10 gateway | `ip access-group ACL_HQ_USERS_IN in`, area 10 |
| `Fa2/0.20` | `10.10.20.1/24` | VLAN 20 gateway | area 10 |
| `Fa2/0.99` | `10.10.99.1/24` | VLAN 99 gateway | area 10, no DHCP pool |
| `Fa3/0` | none | Reserved growth trunk | `shutdown` |
| `Lo0` | `1.1.1.4/32` | Router ID, log source | area 10 |

### 4.4 `DC-EDGE` — Data Centre gateway, WAN transit (`Lo0 2.2.2.2/32`)

| Interface | Address | Role | Key configuration |
|-----------|---------|------|-------------------|
| `Fa0/0` | `10.255.0.2/30` | To `HQ-CORE Fa1/0` | area 0, MD5 |
| `Fa1/0` | `10.255.0.5/30` | To `BR-EDGE Fa0/0`, primary Branch path | `ip access-group ACL_WAN_BR_IN in`, area 0, MD5 |
| `Fa2/0` | none | Cabled to `SW-DC-1 Eth0` | `shutdown` — loop avoidance |
| `Fa3/0` | none | 802.1Q trunk to `SW-DC-CORE` | parent trunk, no address |
| `Fa3/0.30` | `10.20.30.1/24` | VLAN 30 gateway | area 20 |
| `Lo0` | `2.2.2.2/32` | Router ID, log source | area 0 |

### 4.5 `BR-EDGE` — Branch gateway, dual-homed (`Lo0 3.3.3.3/32`)

| Interface | Address | Role | Key configuration |
|-----------|---------|------|-------------------|
| `Fa0/0` | `10.255.0.6/30` | To `DC-EDGE Fa1/0`, primary | area 0, MD5 |
| `Fa1/0` | none | Cabled to `SW-BR-1 Eth0` | `shutdown` — loop avoidance |
| `Fa2/0` | `10.255.0.22/30` | To `HQ-CORE Fa3/0` via `WAN-Cloud`, backup | `ip ospf cost 50`, area 0, MD5 |
| `Fa3/0` | none | 802.1Q trunk to `SW-BR-DIST` | parent trunk, no address |
| `Fa3/0.40` | `10.30.40.1/24` | VLAN 40 gateway | area 30 |
| `Fa3/0.50` | `10.30.50.1/24` | VLAN 50 guest gateway | `ip access-group ACL_GUEST_IN in`, `no cdp enable`, area 30 |
| `Lo0` | `3.3.3.3/32` | Router ID, log source | area 30 |

---

## 5. Loopbacks and router identity

| Device | `Loopback0` | OSPF router ID | Loopback's area |
|--------|-------------|----------------|-----------------|
| `FW-EDGE` | `4.4.4.4/32` | `4.4.4.4` | 0 |
| `HQ-CORE` | `1.1.1.1/32` | `1.1.1.1` | 0 |
| `HQ-DIST` | `1.1.1.4/32` | `1.1.1.4` | 10 |
| `DC-EDGE` | `2.2.2.2/32` | `2.2.2.2` | 0 |
| `BR-EDGE` | `3.3.3.3/32` | `3.3.3.3` | 30 |

`Loopback0` is used for **five** distinct purposes on every router: the OSPF router
ID, the syslog source address, the NTP source address, the DNS query source
address, and the Ansible inventory target. One always-up interface therefore
defines one identity per device. The practical consequences:

- A physical interface flapping or being renumbered never changes the router ID, so
  there is no adjacency reset and no LSDB churn.
- Log and time correlation stay keyed to one address per device regardless of which
  of a router's four WAN interfaces a packet left by — which matters here because
  `BR-EDGE` has two WAN paths and would otherwise log under two different
  addresses depending on the failover state.

`HQ-CORE` and `DC-EDGE` place their loopbacks in area 0; `HQ-DIST` and `BR-EDGE`
place theirs in their site area. This is visible in the routing table —
`1.1.1.1/32` and `2.2.2.2/32` appear as intra-area `O` on backbone routers while
`1.1.1.4/32` and `3.3.3.3/32` appear as inter-area `O IA` — and is asserted in the
verification plan so it reads as a decision rather than an inconsistency.

---

## 6. Host addressing

### 6.1 Statically addressed servers

| Host | Address | VLAN | Gateway | Service |
|------|---------|-----:|---------|---------|
| `AUTO-SRV` | `10.10.99.10/24` | 99 | `10.10.99.1` | Ansible / Netmiko automation control node |
| `JUMP-SRV` | `10.10.99.11/24` | 99 | `10.10.99.1` | SSH bastion for interactive administration |
| `DNS` | `10.20.30.10/24` | 30 | `10.20.30.1` | `dnsmasq`, authoritative for `corp.local` |
| `NTP` | `10.20.30.11/24` | 30 | `10.20.30.1` | `chrony`, `local stratum 10` |
| `SYSLOG` | `10.20.30.12/24` | 30 | `10.20.30.1` | `rsyslog`, UDP/TCP 514 |
| `FILE-SRV` | `10.20.30.13/24` | 30 | `10.20.30.1` | Internal HTTP file share, not published |
| `MON-SRV` | `10.20.30.14/24` | 30 | `10.20.30.1` | Monitoring, `:9090`, break-glass SSH origin |
| `WEB-SRV` | `10.60.60.10/24` | 60 | `10.60.60.1` | `nginx`, published on TCP 80 |
| `APP-SRV` | `10.60.60.11/24` | 60 | `10.60.60.1` | Application tier, published on TCP 8080 |

### 6.2 DHCP endpoints

| Host | VLAN | Gateway | DHCP server | Pool | Domain served |
|------|-----:|---------|-------------|------|---------------|
| `PC1`, `PC5` | 10 | `10.10.10.1` | `HQ-DIST` | `VLAN10_HQ_USERS` | `corp.local` |
| `PC2`, `PC8` | 20 | `10.10.20.1` | `HQ-DIST` | `VLAN20_HQ_CORP` | `corp.local` |
| `PC3`, `PC6`, `PC7` | 40 | `10.30.40.1` | `BR-EDGE` | `VLAN40_BR_STAFF` | `corp.local` |
| `PC4`, `PC9` | 50 | `10.30.50.1` | `BR-EDGE` | `VLAN50_BR_GUEST` | `guest.corp.local` |
| `PC-DMZ` | 60 | `10.60.60.1` | `FW-EDGE` | `VLAN60_DMZ` | `dmz.corp.local` |

Leases start at `.21`. Which host in a VLAN receives `.21` versus `.22` depends on
boot order, so the pass criterion is a correct subnet, mask, gateway, DNS server and
domain name — not a specific host address.

---

## 7. DHCP pools

| Pool | Router | Network | Excluded | Gateway | DNS | Domain | Option 42 | Lease |
|------|--------|---------|----------|---------|-----|--------|-----------|-------|
| `VLAN10_HQ_USERS` | `HQ-DIST` | `10.10.10.0/24` | `.1`–`.20` | `.1` | `10.20.30.10` | `corp.local` | `10.20.30.11` | 2 days |
| `VLAN20_HQ_CORP` | `HQ-DIST` | `10.10.20.0/24` | `.1`–`.20` | `.1` | `10.20.30.10` | `corp.local` | `10.20.30.11` | 2 days |
| `VLAN30_DC_SERVERS` | `DC-EDGE` | `10.20.30.0/24` | `.1`–`.20` | `.1` | `10.20.30.10` | `corp.local` | `10.20.30.11` | 7 days |
| `VLAN40_BR_STAFF` | `BR-EDGE` | `10.30.40.0/24` | `.1`–`.20` | `.1` | `10.20.30.10` | `corp.local` | `10.20.30.11` | 2 days |
| `VLAN50_BR_GUEST` | `BR-EDGE` | `10.30.50.0/24` | `.1`–`.20` | `.1` | `10.20.30.10` | `guest.corp.local` | *(none)* | 4 hours |
| `VLAN60_DMZ` | `FW-EDGE` | `10.60.60.0/24` | `.1`–`.20` | `.1` | `10.20.30.10` | `dmz.corp.local` | *(none)* | 8 hours |

Six pools on three routers. Design points visible in the table:

- **No pool on VLAN 99** — see §2.
- **The guest scope differs from every corporate scope, and each difference is a
  control.** A four-hour lease matches transient visitor devices and stops the pool
  being exhausted by devices that have left. The distinct domain name makes a guest
  lease self-evident from the client side, which is the cheapest possible proof that
  scope separation works. No option 42 is offered because guests have no reason to
  be handed the enterprise time source.
- **`VLAN30_DC_SERVERS` is expected to show zero leases.** All five Data Centre
  servers are statically addressed. The pool serves the staging ports provisioned on
  `SW-DC-2`, so a replacement or test host can be attached with no router change.
  Zero leases there is the correct steady-state result, not a fault.

---

## 8. Prefix count and change control

### Expected prefix count once converged

| Category | Count |
|----------|------:|
| VLAN /24s | 7 |
| WAN /30s | 5 |
| Loopback /32s | 5 |
| External default (`O*E2`) | 1 |
| **Total in `show ip route`** | **18** |

A router will not list its own directly connected prefixes as OSPF routes, so the
`O`/`O IA` count on any given device is lower than 17; the total above is the size
of the routing information in the domain. Exact per-device expectations are in
[`../verification/CHECKS.md`](../verification/CHECKS.md) §3.

### Adding a VLAN

Pick an unused ID, address it `10.<zone>.<vlan>.0/24`, add the subinterface, add the
DHCP pool with `.1`–`.20` excluded, add the `network … area <n>` statement, and set
the switch access ports. Nothing outside that site's area changes.

### Adding a zone or site

Take the next zone octet, the next WAN /30 (`10.255.0.12/30`), and a new area. Then
— and this is the step that is easy to miss — **extend every ACL that enumerates
enterprise address space**: `ACL_NAT`, `ACL_OUTSIDE_IN`, `ACL_DMZ_IN`,
`ACL_GUEST_IN` and `ACL_WAN_BR_IN`. Omitting it is exactly the defect recorded as
R-06 in [`REVIEW_FINDINGS.md`](REVIEW_FINDINGS.md), where the guest ACL enumerated
only two /24s and therefore granted guests access to everything else that had been
added since it was written.

This is the structural weakness of deny-list filtering at a trust boundary, and it
is the strongest argument in this design for moving to an allow-list model as the
network grows.
