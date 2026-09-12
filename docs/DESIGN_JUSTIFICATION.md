# Part A — Design Justification

This document explains *why* the Part A network is built the way it is: the architecture, the platform
choices forced by the host hardware, the addressing and routing model, the security model, and the
scalability path to a production-sized deployment. Addressing is defined in
[IP_ADDRESSING.md](IP_ADDRESSING.md); cabling and port roles in [TOPOLOGY.md](TOPOLOGY.md); test evidence
in [../verification/CHECKS.md](../verification/CHECKS.md).

---

## 1. Architecture

Three sites, each with a distinct role, connected by a routed WAN core:

| Site | Role | OSPF area | Gateway device(s) |
|------|------|-----------|-------------------|
| Headquarters | User population, management VLAN, automation host, Internet edge | 10 | `HQ-CORE`, `HQ-DIST` |
| Data Centre | Shared infrastructure services (DNS, NTP, Syslog) and WAN transit | 20 | `DC-EDGE` |
| Branch Office | Branch staff plus an isolated guest network | 30 | `BR-EDGE` |
| WAN backbone | Site interconnect only, no end hosts | 0 | all four routers |

### 1.1 Why HQ is split across two routers

`HQ-CORE` and `HQ-DIST` deliberately separate two different jobs:

- **`HQ-CORE` is the security boundary.** It owns the only interface that faces an untrusted network
  (`Fa0/0` to the GNS3 NAT cloud), performs PAT, filters inbound traffic, and originates the default route
  into OSPF. It holds no user VLANs, so a change to the user access layer can never accidentally modify the
  Internet edge.
- **`HQ-DIST` is the distribution/aggregation layer.** It terminates the 802.1Q trunk, provides the
  inter-VLAN gateways and the DHCP scopes for HQ, and acts as the area border router (ABR) for area 10.

This is the classic collapsed-core-plus-edge pattern. The practical benefit in this lab is *failure
containment*: a misconfigured subinterface or DHCP pool on `HQ-DIST` cannot break Internet reachability for
the Data Centre or Branch, because their default route comes from `HQ-CORE` over a separate adjacency.

### 1.2 Why the Data Centre is the WAN transit point

The WAN is a chain, `HQ-CORE — DC-EDGE — BR-EDGE`, rather than a direct HQ-to-Branch link. Two reasons:

1. **Traffic locality.** The overwhelming majority of Branch traffic is to shared services (DNS, NTP,
   Syslog, and in Part B the Ansible inventory targets). Putting the Data Centre in the middle means that
   traffic traverses one hop, not two.
2. **A single chokepoint for policy.** Every packet from the Branch toward either the Data Centre or HQ
   crosses `DC-EDGE Fa1/0`, which is where the second guest-isolation ACL (`ACL_WAN_BR_IN`) is enforced.
   One interface enforces policy for the whole remote site.

The trade-off is honest and worth stating: `DC-EDGE` is a single point of failure for the Branch. In a
production build the fix is a second Branch uplink directly to `HQ-CORE`, which OSPF would use as an equal
or backup path with no addressing changes — the `10.255.0.0/24` WAN supernet has 61 unused /30s reserved for
exactly this.

---

## 2. Platform and emulation choices

The whole design is constrained by the host: an **Apple M3 (arm64) laptop running the GNS3 VM with 4 GB of
RAM** and limited free disk (~44 GB). Every platform decision below follows from that constraint.

### 2.1 Cisco c7200 on Dynamips (routers)

| Requirement | c7200 / Dynamips | Alternative considered | Why the alternative was rejected |
|-------------|------------------|------------------------|----------------------------------|
| RAM per router | ~256–512 MB emulated, ~100–160 MB real host RAM | IOSv / IOSvL2 (QEMU) needs 512 MB–1 GB *real* RAM each | 4 routers x 512 MB exceeds the entire 4 GB GNS3 VM |
| CPU | Single MIPS core emulated; `idlepc` calibration drops idle CPU to a few percent | IOSv is a full x86 VM; under QEMU on arm64 it must be **software-emulated (TCG)**, not accelerated | x86-on-arm64 emulation is roughly an order of magnitude slower — boot times of many minutes and unstable OSPF hellos |
| Disk | ~120 MB IOS image | IOSv/CSR1000v images are 500 MB–1.5 GB each plus per-node disk overlays | Would consume a large share of the free disk before any project snapshots |
| Feature coverage | OSPF multi-area, DHCP server, NAT/PAT, named ACLs, 802.1Q subinterfaces, SSHv2, NTP client, syslog, `archive log config` | same | no feature gap for Part A |

**Consequence for the configs:** Dynamips c7200 hardware is modelled as an I/O controller in slot 0 plus
port adapters in slots 1–6. Using `C7200-IO-FE` in slot 0 and `PA-FE-TX` in slots 1 and 2 yields
`FastEthernet0/0`, `FastEthernet1/0` and `FastEthernet2/0`. This is why **every interface in this project is
FastEthernet** — no `GigabitEthernet`, no `Ethernet0/x` (a c3600/c2600-style name), and no interface numbers
outside the slots that actually exist. A config referencing `Gi0/0` looks plausible but silently fails to
apply on this platform, so the naming discipline is a correctness requirement, not cosmetics.

A useful side effect: because all links are 100 Mbit/s, the default OSPF cost is a uniform 1 on every
interface (`10^8 / 10^8`). Path selection is therefore purely a function of hop count, which makes the
routing table predictable and easy to verify against the expected output in `CHECKS.md`. No
`auto-cost reference-bandwidth` tuning is needed; if faster media were introduced later, that command would
become mandatory to keep the cost metric meaningful.

### 2.2 GNS3 built-in Ethernet switch (Layer 2)

The six access/aggregation switches are GNS3 *built-in* Ethernet switches rather than emulated Cisco
switches:

- **Cost:** they run inside the GNS3 VM's own process space with essentially zero RAM and CPU cost. Six
  IOSvL2 instances would need ~3 GB of RAM on their own — impossible here.
- **Capability match:** Part A needs exactly two Layer 2 behaviours — access port VLAN assignment and
  802.1Q tagging on trunks. The built-in switch implements both, which is sufficient to prove inter-VLAN
  routing, per-VLAN DHCP and VLAN-based ACL enforcement.
- **Accepted limitation:** the built-in switch has no CLI, no STP, no VTP, no port security, no
  `switchport trunk allowed vlan` pruning and no LACP. Those features are therefore out of scope for Part A
  and are called out here rather than silently omitted. If the assessment later requires port security or
  STP root election, the switch template must be swapped for IOSvL2 and the GNS3 VM given 8 GB of RAM.

Because there is no STP, the topology is deliberately kept **loop-free by design**: each switch has exactly
one path toward its router (`SW-HQ-2` and `SW-HQ-3` hang off `SW-HQ-1`; `SW-BR-2` hangs off `SW-BR-1`). A
redundant switch-to-switch link would create a broadcast storm with nothing to block it.

VLAN 1 is left completely unused and every VLAN is carried tagged. This avoids the native-VLAN mismatch
class of bug (untagged frames arriving at a router subinterface that only accepts tagged frames) and follows
the standard hardening guidance of not using the default VLAN for data.

### 2.3 Docker containers (services and automation)

`AUTO-SRV`, `DNS`, `NTP` and `SYSLOG` are Ubuntu 22.04 Docker nodes:

- **arm64-native.** Containers share the GNS3 VM kernel, so on an M3 host they execute native arm64 code
  with no CPU emulation penalty. A QEMU Ubuntu VM per service would each need ~1 GB RAM and, if an amd64
  image were used, full TCG emulation.
- **Footprint.** Four containers running `dnsmasq`, `chrony`, `rsyslog` and a Python/Ansible toolchain sit
  in tens of megabytes each, leaving headroom for the four Dynamips processes.
- **Part B readiness.** `AUTO-SRV` already installs `ansible` and `netmiko` (see
  `configs/linux/auto-srv-setup.sh`), so Part B automation runs from inside the topology and is subject to
  the same ACLs as any other host — which is what makes `ACL_VTY` a meaningful control rather than a
  decoration.
- **Accepted limitation.** Docker nodes do not persist filesystem changes outside the configured
  persistent directories, so the setup scripts are written to be **idempotent** and re-runnable
  (`ip addr add ... || true`) rather than assuming one-time execution.

### 2.4 Placement of services in the Data Centre

DNS, NTP and Syslog live on VLAN 30 behind `DC-EDGE`, not in HQ, because:

- they are consumed by all three sites, and the Data Centre is the WAN transit point, so it is the
  topological centre of the network;
- keeping them off the HQ management VLAN means the *automation* host (`AUTO-SRV`, VLAN 99) and the
  *service* hosts are in separate failure and security domains, while both are still permitted to manage the
  routers by `ACL_VTY`;
- routers point at `10.20.30.10` for DNS, `10.20.30.11` for time and `10.20.30.12` for logs, so a single
  subnet is the trust anchor for the entire management plane, which is easy to express as one ACL entry.

---

## 3. Addressing model

`10.0.0.0/8` is divided on a **site-aligned second octet**, which is the property that makes the plan
scalable:

| Block | Meaning |
|-------|---------|
| `10.10.0.0/16` | Headquarters — third octet is the VLAN ID (`10.10.10.0/24` = VLAN 10) |
| `10.20.0.0/16` | Data Centre — `10.20.30.0/24` = VLAN 30 |
| `10.30.0.0/16` | Branch Office — `10.30.40.0/24`, `10.30.50.0/24` |
| `10.255.0.0/24` | WAN point-to-point transit, carved into /30s |

Two design properties follow directly:

1. **Summarisable.** Each site is a single /16 that an ABR can summarise into the backbone with one
   `area <n> range` statement. The lab does not enable summarisation (with one router per area there is
   nothing to summarise), but the addressing does not have to change to enable it later.
2. **Greppable and ACL-friendly.** "All of HQ" is `10.10.0.0 0.0.255.255`, which is why the guest ACL on
   `BR-EDGE` can block an entire site in one line instead of enumerating VLANs. Because the third octet
   equals the VLAN ID, an address on a console screen immediately identifies its site and VLAN.

/30s are used for the WAN links because point-to-point links need exactly two host addresses; a /24 per WAN
link would waste 250 addresses each and inflate the routing table with unnecessarily large prefixes.

Loopbacks (`1.1.1.1`, `1.1.1.4`, `2.2.2.2`, `3.3.3.3`) provide stable router IDs and a stable syslog source
address. Deriving the OSPF router ID from a loopback rather than letting IOS pick the highest interface
address means the router ID never changes when a physical interface flaps or is renumbered — important
because a changing router ID forces a full adjacency reset and LSDB churn.

---

## 4. Routing design

### 4.1 Why OSPF, and why multi-area

OSPF is chosen over RIP and EIGRP:

- **vs RIP:** RIP's 15-hop diameter limit and 30-second periodic updates are unsuitable for a design meant
  to grow; OSPF's link-state flooding converges in seconds and carries no hop-count ceiling.
- **vs EIGRP:** EIGRP is simpler to configure but the design brief targets vendor-neutral,
  standards-based operation. OSPF (RFC 2328) allows the Branch or Data Centre gateway to be replaced with
  non-Cisco hardware without redesigning the routing protocol.
- **vs static routing:** with four routers and eight internal prefixes, static routing would require
  manual maintenance at every site for every change and would provide no automatic reconvergence.

Multi-area is used even though the lab is small, because the areas are the mechanism that makes the design
*scale*:

- Area 0 contains only the WAN /30s and the backbone loopbacks. Its LSDB is tiny and stable.
- Each site's LANs are in their own area, so a flapping access-layer subinterface at the Branch triggers
  SPF recalculation only inside area 30 and produces a single type-3 summary update in the backbone —
  instead of a full topology-wide SPF run.
- Every non-backbone area touches area 0 through exactly one ABR, satisfying OSPF's requirement that all
  areas connect to the backbone. There are no virtual links, which is a deliberate simplicity choice.

### 4.2 Specific routing decisions

| Decision | Reason |
|----------|--------|
| `passive-interface default` with explicit `no passive-interface` on WAN links | OSPF hellos are sent only where a neighbour is expected. LAN and server segments never receive hellos, which removes an information-disclosure vector and prevents a rogue host from forming an adjacency. LAN prefixes are still advertised. |
| `network <loopback> 0.0.0.0 area <n>` | advertises the /32 router ID so `ping <loopback>` and `logging source-interface Loopback0` work from any site |
| `default-information originate always` on `HQ-CORE` | the default route toward the Internet is learned by DHCP, whose lease timing is outside our control. `always` keeps a stable default in the backbone even while the lease is being renewed, which prevents a transient routing black hole for all three sites. |
| Default OSPF broadcast network type on the /30s | keeps the DR/BDR election visible in `show ip ospf neighbor` output, which is useful assessment evidence. `ip ospf network point-to-point` would be marginally more efficient (no DR election, no type-2 network LSA) and is the recommended next step for a production build. |
| `log-adjacency-changes detail` | every neighbour state transition is timestamped and shipped to the syslog collector, so adjacency flaps are diagnosable after the fact |
| No route redistribution | there is exactly one routing protocol and one externally-originated route (the default). Nothing needs redistributing, so there is no risk of a redistribution loop or of a metric-translation mistake. |

---

## 5. Security design

The design applies defence in depth across three planes.

### 5.1 Management plane

| Control | Implementation | Rationale |
|---------|----------------|-----------|
| No plaintext remote access | `ip ssh version 2` plus `transport input ssh` on all VTY lines | Telnet is disabled outright, not merely deprioritised, so credentials never cross the WAN in clear text |
| Source-restricted administration | `ACL_VTY` applied with `access-class ... in` on `line vty 0 4` **and** `line vty 5 15` | SSH is only accepted from the HQ management VLAN (`10.10.99.0/24`) and the Data Centre server VLAN (`10.20.30.0/24`). Protecting vty 5–15 as well closes the common gap where extra lines are created implicitly and left unguarded. |
| Credential hygiene | `enable secret` and `username admin ... secret` (both type-5/9 hashed), `service password-encryption` for remaining type-7 strings | avoids reversible cleartext passwords in `show running-config` output |
| Session hygiene | `exec-timeout 10 0` on VTY, `15 0` on console, `ip ssh time-out 60`, `ip ssh authentication-retries 2` | limits the window in which an abandoned session can be hijacked and slows credential guessing |
| Unused access paths closed | `line aux 0` with `no exec` and `transport input none`; `no ip http server`; `no ip http secure-server`; `no service pad` | removes management surfaces that are enabled by default and never used |
| Attribution | `login on-success log`, `login on-failure log`, `archive log config` with `notify syslog` and `hidekeys` | every login attempt and every configuration line entered is timestamped and exported to `10.20.30.12`, giving a tamper-evident audit trail off the device |
| Legal notice | `banner login` and `banner motd` on every router | required for enforceable unauthorised-access claims in most jurisdictions |

`hidekeys` matters specifically: without it, the configuration-change archive would ship secrets in plain
text to the syslog collector, turning an audit control into a credential leak.

### 5.2 Data plane — segmentation

| Control | Where | Rationale |
|---------|-------|-----------|
| VLAN separation | VLANs 10/20/99 at HQ, 30 at DC, 40/50 at Branch | broadcast domains are scoped per function, so an ARP or broadcast problem in the guest VLAN cannot affect the servers |
| Guest isolation | `ACL_GUEST_IN` inbound on `BR-EDGE Fa1/0.50` | enforced at the **first** Layer 3 hop, so denied guest traffic never enters the WAN and consumes no backbone bandwidth |
| Guest isolation, second pass | `ACL_WAN_BR_IN` inbound on `DC-EDGE Fa1/0` | defence in depth: if the branch ACL is removed or a guest host spoofs its way onto VLAN 40, the Data Centre still refuses guest-sourced traffic |
| Management VLAN isolation | `ACL_HQ_USERS_IN` inbound on `HQ-DIST Fa1/0.10` denies VLAN 10 → VLAN 99 | ordinary user workstations have no business reaching the automation host, which holds router credentials |
| Anti-spoofing at the edge | `ACL_INTERNET_IN` inbound on `HQ-CORE Fa0/0` denies source `10.0.0.0/8`, `127.0.0.0/8`, `169.254.0.0/16` | RFC 2827-style ingress filtering: a packet claiming an internal source address must not arrive from the Internet |
| Inbound management block | same ACL denies inbound TCP 22 and 23 | the NAT edge never accepts an administration session from the untrusted side, regardless of any future NAT port-forward mistake |
| No proxy ARP / no redirects | on all host-facing and WAN interfaces | prevents a host from being tricked into using the router as a MITM relay for off-subnet addresses |

**ACL entry ordering is a deliberate design element, not an accident.** In `ACL_GUEST_IN`, the DHCP permit
(`udp any eq bootpc any eq bootps`, which must use `any` as the source because a DHCP DISCOVER is sourced
from `0.0.0.0`) and the DNS permits to `10.20.30.10` sit **above** the deny rules. Without that ordering a
guest device would be unable to obtain an address or resolve a name, and the guest network would be
functionally dead rather than merely restricted. Every ACL also ends with an explicit
`deny ip any any log` or a deliberate `permit ip ... any`, so the implicit deny is never relied upon and
drops are always counted and logged.

Guest devices reach the Internet through PAT on `HQ-CORE` and can resolve names via `10.20.30.10`, but
cannot reach any HQ subnet, the Data Centre server subnet, the branch corporate VLAN, or the WAN transit
addresses. That is the intended "Internet-only guest" service definition.

### 5.3 Control plane

- OSPF adjacencies can only form on the two/three WAN interfaces per router because everything else is
  passive. This is the single most effective control-plane protection available without configuring
  authentication.
- `ACL_WAN_BR_IN` explicitly permits `ospf any any` as its first entry. This is intentional: relying on the
  trailing `permit ip any any` would work, but an explicit permit means the adjacency survives any future
  tightening of the tail of that ACL — a common outage cause.
- **Known gap:** OSPF MD5/SHA authentication (`ip ospf message-digest-key`) is not configured. It is the
  first thing to add in a production build; it is omitted here so that the neighbour-formation evidence in
  `CHECKS.md` isolates addressing and area configuration from authentication mismatches.

### 5.4 Why SSH keys are generated after boot rather than in the startup config

`crypto key generate rsa` is an **exec-mode** command, not a configuration command. It cannot appear in a
startup configuration, and pasting it into a config session either errors out or, on some releases, silently
does nothing. Three concrete consequences drove the decision to keep it out of `configs/*.cfg` entirely:

1. **Determinism.** A startup config that appears to enable SSH but does not would fail verification in a
   confusing way (`ssh` refused, `show ip ssh` reporting SSH disabled) with no obvious cause.
2. **Key generation depends on runtime state.** RSA key generation requires the hostname and
   `ip domain-name` to already be set, and consumes noticeable CPU on emulated MIPS hardware. Doing it after
   the device has booted and settled avoids a slow, blocking operation during config replay.
3. **Keys should never be a shared artefact.** Each device must have its own unique host key. Keeping key
   generation as a documented post-boot step (see the README) makes it obvious that the key is
   per-device and is regenerated if the lab is rebuilt.

The startup configs do everything that *is* configuration — `ip domain-name corp.local`, `ip ssh version 2`,
timeouts, retry limits, local user database, `transport input ssh`, and `access-class` — so the only
remaining step is one exec command per device.

---

## 6. Requirement-to-implementation traceability

| Requirement | Implementation | Where |
|-------------|----------------|-------|
| VLANs and inter-VLAN routing | 802.1Q router-on-a-stick subinterfaces | `HQ-DIST Fa1/0.10/.20/.99`, `DC-EDGE Fa2/0.30`, `BR-EDGE Fa1/0.40/.50` |
| Dynamic routing | OSPF process 1, areas 0/10/20/30, loopback router IDs, passive-by-default | all four routers |
| Dynamic addressing | six IOS DHCP pools with gateway, DNS, `domain-name`, NTP (option 42) and lease tuning | `HQ-DIST`, `DC-EDGE`, `BR-EDGE` |
| Internet access | PAT overload on `Fa0/0`, `ACL_NAT_INSIDE`, DHCP-learned upstream, default injected into OSPF | `HQ-CORE` |
| Secure remote access | SSHv2, local AAA, `ACL_VTY` on all VTY lines, post-boot RSA key | all four routers |
| Traffic filtering | `ACL_GUEST_IN`, `ACL_WAN_BR_IN`, `ACL_HQ_USERS_IN`, `ACL_INTERNET_IN`, `ACL_VTY` | see section 5 |
| Name resolution | `dnsmasq` authoritative for `corp.local`, forwarding to `8.8.8.8`; routers use `ip name-server` | `DNS` 10.20.30.10 |
| Time synchronisation | `chrony` stratum 10 serving `10.0.0.0/8`; routers use `ntp server ... prefer` + `ntp update-calendar` + `clock timezone AEST 10` | `NTP` 10.20.30.11 |
| Centralised logging | `rsyslog` on UDP/TCP 514; routers use `logging trap informational` sourced from `Loopback0` | `SYSLOG` 10.20.30.12 |
| Automation readiness | Ansible/Netmiko host on the management VLAN, permitted by `ACL_VTY` | `AUTO-SRV` 10.10.99.10 |

Correlated timestamps are the reason NTP and syslog are treated as one requirement in practice: without a
common clock, log entries from four routers cannot be ordered, so `clock timezone`,
`service timestamps log datetime msec localtime show-timezone` and the NTP client are all prerequisites for
the logging evidence in `CHECKS.md` to be usable.

---

## 7. Scalability analysis

### 7.1 Adding a site

Adding a fourth site requires no renumbering:

1. Allocate the next site /16 (`10.40.0.0/16`) and the next WAN /30 (`10.255.0.8/30` is taken;
   `10.255.0.12/30` is next — 61 of the 64 available remain free).
2. Configure the new gateway as an ABR: WAN link in area 0, site LANs in a new area 40.
3. Add the local DHCP pools and point the router at `10.20.30.10/.11/.12`.
4. No change is required on any existing router beyond the one new WAN interface and `network` statement on
   the transit router — existing area LSDBs are untouched because the new site's internal topology is hidden
   behind its ABR.

### 7.2 Growing an existing site

The third octet is the VLAN ID, so a site has 254 VLAN-aligned /24s available. `HQ-DIST Fa2/0` is already
cabled-and-reserved for a fourth HQ access switch. Each new VLAN needs one subinterface, one DHCP pool and
one `network ... area 10` statement; nothing outside area 10 changes.

### 7.3 Where this design would stop scaling, and what replaces it

Being explicit about limits is part of the analysis:

| Limit | Symptom | Remedy |
|-------|---------|--------|
| Router-on-a-stick trunk bandwidth | all inter-VLAN traffic for a site shares one 100 Mbit/s trunk, and the router CPU forwards every inter-VLAN packet | replace `HQ-DIST` with a Layer 3 switch doing SVI routing in hardware; addressing and OSPF configuration transfer unchanged |
| One router per area | area summarisation and stub areas have no effect yet | as sites gain routers, add `area <n> range` on each ABR and make leaf areas `stub`/`totally stubby` to shrink remote LSDBs |
| No STP on the built-in switches | no redundant Layer 2 paths are possible | swap the switch template for IOSvL2 with RSTP once the GNS3 VM has ≥8 GB RAM |
| `DC-EDGE` as sole Branch transit | Branch is isolated if `DC-EDGE` fails | add a second Branch uplink to `HQ-CORE`; OSPF will use it automatically |
| Single DNS/NTP/Syslog instance each | any one container is a single point of failure for the management plane | second instance per service in a different VLAN, advertised via a shared anycast address or simply as a second `ip name-server` / `ntp server` / `logging host` entry (the configs already support multiple entries) |
| Manual per-device configuration | configuration drift between four devices | this is precisely what Part B addresses: `AUTO-SRV` renders and pushes these configurations from templates, making the four files here the intended source of truth |
| Flat `10.0.0.0/8` NAT ACL | as sites are added, `ACL_NAT_INSIDE` needs an entry each time | the site-aligned second octet means one `permit 10.<site>.0.0 0.0.255.255` line per site, and the three existing lines could collapse to `permit 10.0.0.0 0.255.255.255` if per-site NAT policy is never needed |

### 7.4 Operational scalability

The configuration itself is written to be maintained at scale: named ACLs with `remark` lines instead of
numbered lists, `description` on every interface stating both ends of the link, ACLs defined before the
objects that reference them so the files replay cleanly in order, and one and only one block per interface
and per line range. These properties are what make the files safe to generate from a template in Part B —
a config with duplicate `interface` blocks or forward ACL references cannot be reliably rendered or
idempotently re-applied.
