# Node Inventory — every node, its purpose, its addressing, its configuration

44 nodes. This document exists to answer one question for each of them: *what does
this device do, and where is the configuration that makes it do it?* No node is
present for visual weight.

Companion documents: [`TOPOLOGY.md`](TOPOLOGY.md) (cabling and diagrams),
[`IP_ADDRESSING.md`](IP_ADDRESSING.md) (authoritative addressing),
[`LINK_MAP.md`](LINK_MAP.md) (live export), [`REVIEW_FINDINGS.md`](REVIEW_FINDINGS.md)
(defects found and fixed).

## Summary

| Class | Count | Configuration artefact |
|-------|------:|------------------------|
| Dynamips c7200 routers | 5 | `configs/<NAME>.cfg` — full IOS startup configuration |
| GNS3 Ethernet switches | 17 | `configs/switches/ports_mapping.json` — per-port VLAN/type |
| Docker Ubuntu servers | 9 | `configs/linux/<name>-setup.sh` + `configs/netplan/<name>.yaml` |
| VPCS endpoints | 10 | `configs/vpcs/PC*.txt` |
| NAT cloud | 1 | GNS3 node properties — no user configuration |
| Ethernet hubs (transit) | 2 | none by design — addressing lives on the attached router interfaces |
| **Total** | **44** | |

The assessment minimum is 4 routers, 6 switches and one Linux automation server.
This build provides 5, 17 and 9 — but density is only defensible if each addition
carries policy or service that the minimum could not. §7 sets out that argument
node by node.

---

## 1. Routers (5)

Each runs a complete IOS startup configuration validated by
`python3 scripts/validate_configs.py`.

| Node | Purpose | Interfaces and addresses | OSPF role | Config |
|------|---------|--------------------------|-----------|--------|
| `FW-EDGE` | Internet edge firewall. PAT for all zones; static port translations publishing `WEB-SRV:80` and `APP-SRV:8080`; perimeter ingress filter; DMZ gateway | `Fa0/0` DHCP (outside, via ISP-Cloud), `Fa1/0` `10.255.0.17/30`, `Fa2/0.60` `10.60.60.1/24`, `Fa3/0` reserved/shut, `Lo0` `4.4.4.4/32` | ASBR — sole default-route originator; area 0 | [`configs/FW-EDGE.cfg`](../configs/FW-EDGE.cfg) |
| `HQ-CORE` | Area 0 backbone core. Pure transit: no NAT, no host VLANs, no external origination. Four adjacencies make it the backbone hub | `Fa0/0` `10.255.0.18/30`, `Fa1/0` `10.255.0.1/30`, `Fa2/0` `10.255.0.9/30`, `Fa3/0` `10.255.0.21/30` (cost 50), `Lo0` `1.1.1.1/32` | internal, area 0 | [`configs/HQ-CORE.cfg`](../configs/HQ-CORE.cfg) |
| `HQ-DIST` | HQ distribution. 802.1Q router-on-a-stick gateways for VLAN 10/20/99; DHCP for the two user VLANs | `Fa0/0` `10.255.0.10/30`, `Fa2/0.10` `10.10.10.1/24`, `Fa2/0.20` `10.10.20.1/24`, `Fa2/0.99` `10.10.99.1/24`, `Fa1/0` shut, `Fa3/0` reserved/shut, `Lo0` `1.1.1.4/32` | ABR area 0 ↔ 10 | [`configs/HQ-DIST.cfg`](../configs/HQ-DIST.cfg) |
| `DC-EDGE` | Data Centre gateway and primary Branch WAN transit. VLAN 30 gateway; DHCP for transient server hosts; primary-path guest enforcement | `Fa0/0` `10.255.0.2/30`, `Fa1/0` `10.255.0.5/30`, `Fa3/0.30` `10.20.30.1/24`, `Fa2/0` shut, `Lo0` `2.2.2.2/32` | ABR area 0 ↔ 20 | [`configs/DC-EDGE.cfg`](../configs/DC-EDGE.cfg) |
| `BR-EDGE` | Branch gateway. VLAN 40/50 gateways; DHCP for both; first-hop guest containment; the only dual-homed site | `Fa0/0` `10.255.0.6/30`, `Fa2/0` `10.255.0.22/30` (cost 50), `Fa3/0.40` `10.30.40.1/24`, `Fa3/0.50` `10.30.50.1/24`, `Fa1/0` shut, `Lo0` `3.3.3.3/32` | ABR area 0 ↔ 30 | [`configs/BR-EDGE.cfg`](../configs/BR-EDGE.cfg) |

### Services per router

| Service | `FW-EDGE` | `HQ-CORE` | `HQ-DIST` | `DC-EDGE` | `BR-EDGE` |
|---------|:---------:|:---------:|:---------:|:---------:|:---------:|
| Inter-VLAN routing (802.1Q) | VLAN 60 | — | VLAN 10/20/99 | VLAN 30 | VLAN 40/50 |
| OSPF | ASBR a0 + a0 DMZ | a0 | ABR a0/a10 | ABR a0/a20 | ABR a0/a30 |
| OSPF area 0 MD5 auth *(enhancement)* | yes | yes | yes | yes | yes |
| DHCP server | `VLAN60_DMZ` | — | `VLAN10`, `VLAN20` | `VLAN30` | `VLAN40`, `VLAN50` |
| SSH v2 + `ACL_VTY` | yes | yes | yes | yes | yes |
| NAT | PAT + 2 static | — | — | — | — |
| ACLs applied | `ACL_OUTSIDE_IN`, `ACL_DMZ_IN`, `ACL_VTY` | `ACL_WAN_BR_IN`, `ACL_VTY` | `ACL_HQ_USERS_IN`, `ACL_VTY` | `ACL_WAN_BR_IN`, `ACL_VTY` | `ACL_GUEST_IN`, `ACL_VTY` |
| DNS client | yes | yes | yes | yes | yes |
| NTP client (`Lo0` source) | yes | yes | yes | yes | yes |
| Syslog export (`Lo0` source) | yes | yes | yes | yes | yes |

---

## 2. Layer 2 transit nodes (3)

These carry no configuration of their own. That is not the same as carrying no
function: each is a real segment on a real path, and the addressing sits on the
router interfaces attached to it. Removing any of the three breaks a path.

| Node | GNS3 type | Purpose | Addressing |
|------|-----------|---------|------------|
| `Internet-NAT` | NAT cloud | Simulated Internet and the upstream DHCP server that leases `FW-EDGE Fa0/0` its outside global address | GNS3-managed pool (default `192.168.122.0/24`) |
| `ISP-Cloud` | Ethernet hub | ISP access segment between `Internet-NAT` and `FW-EDGE Fa0/0`. Models the provider handoff as a distinct segment, so the perimeter is a boundary between two named networks rather than a cable | none — transparent at Layer 2 |
| `WAN-Cloud` | Ethernet hub | Backup WAN segment between `HQ-CORE Fa3/0` and `BR-EDGE Fa2/0`. Models a carrier Ethernet service | none — `10.255.0.20/30` lives on the two router interfaces |

**Why inserting a hub changes no configuration.** An Ethernet hub is transparent
at Layer 2: it floods every frame to every other port and holds no address. So
`HQ-CORE Fa3/0` and `BR-EDGE Fa2/0` remain a single IP subnet, `10.255.0.20/30`,
and OSPF still forms one adjacency across it as a broadcast segment with a DR/BDR
election. The `/30` mask is what actually enforces the point-to-point nature:
because only two host addresses exist, no third device can be addressed onto the
segment even though a hub would happily flood to it.

Two consequences worth being explicit about, because a marker may ask:

1. A hub is a shared collision domain with no filtering, so anything attached to
   `WAN-Cloud` would see all traffic crossing it. Only the two routers are
   attached, and the `/30` prevents a third from being addressed.
2. OSPF on a hub segment elects a DR and BDR, which a true point-to-point link
   would not. `ip ospf network point-to-point` on both ends would suppress the
   election and the type-2 network LSA. It is deliberately left at the default so
   the election is visible in `show ip ospf neighbor` as assessment evidence; the
   optimisation is noted as a production improvement.

---

## 3. Switches (17)

GNS3 built-in Ethernet switches. Configuration is the per-port VLAN and type
matrix in [`configs/switches/ports_mapping.json`](../configs/switches/ports_mapping.json),
applied through the GNS3 API by `scripts/apply_on_mac.py`. Trunk ports are
`dot1q` with native VLAN 1 (unused); host ports are `access` on their data VLAN.

### 3.1 DMZ (1)

| Node | Role | Uplink | Host ports |
|------|------|--------|-----------|
| `SW-DMZ-1` | DMZ access fabric. The only switch outside the trusted zones | `Eth0` `dot1q` → `FW-EDGE Fa2/0` | `Eth1` v60 `WEB-SRV`, `Eth2` v60 `APP-SRV`, `Eth3` v60 `PC-DMZ` |

### 3.2 Headquarters (6)

| Node | Role | Uplink | Host ports |
|------|------|--------|-----------|
| `SW-HQ-DIST` | HQ aggregation. Single point where the `HQ-DIST` ROAS trunk fans out to four access switches, so the access layer can grow without another router port | `Eth0` `dot1q` → `HQ-DIST Fa2/0` | none — aggregation only: `Eth1`→`SW-HQ-1`, `Eth2`→`SW-HQ-2`, `Eth3`→`SW-HQ-3`, `Eth5`→`SW-HQ-4` |
| `SW-HQ-1` | HQ access, mixed user and management. Also the path to the management island | `Eth4` `dot1q` → `SW-HQ-DIST Eth1` | `Eth1` v10 `PC1`, `Eth2` v99 `AUTO-SRV`, `Eth5` v99 → `MGMT-SW` |
| `SW-HQ-2` | HQ corporate access | `Eth2` `dot1q` → `SW-HQ-DIST Eth2` | `Eth1` v20 `PC2` |
| `SW-HQ-3` | HQ user access, second block | `Eth0` `dot1q` → `SW-HQ-DIST Eth3` | `Eth1` v10 `PC5` |
| `SW-HQ-4` | HQ corporate access, second block | `Eth0` `dot1q` → `SW-HQ-DIST Eth5` | `Eth1` v20 `PC8` |
| `MGMT-SW` | Dedicated management switch. Physically separates the bastion from the user access fabric | `Eth0` **access v99** → `SW-HQ-1 Eth5` | `Eth1` v99 `JUMP-SRV` |

`MGMT-SW` is the one switch reached over an **access** port rather than a trunk.
It carries a single VLAN, so tagging would add nothing: VLAN 99 travels untagged
between `SW-HQ-1 Eth5` and `MGMT-SW Eth0`, both access ports on VLAN 99. The
practical benefit is that a mis-set trunk cannot leak another VLAN onto the
management island — the segment is incapable of carrying one.

### 3.3 Data Centre (5)

| Node | Role | Uplink | Host ports |
|------|------|--------|-----------|
| `SW-DC-CORE` | Data Centre aggregation for the `DC-EDGE` ROAS trunk | `Eth0` `dot1q` → `DC-EDGE Fa3/0` | none — aggregation: `Eth1`→`SW-DC-1`, `Eth2`→`SW-DC-2`, `Eth3`→`SW-DC-3`, `Eth5`→`SW-DC-4` |
| `SW-DC-1` | Core infrastructure access — the three services every router depends on | `Eth6` `dot1q` → `SW-DC-CORE Eth1` | `Eth1` v30 `DNS`, `Eth2` v30 `NTP`, `Eth3` v30 `SYSLOG` |
| `SW-DC-2` | Staging / expansion access. Ports pre-provisioned on VLAN 30 so a replacement or test server can be attached with no router change | `Eth6` `dot1q` → `SW-DC-CORE Eth2` | `Eth1`–`Eth3` v30, currently unpopulated |
| `SW-DC-3` | File service access | `Eth0` `dot1q` → `SW-DC-CORE Eth3` | `Eth1` v30 `FILE-SRV` |
| `SW-DC-4` | Monitoring access | `Eth0` `dot1q` → `SW-DC-CORE Eth5` | `Eth1` v30 `MON-SRV` |

Splitting five servers across four access switches is a fault-domain decision, not
padding. `DNS`, `NTP` and `SYSLOG` are the management plane; `FILE-SRV` is a user
service; `MON-SRV` is the break-glass path. Putting them on one switch would mean
one switch failure takes out name resolution, time, logging, file access and the
ability to observe any of it simultaneously. `SW-DC-2` gives the `VLAN30` DHCP pool
a genuine purpose — without it that pool would have no possible client.

### 3.4 Branch (5)

| Node | Role | Uplink | Host ports |
|------|------|--------|-----------|
| `SW-BR-DIST` | Branch aggregation for the `BR-EDGE` ROAS trunk | `Eth0` `dot1q` → `BR-EDGE Fa3/0` | none — aggregation: `Eth1`→`SW-BR-1`, `Eth2`→`SW-BR-2`, `Eth3`→`SW-BR-3`, `Eth5`→`SW-BR-4` |
| `SW-BR-1` | Branch staff access | `Eth6` `dot1q` → `SW-BR-DIST Eth1` | `Eth1` v40 `PC3`, `Eth3` v40 `PC7` |
| `SW-BR-2` | Branch **guest** access | `Eth6` `dot1q` → `SW-BR-DIST Eth2` | `Eth1` v50 `PC4` |
| `SW-BR-3` | Branch staff access, second block | `Eth0` `dot1q` → `SW-BR-DIST Eth3` | `Eth1` v40 `PC6` |
| `SW-BR-4` | Branch **guest** access, second block | `Eth0` `dot1q` → `SW-BR-DIST Eth5` | `Eth1` v50 `PC9` |

Staff and guest are on **separate physical switches** as well as separate VLANs.
That is what makes the guest-isolation evidence meaningful: `PC4` and `PC3` are not
merely tagged differently, they are on different access switches converging on one
enforcement point, `ACL_GUEST_IN` on `BR-EDGE Fa3/0.50`.

### 3.5 Ports cabled but held inactive

Three router ports are cabled to an access switch **and** administratively shut,
and three switch-to-switch cross-links must be removed. Both are consequences of
the same platform limit: the GNS3 built-in switch implements no spanning tree, so
the Layer 2 topology has to be a tree by construction.

| Held down | Reason |
|-----------|--------|
| `HQ-DIST Fa1/0` → `SW-HQ-1 Eth0` | `SW-HQ-1` is also reachable via `SW-HQ-DIST`; only one path may be active |
| `DC-EDGE Fa2/0` → `SW-DC-1 Eth0` | `SW-DC-1` is also reachable via `SW-DC-CORE` |
| `BR-EDGE Fa1/0` → `SW-BR-1 Eth0` | `SW-BR-1` is also reachable via `SW-BR-DIST` |

| Must be deleted in GNS3 | Loop it closes |
|-------------------------|----------------|
| `SW-HQ-1 Eth7` ↔ `SW-HQ-2 Eth0` | `SW-HQ-1` – `SW-HQ-2` – `SW-HQ-DIST` – `SW-HQ-1` |
| `SW-DC-1 Eth7` ↔ `SW-DC-2 Eth0` | `SW-DC-1` – `SW-DC-2` – `SW-DC-CORE` – `SW-DC-1` |
| `SW-BR-1 Eth7` ↔ `SW-BR-2 Eth0` | `SW-BR-1` – `SW-BR-2` – `SW-BR-DIST` – `SW-BR-1` |

The three shut router ports do **not** fix the three cross-links: they are
independent loops. See [`REVIEW_FINDINGS.md`](REVIEW_FINDINGS.md) R-02.

---

## 4. Docker servers (9)

Ubuntu containers. Each has an idempotent setup script and a matching netplan
file; addresses in the two are cross-checked and agree. Every script ends with a
self-check so a partial run is visibly distinguishable from a successful one.

| Node | Address | VLAN | Gateway | Service and why it exists | Config |
|------|---------|-----:|---------|---------------------------|--------|
| `DNS` | `10.20.30.10/24` | 30 | `10.20.30.1` | `dnsmasq` authoritative for `corp.local`, forwarding to `8.8.8.8`/`1.1.1.1`. A/PTR records for all 5 routers, 9 servers and 7 gateways. Consumed by every router (`ip name-server`) and every DHCP client | [`dns-setup.sh`](../configs/linux/dns-setup.sh) |
| `NTP` | `10.20.30.11/24` | 30 | `10.20.30.1` | `chrony`, `local stratum 10` so it is authoritative offline. Routers sync at stratum 11. Prerequisite for ordering syslog across five devices | [`ntp-setup.sh`](../configs/linux/ntp-setup.sh) |
| `SYSLOG` | `10.20.30.12/24` | 30 | `10.20.30.1` | `rsyslog` on UDP/TCP 514. Per-device files in `/var/log/network/` plus one merged time-ordered file | [`syslog-setup.sh`](../configs/linux/syslog-setup.sh) |
| `FILE-SRV` | `10.20.30.13/24` | 30 | `10.20.30.1` | Internal HTTP file share. Deliberately **not** published by any NAT entry — reachable from trusted zones only, which is what makes the staff-vs-guest access contrast demonstrable | [`file-srv-setup.sh`](../configs/linux/file-srv-setup.sh) |
| `MON-SRV` | `10.20.30.14/24` | 30 | `10.20.30.1` | Monitoring. `:9090/health` runs a live reachability sweep across 14 targets, producing verification evidence as a single artefact. Also the break-glass SSH origin permitted by `ACL_VTY` | [`mon-srv-setup.sh`](../configs/linux/mon-srv-setup.sh) |
| `WEB-SRV` | `10.60.60.10/24` | 60 | `10.60.60.1` | `nginx`. The enterprise's only Internet-reachable service, published by static PAT on TCP 80 | [`web-srv-setup.sh`](../configs/linux/web-srv-setup.sh) |
| `APP-SRV` | `10.60.60.11/24` | 60 | `10.60.60.1` | Application tier behind the web tier, published by static PAT on TCP 8080 | [`app-srv-setup.sh`](../configs/linux/app-srv-setup.sh) |
| `AUTO-SRV` | `10.10.99.10/24` | 99 | `10.10.99.1` | **The Linux automation server the brief requires.** Ansible + Netmiko, inventory of all 5 routers keyed by loopback. Part B control node | [`auto-srv-setup.sh`](../configs/linux/auto-srv-setup.sh) |
| `JUMP-SRV` | `10.10.99.11/24` | 99 | `10.10.99.1` | SSH bastion for interactive administration, separate from the automation path so the two have distinct audit trails | [`jump-srv-setup.sh`](../configs/linux/jump-srv-setup.sh) |

`AUTO-SRV` and `JUMP-SRV` are the only two hosts named individually in `ACL_VTY`
on all five routers. That is what turns `ACL_VTY` into an enforced control rather
than a decoration: automation is subject to exactly the same access restriction as
a human administrator, and neither can administer a router from a user VLAN.

---

## 5. VPCS endpoints (10)

All ten take addressing by **DHCP**, so the DHCP requirement is demonstrated end
to end. Full detail in [`configs/vpcs/README.md`](../configs/vpcs/README.md).

| Node | VLAN | Subnet | Gateway | DHCP server | Switch/port | Purpose |
|------|-----:|--------|---------|-------------|-------------|---------|
| `PC1` | 10 | `10.10.10.0/24` | `10.10.10.1` | `HQ-DIST` | `SW-HQ-1 Eth1` | HQ user |
| `PC5` | 10 | `10.10.10.0/24` | `10.10.10.1` | `HQ-DIST` | `SW-HQ-3 Eth1` | HQ user, proves a second access block gets the same scope |
| `PC2` | 20 | `10.10.20.0/24` | `10.10.20.1` | `HQ-DIST` | `SW-HQ-2 Eth1` | HQ corporate |
| `PC8` | 20 | `10.10.20.0/24` | `10.10.20.1` | `HQ-DIST` | `SW-HQ-4 Eth1` | HQ corporate, second access block |
| `PC3` | 40 | `10.30.40.0/24` | `10.30.40.1` | `BR-EDGE` | `SW-BR-1 Eth1` | Branch staff — the positive control for cross-WAN access |
| `PC7` | 40 | `10.30.40.0/24` | `10.30.40.1` | `BR-EDGE` | `SW-BR-1 Eth3` | Branch staff |
| `PC6` | 40 | `10.30.40.0/24` | `10.30.40.1` | `BR-EDGE` | `SW-BR-3 Eth1` | Branch staff, second access block |
| `PC4` | 50 | `10.30.50.0/24` | `10.30.50.1` | `BR-EDGE` | `SW-BR-2 Eth1` | Branch **guest** — the negative control for isolation |
| `PC9` | 50 | `10.30.50.0/24` | `10.30.50.1` | `BR-EDGE` | `SW-BR-4 Eth1` | Branch guest, second access block |
| `PC-DMZ` | 60 | `10.60.60.0/24` | `10.60.60.1` | `FW-EDGE` | `SW-DMZ-1 Eth3` | DMZ maintenance host — proves the DMZ has its own DHCP scope and its own egress policy |

`PC3` and `PC4` are the pair that carries most of the segmentation evidence: same
site, same fabric, adjacent switches, opposite policy outcomes.

> **Discrepancy to resolve before screenshots.** A briefing note described
> `PC5`–`PC9` as Branch hosts. The live topology export
> ([`LINK_MAP.md`](LINK_MAP.md) links 28 and 44) has `PC5` on `SW-HQ-3` and `PC8`
> on `SW-HQ-4`, both at HQ. This document follows the export, because that is what
> the screenshots will show. If Branch-only numbering is preferred, move `PC5` and
> `PC8` to `SW-BR-3`/`SW-BR-4` in GNS3 — no router configuration changes, because
> both would then take a Branch scope by DHCP. Do not change only the document.

---

## 6. Requirement-to-node traceability

The ten configurations Part A requires, and the specific nodes that implement each.
Anything not in this table is either supporting infrastructure or an enhancement
(OSPF MD5 authentication, the cost-engineered redundant WAN, and the commented-out CBAC
block) rather than a rubric item.

| Required service | Implemented on | Verified by |
|------------------|----------------|-------------|
| VLANs | 7 data VLANs across 17 switches (`ports_mapping.json`); VLAN 1 unused | `CHECKS.md` §2 |
| Inter-VLAN routing | 802.1Q ROAS: `HQ-DIST Fa2/0.10/.20/.99`, `DC-EDGE Fa3/0.30`, `BR-EDGE Fa3/0.40/.50`, `FW-EDGE Fa2/0.60` | `CHECKS.md` §2, §5 |
| OSPF | Process 1, areas 0/10/20/30, 5 routers, 5 adjacencies, one ASBR, three ABRs | `CHECKS.md` §3 |
| DHCP | 6 pools on 3 routers serving 10 endpoints, with gateway, DNS, domain-name, option 42 and per-scope leases | `CHECKS.md` §4 |
| SSH | SSHv2 + local AAA + `ACL_VTY` on both VTY ranges, all 5 routers; `AUTO-SRV` and `JUMP-SRV` as the only permitted origins | `CHECKS.md` §6.4 |
| ACLs | 6 named ACLs at 7 enforcement points | `CHECKS.md` §6 |
| NAT | PAT for 4 zones + 2 static port translations publishing DMZ services | `CHECKS.md` §7 |
| DNS | `dnsmasq` on `DNS`, consumed by 5 routers and 10 DHCP clients | `CHECKS.md` §8.1 |
| NTP | `chrony` on `NTP`, 5 router clients sourced from `Loopback0` | `CHECKS.md` §8.2 |
| Syslog | `rsyslog` on `SYSLOG`, 5 router senders sourced from `Loopback0` | `CHECKS.md` §8.3 |
| Linux automation server | `AUTO-SRV` with Ansible, Netmiko and a loopback-keyed inventory | `CHECKS.md` §8.4 |

---

## 7. Why the node count is justified, not decorative

The brief asks for 4 routers, 6 switches and 1 automation server. Density beyond a
minimum is only worth marks if it buys capability, so here is the argument for each
group, and the honest cost.

| Addition beyond minimum | What it makes possible that the minimum cannot |
|-------------------------|-----------------------------------------------|
| `FW-EDGE` (5th router) | A dedicated security boundary. Without it, the Internet edge, PAT, perimeter filtering and the OSPF backbone all collapse onto `HQ-CORE`, and there is no zone where an inbound-initiated session can safely terminate |
| DMZ zone: `SW-DMZ-1`, `WEB-SRV`, `APP-SRV`, `PC-DMZ` | An Internet-reachable service at all. Without a DMZ the NAT requirement can only be demonstrated as outbound PAT; with it, static port translation, inbound filtering and DMZ egress containment become demonstrable |
| `WAN-Cloud` + `HQ-CORE Fa3/0` + `BR-EDGE Fa2/0` | Layer 3 redundancy and a failover test. It also creates the second enforcement point problem that `ACL_WAN_BR_IN` on two interfaces solves — a genuine design lesson rather than an extra line |
| `MGMT-SW` + `JUMP-SRV` | Separation of interactive administration from automated administration, and a management segment that is physically incapable of carrying a user VLAN |
| `MON-SRV` | An observability plane, and a break-glass administrative path that survives loss of the HQ management VLAN |
| `FILE-SRV` | An internal-only service, which is the counter-example that makes the DMZ boundary meaningful: something deliberately *not* published |
| 4 access switches per site instead of 1 | Fault domains, and a staff/guest physical split that makes the isolation evidence credible rather than purely logical |
| `ISP-Cloud` | An explicit provider handoff, so the perimeter is a boundary between two named networks |

**The honest cost.** Five Dynamips routers are the entire resource budget on a
4 GB GNS3 VM — roughly 150 MB of real host RAM each with a calibrated `idlepc`.
The 17 switches and 10 VPCS nodes cost almost nothing because they run inside the
GNS3 VM's own process space, and the 9 containers share the VM kernel and cost tens
of megabytes each. That is precisely why the topology grows through switches,
containers and hubs rather than through more routers: the density is affordable
because of where it was added. The trade-off accepted in exchange is that the
switches have no CLI, no STP, no port security and no LACP — see
[`REVIEW_FINDINGS.md`](REVIEW_FINDINGS.md) R-16.
