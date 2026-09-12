# MN521 Part A — Enterprise IP Addressing Plan

Authoritative addressing for the Part A network. Every other artefact — the IOS configurations, the topology
tables, the verification plan and the report — derives its addresses from this document. If a value here and
a value elsewhere disagree, this document is correct and the other artefact is a defect.

Cabling and port roles are in [TOPOLOGY.md](TOPOLOGY.md); rationale is in
[DESIGN_JUSTIFICATION.md](DESIGN_JUSTIFICATION.md); the review that produced the current revision is in
[REVIEW_FINDINGS.md](REVIEW_FINDINGS.md).

---

## 1. Allocation scheme

The enterprise uses `10.0.0.0/8` with a **site-aligned second octet** and a **VLAN-aligned third octet**:

```
10 . <site> . <vlan> . <host>
     ^^^^^^   ^^^^^^
     zone     VLAN ID
```

| Block | Zone | OSPF area | Purpose |
|-------|------|-----------|---------|
| `10.10.0.0/16` | Headquarters | 10 | User, corporate and management VLANs |
| `10.20.0.0/16` | Data Centre | 20 | Infrastructure and application server tiers |
| `10.30.0.0/16` | Branch Office | 30 | Branch staff and isolated guest VLANs |
| `10.40.0.0/16` | Internet edge / DMZ | 40 | Semi-trusted, Internet-reachable services |
| `10.255.0.0/24` | WAN transit | 0 | Point-to-point /30s between routers |
| `1.1.1.0/24`, `2.2.2.0/24`, `3.3.3.0/24`, `4.4.4.0/24` | Router IDs | per site | `Loopback0` /32s |

Three properties follow from the scheme and are relied on elsewhere:

1. **Any zone is one ACL entry.** "All of Headquarters" is `10.10.0.0 0.0.255.255`, which is why the guest
   isolation ACL can exclude an entire site per line instead of enumerating VLANs.
2. **Any zone is one summary.** Each zone is a single /16 that its ABR can advertise with one
   `area <n> range 10.<site>.0.0 255.255.0.0` statement when the site grows past one router.
3. **An address identifies itself.** `10.30.50.14` is unambiguously Branch, VLAN 50, host 14 — readable off
   a console screen or a syslog line without consulting a table.

Host-part conventions inside every /24:

| Range | Reserved for |
|-------|--------------|
| `.1` | Default gateway (router subinterface) |
| `.2`–`.9` | Future first-hop redundancy (HSRP/VRRP virtual and physical addresses) |
| `.10`–`.19` | Statically addressed servers and appliances |
| `.20` | Reserved boundary marker — never assigned |
| `.21`–`.254` | DHCP pool |

`ip dhcp excluded-address 10.x.y.1 10.x.y.20` on every pool enforces the boundary, which is why every lease
in the verification evidence begins at `.21`.

---

## 2. Zones and OSPF areas

| Zone | Role | OSPF area | Gateway device(s) | Trust level |
|------|------|-----------|-------------------|-------------|
| Internet | Simulated upstream (GNS3 NAT cloud) | — | `Internet-NAT` | Untrusted |
| DMZ | Internet-reachable web service, DMZ test host | 40 | `FW-EDGE` | Semi-trusted |
| WAN backbone | Router interconnect only, no end hosts | 0 | all five routers | Trusted |
| Headquarters | Users, corporate, management, automation | 10 | `HQ-DIST` | Trusted |
| Data Centre | Infrastructure services and application servers | 20 | `DC-EDGE` | Trusted |
| Branch Office | Branch staff plus an isolated guest network | 30 | `BR-EDGE` | Trusted / untrusted guest |

---

## 3. VLANs

| VLAN | Name | Subnet | Gateway | Gateway interface | Zone | OSPF area | Addressing |
|------|------|--------|---------|-------------------|------|-----------|------------|
| 10 | `HQ_USERS` | `10.10.10.0/24` | `10.10.10.1` | `HQ-DIST Fa1/0.10` | HQ | 10 | DHCP |
| 20 | `HQ_CORP` | `10.10.20.0/24` | `10.10.20.1` | `HQ-DIST Fa1/0.20` | HQ | 10 | DHCP |
| 99 | `HQ_MGMT` | `10.10.99.0/24` | `10.10.99.1` | `HQ-DIST Fa1/0.99` | HQ | 10 | **static only** |
| 30 | `DC_INFRA` | `10.20.30.0/24` | `10.20.30.1` | `DC-EDGE Fa2/0.30` | DC | 20 | static servers + DHCP |
| 31 | `DC_APP` | `10.20.31.0/24` | `10.20.31.1` | `DC-EDGE Fa2/0.31` | DC | 20 | static servers + DHCP |
| 40 | `BR_USERS` | `10.30.40.0/24` | `10.30.40.1` | `BR-EDGE Fa1/0.40` | BR | 30 | DHCP |
| 50 | `BR_GUEST` | `10.30.50.0/24` | `10.30.50.1` | `BR-EDGE Fa1/0.50` | BR | 30 | DHCP (short lease) |
| 200 | `DMZ_PUBLIC` | `10.40.200.0/24` | `10.40.200.1` | `FW-EDGE Fa2/0.200` | DMZ | 40 | static server + DHCP |
| 1 | *(default — unused)* | — | — | — | — | — | deliberately empty |

VLAN 99 carries no DHCP pool: it is the only subnet from which `ACL_VTY` accepts an SSH session, so hosts on
it are named individually rather than admitted automatically. See `REVIEW_FINDINGS.md` R-07.

VLAN 1 is unused and every data VLAN is carried tagged, so a native-VLAN mismatch between a GNS3 switch port
and a router subinterface cannot silently deliver traffic to the wrong VLAN.

---

## 4. WAN point-to-point links

All WAN transit is carved from `10.255.0.0/24` as /30s. Five of the 64 available /30s are in use.

| Link | Network | A end | A address | B end | B address | OSPF area | Cost |
|------|---------|-------|-----------|-------|-----------|-----------|------|
| Internet | DHCP from GNS3 NAT cloud | `Internet-NAT` | GNS3 pool | `FW-EDGE Fa0/0` | learned | — (NAT outside) | — |
| Edge ↔ Core | `10.255.0.12/30` | `FW-EDGE Fa1/0` | `10.255.0.13` | `HQ-CORE Fa0/0` | `10.255.0.14` | 0 | 1 |
| Core ↔ DC | `10.255.0.0/30` | `HQ-CORE Fa1/0` | `10.255.0.1` | `DC-EDGE Fa0/0` | `10.255.0.2` | 0 | 1 |
| Core ↔ HQ dist | `10.255.0.8/30` | `HQ-CORE Fa2/0` | `10.255.0.9` | `HQ-DIST Fa0/0` | `10.255.0.10` | 0 | 1 |
| DC ↔ Branch (primary) | `10.255.0.4/30` | `DC-EDGE Fa1/0` | `10.255.0.5` | `BR-EDGE Fa0/0` | `10.255.0.6` | 0 | 1 |
| Core ↔ Branch (backup) | `10.255.0.16/30` | `HQ-CORE Fa3/0` | `10.255.0.17` | `BR-EDGE Fa2/0` | `10.255.0.18` | 0 | **50** |

The backup link's cost is raised to 50 on both ends so that Branch traffic normally traverses the Data Centre
— preserving both traffic locality and the single policy chokepoint — while the link still takes over within
OSPF's convergence time if the primary path fails. See `REVIEW_FINDINGS.md` R-03 for why equal cost would
have been a security regression rather than an improvement.

**Free WAN /30s** (next allocations, in order): `10.255.0.20/30`, `10.255.0.24/30`, `10.255.0.28/30`, …
through `10.255.0.252/30` — 59 remaining.

---

## 5. Router interfaces

Dynamips c7200 slot layout: **slot 0 = `C7200-IO-FE`** → `Fa0/0`; **slots 1–3 = `PA-FE-TX`** →
`Fa1/0`, `Fa2/0`, `Fa3/0`. Only FastEthernet is used, so every link is 100 Mbit/s and the default OSPF
cost is a uniform 1.

### 5.1 `FW-EDGE` — Internet edge, PAT, DMZ (`Loopback0 4.4.4.4/32`)

| Interface | Address | Role | Notable configuration |
|-----------|---------|------|-----------------------|
| `Fa0/0` | DHCP (GNS3 NAT cloud) | NAT outside, untrusted | `ip nat outside`, `ip access-group ACL_INTERNET_IN in`, `no cdp enable` |
| `Fa1/0` | `10.255.0.13/30` | To `HQ-CORE Fa0/0` | `ip nat inside`, OSPF area 0, MD5 auth |
| `Fa2/0` | none (802.1Q trunk) | To `SW-DMZ` port 0 | parent trunk, no address |
| `Fa2/0.200` | `10.40.200.1/24` | DMZ gateway | `ip nat inside`, `ip access-group ACL_DMZ_IN in`, `no cdp enable` |
| `Fa3/0` | none | Reserved — second ISP uplink | `shutdown` |
| `Loopback0` | `4.4.4.4/32` | Router ID, log source | OSPF area 0 |

### 5.2 `HQ-CORE` — area 0 core (`Loopback0 1.1.1.1/32`)

| Interface | Address | Role | Notable configuration |
|-----------|---------|------|-----------------------|
| `Fa0/0` | `10.255.0.14/30` | To `FW-EDGE Fa1/0` | OSPF area 0, MD5 auth |
| `Fa1/0` | `10.255.0.1/30` | To `DC-EDGE Fa0/0` | OSPF area 0, MD5 auth |
| `Fa2/0` | `10.255.0.9/30` | To `HQ-DIST Fa0/0` | OSPF area 0, MD5 auth |
| `Fa3/0` | `10.255.0.17/30` | To `BR-EDGE Fa2/0` (backup) | `ip ospf cost 50`, `ip access-group ACL_WAN_BR_IN in`, MD5 auth |
| `Loopback0` | `1.1.1.1/32` | Router ID, log source | OSPF area 0 |

`HQ-CORE` performs no NAT and originates no external route: it is a pure transit router.

### 5.3 `HQ-DIST` — HQ distribution, inter-VLAN routing, DHCP (`Loopback0 1.1.1.4/32`)

| Interface | Address | Role | Notable configuration |
|-----------|---------|------|-----------------------|
| `Fa0/0` | `10.255.0.10/30` | To `HQ-CORE Fa2/0` | OSPF area 0, MD5 auth |
| `Fa1/0` | none (802.1Q trunk) | To `SW-HQ-1` port 0, VLANs 10/20/99 | parent trunk, no address |
| `Fa1/0.10` | `10.10.10.1/24` | VLAN 10 gateway | `ip access-group ACL_HQ_USERS_IN in`, OSPF area 10 |
| `Fa1/0.20` | `10.10.20.1/24` | VLAN 20 gateway | OSPF area 10 |
| `Fa1/0.99` | `10.10.99.1/24` | VLAN 99 gateway | OSPF area 10, no DHCP pool |
| `Fa2/0` | none | Reserved — second HQ trunk | `shutdown` |
| `Loopback0` | `1.1.1.4/32` | Router ID, log source | OSPF area 10 |

### 5.4 `DC-EDGE` — Data Centre gateway, WAN transit, DHCP (`Loopback0 2.2.2.2/32`)

| Interface | Address | Role | Notable configuration |
|-----------|---------|------|-----------------------|
| `Fa0/0` | `10.255.0.2/30` | To `HQ-CORE Fa1/0` | OSPF area 0, MD5 auth |
| `Fa1/0` | `10.255.0.5/30` | To `BR-EDGE Fa0/0` (primary Branch path) | `ip access-group ACL_WAN_BR_IN in`, OSPF area 0, MD5 auth |
| `Fa2/0` | none (802.1Q trunk) | To `SW-DC-CORE` port 0, VLANs 30/31 | parent trunk, no address |
| `Fa2/0.30` | `10.20.30.1/24` | VLAN 30 infrastructure gateway | OSPF area 20 |
| `Fa2/0.31` | `10.20.31.1/24` | VLAN 31 application gateway | `ip access-group ACL_DC_APP_IN in`, OSPF area 20 |
| `Loopback0` | `2.2.2.2/32` | Router ID, log source | OSPF area 0 |

`DC-EDGE` keeps its loopback in area 0 because it holds two backbone interfaces and no site-local role
beyond the server VLANs; `HQ-DIST` and `BR-EDGE` place theirs in their site area. The consequence is visible
in the routing table and is called out in the verification plan so it reads as a decision, not a mistake.

### 5.5 `BR-EDGE` — Branch gateway, DHCP, guest isolation (`Loopback0 3.3.3.3/32`)

| Interface | Address | Role | Notable configuration |
|-----------|---------|------|-----------------------|
| `Fa0/0` | `10.255.0.6/30` | To `DC-EDGE Fa1/0` (primary) | OSPF area 0, MD5 auth |
| `Fa1/0` | none (802.1Q trunk) | To `SW-BR-1` port 0, VLANs 40/50 | parent trunk, no address |
| `Fa1/0.40` | `10.30.40.1/24` | VLAN 40 gateway | OSPF area 30 |
| `Fa1/0.50` | `10.30.50.1/24` | VLAN 50 guest gateway | `ip access-group ACL_GUEST_IN in`, `no cdp enable`, OSPF area 30 |
| `Fa2/0` | `10.255.0.18/30` | To `HQ-CORE Fa3/0` (backup) | `ip ospf cost 50`, OSPF area 0, MD5 auth |
| `Loopback0` | `3.3.3.3/32` | Router ID, log source | OSPF area 30 |

---

## 6. Loopback addresses and OSPF router IDs

| Device | `Loopback0` | OSPF router ID | Area of the loopback | Zone |
|--------|-------------|----------------|----------------------|------|
| `FW-EDGE` | `4.4.4.4/32` | `4.4.4.4` | 0 | Internet edge |
| `HQ-CORE` | `1.1.1.1/32` | `1.1.1.1` | 0 | HQ / backbone |
| `HQ-DIST` | `1.1.1.4/32` | `1.1.1.4` | 10 | HQ |
| `DC-EDGE` | `2.2.2.2/32` | `2.2.2.2` | 0 | Data Centre |
| `BR-EDGE` | `3.3.3.3/32` | `3.3.3.3` | 30 | Branch |

Loopbacks are the OSPF router ID, the syslog source address, the DNS query source address and the NTP source
address on every router. Deriving all four from one always-up interface means a physical interface flapping
or being renumbered never changes the device's identity: the router ID stays put (so no adjacency reset and
no LSDB churn), and log and time correlation stays keyed to one address per device.

---

## 7. Server and endpoint addressing

### 7.1 Statically addressed servers

| Host | Address | VLAN | Gateway | Platform | Service |
|------|---------|------|---------|----------|---------|
| `AUTO-SRV` | `10.10.99.10/24` | 99 | `10.10.99.1` | Docker `ubuntu:22.04` | Ansible / Netmiko control node (Part B) |
| *(reserved)* | `10.10.99.11/24` | 99 | `10.10.99.1` | — | Management jump host — see `TOPOLOGY_APPENDIX_COMPLEXITY.md` |
| `DNS` | `10.20.30.10/24` | 30 | `10.20.30.1` | Docker `ubuntu:22.04` | `dnsmasq`, authoritative for `corp.local` |
| `NTP` | `10.20.30.11/24` | 30 | `10.20.30.1` | Docker `ubuntu:22.04` | `chrony`, stratum-10 local source |
| `SYSLOG` | `10.20.30.12/24` | 30 | `10.20.30.1` | Docker `ubuntu:22.04` | `rsyslog`, UDP/TCP 514 collector |
| `APP-SRV` | `10.20.31.10/24` | 31 | `10.20.31.1` | Docker `ubuntu:22.04` | Application tier (listens on TCP 8080) |
| `FILE-SRV` | `10.20.31.11/24` | 31 | `10.20.31.1` | Docker `ubuntu:22.04` | File service (TCP 445 placeholder / HTTP index) |
| `WEB-SRV` | `10.40.200.10/24` | 200 | `10.40.200.1` | Docker `ubuntu:22.04` | Public web service (TCP 80), statically translated |

### 7.2 DHCP endpoints

| Host | VLAN | Expected lease | Gateway | DHCP server | Pool |
|------|------|----------------|---------|-------------|------|
| `PC1` | 10 | `10.10.10.21` | `10.10.10.1` | `HQ-DIST` | `VLAN10_HQ_USERS` |
| `PC5` | 10 | `10.10.10.22` | `10.10.10.1` | `HQ-DIST` | `VLAN10_HQ_USERS` |
| `PC2` | 20 | `10.10.20.21` | `10.10.20.1` | `HQ-DIST` | `VLAN20_HQ_CORP` |
| `PC7` | 20 | `10.10.20.22` | `10.10.20.1` | `HQ-DIST` | `VLAN20_HQ_CORP` |
| `PC3` | 40 | `10.30.40.21` | `10.30.40.1` | `BR-EDGE` | `VLAN40_BR_USERS` |
| `PC6` | 40 | `10.30.40.22` | `10.30.40.1` | `BR-EDGE` | `VLAN40_BR_USERS` |
| `PC4` | 50 | `10.30.50.21` | `10.30.50.1` | `BR-EDGE` | `VLAN50_BR_GUEST` |
| `PC-DMZ` | 200 | `10.40.200.21` | `10.40.200.1` | `FW-EDGE` | `VLAN200_DMZ` |

Lease order within a subnet depends on which host boots first, so `PC1`/`PC5` may hold `.21`/`.22` in either
order. The pass criterion is a correct subnet, mask, gateway, DNS server and domain name — not a specific
host address.

---

## 8. DHCP pools

| Pool | Router | Network | Excluded | Gateway | DNS | Domain | Option 42 (NTP) | Lease |
|------|--------|---------|----------|---------|-----|--------|-----------------|-------|
| `VLAN10_HQ_USERS` | `HQ-DIST` | `10.10.10.0/24` | `.1`–`.20` | `10.10.10.1` | `10.20.30.10` | `corp.local` | `10.20.30.11` | 2 days |
| `VLAN20_HQ_CORP` | `HQ-DIST` | `10.10.20.0/24` | `.1`–`.20` | `10.10.20.1` | `10.20.30.10` | `corp.local` | `10.20.30.11` | 2 days |
| `VLAN30_DC_INFRA` | `DC-EDGE` | `10.20.30.0/24` | `.1`–`.20` | `10.20.30.1` | `10.20.30.10` | `corp.local` | `10.20.30.11` | 7 days |
| `VLAN31_DC_APP` | `DC-EDGE` | `10.20.31.0/24` | `.1`–`.20` | `10.20.31.1` | `10.20.30.10` | `corp.local` | `10.20.30.11` | 7 days |
| `VLAN40_BR_USERS` | `BR-EDGE` | `10.30.40.0/24` | `.1`–`.20` | `10.30.40.1` | `10.20.30.10` | `corp.local` | `10.20.30.11` | 2 days |
| `VLAN50_BR_GUEST` | `BR-EDGE` | `10.30.50.0/24` | `.1`–`.20` | `10.30.50.1` | `10.20.30.10` | `guest.corp.local` | *(none)* | 4 hours |
| `VLAN200_DMZ` | `FW-EDGE` | `10.40.200.0/24` | `.1`–`.20` | `10.40.200.1` | `10.20.30.10` | `dmz.corp.local` | *(none)* | 8 hours |

Design points visible in this table:

- **No pool on VLAN 99.** The management VLAN is static-only (`REVIEW_FINDINGS.md` R-07).
- **The guest pool is deliberately different.** A four-hour lease matches transient guest devices and keeps
  the pool from exhausting; `guest.corp.local` rather than `corp.local` means a guest host's DHCP output is
  self-evidently from the guest scope, which is the client-side proof that scope separation works; and no
  option 42 is offered because guests have no reason to be given the enterprise time source.
- **The two Data Centre pools are expected to show zero leases**, because every production host on those
  VLANs is statically addressed. The pools exist for transient test and staging hosts. Zero leases in
  `show ip dhcp pool` is the correct result there, not a fault.

---

## 9. Infrastructure service addresses

| Service | Address | Port(s) | Consumed by | Configured on the router as |
|---------|---------|---------|-------------|-----------------------------|
| DNS | `10.20.30.10` | UDP/TCP 53 | all routers, all hosts | `ip name-server 10.20.30.10` |
| NTP | `10.20.30.11` | UDP 123 | all routers, corporate hosts | `ntp server 10.20.30.11 prefer` |
| Syslog | `10.20.30.12` | UDP 514 | all routers | `logging host 10.20.30.12` |

Routers source DNS, NTP and syslog traffic from `Loopback0` (`ip domain-lookup source-interface`,
`ntp source`, `logging source-interface`), so all three service logs are keyed to the same stable per-device
address.

---

## 10. Forward DNS records (`corp.local`)

Served by `dnsmasq` on `DNS`; `PTR` records are configured for every entry.

| Name | Address |
|------|---------|
| `fw-edge.corp.local` | `4.4.4.4` |
| `hq-core.corp.local` | `1.1.1.1` |
| `hq-dist.corp.local` | `1.1.1.4` |
| `dc-edge.corp.local` | `2.2.2.2` |
| `br-edge.corp.local` | `3.3.3.3` |
| `auto.corp.local` | `10.10.99.10` |
| `dns.corp.local` | `10.20.30.10` |
| `ntp.corp.local` | `10.20.30.11` |
| `syslog.corp.local` | `10.20.30.12` |
| `app.corp.local` | `10.20.31.10` |
| `file.corp.local` | `10.20.31.11` |
| `web.corp.local` | `10.40.200.10` |

---

## 11. Address utilisation summary

| Block | Allocated | In use | Free |
|-------|-----------|--------|------|
| `10.10.0.0/16` (HQ) | 3 × /24 | VLANs 10, 20, 99 | 251 × /24 |
| `10.20.0.0/16` (DC) | 2 × /24 | VLANs 30, 31 | 252 × /24 |
| `10.30.0.0/16` (BR) | 2 × /24 | VLANs 40, 50 | 252 × /24 |
| `10.40.0.0/16` (DMZ) | 1 × /24 | VLAN 200 | 253 × /24 |
| `10.255.0.0/24` (WAN) | 5 × /30 | 5 links | 59 × /30 |
| Loopbacks | 5 × /32 | 5 routers | — |

Total routed prefixes in the OSPF domain: 8 VLAN /24s + 5 WAN /30s + 5 loopback /32s + 1 external default
= **19 prefixes**, which is the count to expect in `show ip route` on any router once the domain has
converged.

---

## 12. Change control

Adding a VLAN: pick the next unused ID, address it `10.<site>.<vlan>.0/24`, add the subinterface, the DHCP
pool with `.1`–`.20` excluded, and the `network … area <site>` statement. Nothing outside that site's area
changes.

Adding a site: take the next site octet (`10.50.0.0/16`), the next WAN /30 (`10.255.0.20/30`), and the next
area (50). Then — and this is the step that is easy to miss — **extend every deny-list ACL that enumerates
enterprise space**: `ACL_NAT_INSIDE`, `ACL_INTERNET_IN`, `ACL_GUEST_IN` and `ACL_WAN_BR_IN`. Omitting that
step is exactly the defect recorded as R-06 in [REVIEW_FINDINGS.md](REVIEW_FINDINGS.md), where adding the DMZ
silently granted the guest VLAN access to it.
