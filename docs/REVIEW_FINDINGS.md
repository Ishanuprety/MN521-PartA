# Part A — Technical Review Findings Register

A structured review of the Part A package as it stood before this revision: the four IOS startup
configurations, the Linux and VPCS node configurations, the topology and addressing documents, and the
verification plan — checked against the live GNS3 project and against the Part A assessment requirements.

Each finding records what is wrong, how it was proved, why it matters, and what was changed. Findings marked
**Accepted risk** are deliberately not fixed, with the reason stated. Nothing in this register is
hypothetical: every entry is traceable to a specific line of a configuration file or a specific claim in a
document.

Severity is assessed against two axes — *does it stop the lab working* and *does it cost marks*:

| Severity | Meaning |
|----------|---------|
| **Critical** | Breaks a security control that the design claims to enforce, or makes a documented test impossible to pass |
| **High** | Causes a functional failure, or a documented claim that the build cannot substantiate |
| **Medium** | Design weakness, unnecessary attack surface, or documentation that diverges from the built lab |
| **Low** | Redundancy, imprecision or cosmetic inconsistency |

---

## Summary

| ID | Severity | Area | Finding | Status |
|----|----------|------|---------|--------|
| [R-01](#r-01) | High | IOS | `no ip domain-lookup` makes the documented DNS test impossible | Fixed |
| [R-02](#r-02) | High | IOS | Anti-spoofing ACE can drop the edge DHCP offer and all PAT return traffic | Fixed |
| [R-03](#r-03) | Critical | Design | Redundant WAN link bypasses the guest-isolation enforcement point | Fixed |
| [R-04](#r-04) | High | Docs | Documentation modelled 19 nodes; the live project has 32 | Fixed |
| [R-05](#r-05) | Medium | Design | Internet edge, PAT and OSPF core collapsed onto one router | Fixed |
| [R-06](#r-06) | Critical | Security | Guest VLAN had unrestricted internal access to the DMZ | Fixed |
| [R-07](#r-07) | Medium | Security | DHCP pool on the management VLAN auto-admits unknown hosts to the VTY-permitted subnet | Fixed |
| [R-08](#r-08) | Medium | Security | `ACL_VTY` permitted a whole /24 of management sources | Fixed |
| [R-09](#r-09) | Medium | Routing | OSPF adjacencies unauthenticated on a now-redundant backbone | Fixed |
| [R-10](#r-10) | High | Routing | Two routers would originate the default route after the edge split | Fixed |
| [R-11](#r-11) | Medium | IOS | NAT scope did not cover the DMZ block | Fixed |
| [R-12](#r-12) | Medium | IOS | `ip nat inside` on a trunk physical interface is silently inert | Fixed |
| [R-13](#r-13) | Medium | Linux | `auto-srv-setup.sh` overwrites `resolv.conf` before `apt-get`, breaking package install | Fixed |
| [R-14](#r-14) | Medium | Linux | Container setup scripts add a second address instead of replacing GNS3's | Fixed |
| [R-15](#r-15) | Medium | Linux | Syslog collector wrote all devices into one undifferentiated file | Fixed |
| [R-16](#r-16) | Low | Linux | DNS zone data omitted the servers added since the first build | Fixed |
| [R-17](#r-17) | Low | IOS | Redundant static default route duplicating the DHCP-learned default | Fixed |
| [R-18](#r-18) | Low | IOS | Shadowed DNS permits in `ACL_HQ_USERS_IN` | Fixed |
| [R-19](#r-19) | Low | Docs | Verification plan overclaimed VPCS DHCP option 42 visibility | Fixed |
| [R-20](#r-20) | Low | Docs | Expected OSPF metrics and router roles invalidated by the new topology | Fixed |
| [R-21](#r-21) | Medium | Security | CDP enabled on untrusted and guest-facing interfaces | Fixed |
| [R-22](#r-22) | Medium | Rubric | Part A requirements with no artefact: DMZ, stateful edge, redundancy evidence | Fixed |
| [R-23](#r-23) | Low | Design | Broad wildcard mask on the WAN deny entry | Accepted risk |
| [R-24](#r-24) | Medium | Design | No STP on GNS3 built-in switches, so Layer 2 cannot be made redundant | Accepted risk |
| [R-25](#r-25) | Medium | Design | Stateless inspection at the Internet edge | Accepted risk (upgrade path documented) |

---

## Functional and configuration defects

### R-01
**`no ip domain-lookup` makes the documented DNS verification impossible.** *(High — fixed)*

All four startup configurations contained both of these lines:

```
no ip domain-lookup
...
ip name-server 10.20.30.10
```

`no ip domain-lookup` disables the IOS DNS resolver process outright. With it configured, `ip name-server`
is stored but never consulted, so any name typed at the CLI is rejected with
`% Unrecognized host or address, or protocol not running.` The verification plan nevertheless asserted:

> `HQ-CORE# ping auto.corp.local` → `Translating "auto.corp.local"...domain server (10.20.30.10) [OK]`

That output cannot be produced by the configuration as written, and the plan's own explanatory note — that
"name resolution from the CLI works because `ip name-server` is set explicitly" — is incorrect. A marker
following the test plan would record a failure against a requirement (name resolution) that is in fact
implemented correctly on the server side.

**Resolution.** All five routers now configure:

```
ip domain-lookup
ip domain-lookup source-interface Loopback0
ip name-server 10.20.30.10
```

Sourcing lookups from `Loopback0` means the query reaches `DNS` from a stable, OSPF-advertised address
regardless of which WAN interface the packet leaves by — which matters now that the backbone has two paths.
The original motivation for `no ip domain-lookup` (a mistyped command being treated as a hostname and
hanging the console) is addressed by the fact that a resolver *is* configured and answers immediately, so a
failed lookup returns in milliseconds instead of timing out.

### R-02
**Anti-spoofing ACE can drop the edge DHCP offer and all PAT return traffic.** *(High — fixed)*

`ACL_INTERNET_IN`, applied inbound on the untrusted edge interface, opened with:

```
deny ip 10.0.0.0 0.255.255.255 any log
```

The intent — RFC 2827 ingress filtering, so a packet claiming an internal source cannot arrive from outside
— is correct. The implementation is too broad for the environment. The edge interface takes its address
from the GNS3 NAT cloud by DHCP, and while the default NAT cloud network is `192.168.122.0/24`, a GNS3 VM
whose host network is inside `10.0.0.0/8` (common on corporate and university Wi-Fi, and on some
VMware Fusion and UTM default configurations) hands out a `10.x.x.x` address. In that case the ACE drops the
DHCP `OFFER` and every PAT return packet, the outside interface never binds an address, and **all three
sites lose Internet access** with a symptom — "the NAT cloud is broken" — that points away from the cause.

The previous revision recognised this and documented a manual workaround in two places rather than fixing
it. A workaround the reader must find and apply is a defect, not a mitigation.

**Resolution.** The spoofing filter now enumerates only the address space this enterprise actually owns, so
no legitimate upstream address can match it, and the rest of the ACL was restructured from a deny-list into
an allow-list:

```
ip access-list extended ACL_INTERNET_IN
 deny   ip 10.10.0.0 0.0.255.255 any log      ! our own zones, by name
 deny   ip 10.20.0.0 0.0.255.255 any log
 deny   ip 10.30.0.0 0.0.255.255 any log
 deny   ip 10.40.0.0 0.0.255.255 any log
 deny   ip 10.255.0.0 0.0.255.255 any log
 deny   ip 127.0.0.0 0.255.255.255 any log
 deny   ip 169.254.0.0 0.0.255.255 any log
 permit tcp any any eq www                    ! the one published service
 permit udp any eq bootps any eq bootpc       ! the upstream DHCP offer
 permit tcp any any established               ! returns for PAT sessions
 permit udp any any gt 1023
 permit udp any eq ntp any eq ntp
 permit icmp any any echo-reply
 permit icmp any any unreachable
 permit icmp any any time-exceeded
 deny   ip any any log
```

Two things improved together. The spoofing filter is now strictly stronger — it also blocks spoofed
WAN-transit source addresses, which the single `10.0.0.0/8` entry covered only incidentally — and it is immune
to whatever the upstream network is numbered. Separately, the previous revision's trailing
`permit ip any any` accepted every unsolicited inbound packet that was not explicitly denied, which made the
entries above it decorative; the allow-list ends in `deny ip any any log`, so an inbound session that is not
a reply to an outbound one, or a connection to the single published port, is dropped and counted.

The explicit `permit udp any eq bootps any eq bootpc` is required by the change and is easy to omit: with a
closing deny, the DHCP `OFFER` for the outside interface is itself unsolicited inbound traffic. Note also that
inbound `ping` to the public address now fails by design, which the verification plan states as an expected
result so it is not mistaken for a fault.

### R-03
**The redundant WAN link bypasses the guest-isolation enforcement point.** *(Critical — fixed)*

The live project adds a second Branch uplink, `HQ-CORE ↔ BR-EDGE`, which the previous design documents had
listed only as a future improvement. Adding that link breaks a security property the design explicitly
claims.

Guest isolation is enforced at two points: `ACL_GUEST_IN` inbound on `BR-EDGE Fa1/0.50`, and
`ACL_WAN_BR_IN` inbound on `DC-EDGE Fa1/0` as "defence in depth: if the branch ACL is removed or a guest
host spoofs its way onto VLAN 40, the Data Centre still refuses guest-sourced traffic". That second control
depends on a topological assumption — that every packet leaving the Branch passes through `DC-EDGE Fa1/0`.
The new link makes the assumption false. Worse, because every link is FastEthernet with a default cost of 1,
the direct `BR-EDGE → HQ-CORE` path is **shorter** than the path through the Data Centre, so OSPF prefers
it and *all* Branch-to-HQ traffic — including guest traffic if the branch ACL is ever removed, misapplied
during a change, or bypassed — takes the unfiltered path by default.

**Resolution.** Two changes, applied together because either alone is insufficient:

1. **Policy follows the packet, not the path.** `ACL_WAN_BR_IN` is now applied inbound on
   `HQ-CORE Fa3/0` as well as `DC-EDGE Fa1/0`. Every possible egress from the Branch is filtered, so the
   defence-in-depth claim holds under any failover state.
2. **The direct link is a backup, not a primary.** `ip ospf cost 50` on both ends of
   `10.255.0.16/30` makes the path through the Data Centre (cost 2) preferred over the direct path
   (cost 50). Normal traffic still traverses the intended Data Centre chokepoint, preserving traffic
   locality and making the routing table match the documented flow tables, while the link still delivers
   its actual purpose: it carries Branch traffic within seconds if `DC-EDGE` or the primary WAN link fails.

Making a redundant path explicitly *less preferred* rather than equal-cost is the deliberate choice here.
Equal-cost multipath across the two links would halve the effective policy coverage of any per-interface
control and would make packet captures non-deterministic, which is a poor property in a lab whose evidence
is per-interface counters.

### R-06
**The guest VLAN had unrestricted internal access to the DMZ.** *(Critical — fixed)*

`ACL_GUEST_IN` blocks guest traffic toward `10.10.0.0/16`, `10.20.0.0/16`, `10.30.40.0/24` and
`10.255.0.0/16`, then permits everything else so guests reach the Internet. That enumeration was complete
when the enterprise owned only three /16s. The live project adds the DMZ zone at `10.40.0.0/16`, which the
enumeration does not cover — so the final `permit ip 10.30.50.0 0.0.0.255 any` grants the guest VLAN
**direct internal access to `WEB-SRV` and every other DMZ host**, bypassing the Internet-facing service
definition entirely.

This is the characteristic failure mode of deny-list ACLs: adding a subnet to the network silently widens
the permission. It is worth stating plainly in the report because it is the reason production designs prefer
allow-lists at trust boundaries.

**Resolution.** `deny ip 10.30.50.0 0.0.0.255 10.40.0.0 0.0.255.255 log` added above the trailing permit,
and the same entry added to `ACL_WAN_BR_IN` at both enforcement points. The report documents the structural
lesson alongside the fix, and §5 of `DESIGN_JUSTIFICATION.md` now states the enumeration explicitly as a
maintenance obligation attached to the addressing plan.

### R-10
**Two routers would originate the default route after the edge split.** *(High — fixed)*

Moving PAT and the Internet edge to `FW-EDGE` (see [R-05](#r-05)) requires the default route to be
originated there. `HQ-CORE` retained `default-information originate always`, and because that command's
`always` keyword injects a type-5 external LSA *whether or not the router has a default route of its own*,
leaving it in place would have produced two `O*E2 0.0.0.0/0` entries across the domain — one pointing at a
router with no path to the Internet. Roughly half of all Internet-bound traffic would have been forwarded to
`HQ-CORE` and dropped, presenting as intermittent, source-dependent Internet failure.

**Resolution.** `default-information originate always` exists on `FW-EDGE` only. `HQ-CORE` is now a pure
area-0 core router with no external origination, which `show ip ospf` confirms by no longer reporting
"It is an autonomous system boundary router".

### R-11
**NAT scope did not cover the DMZ block.** *(Medium — fixed)*
`ACL_NAT_INSIDE` permitted `10.10.0.0/16`, `10.20.0.0/16` and `10.30.0.0/16`. DMZ hosts at
`10.40.200.0/24` therefore matched no NAT rule, so their outbound packets would have been forwarded to the
upstream network untranslated and silently discarded. `permit 10.40.0.0 0.0.255.255` added.

### R-12
**`ip nat inside` on a trunk physical interface is silently inert.** *(Medium — fixed)*
The DMZ gateway on `FW-EDGE` is an 802.1Q subinterface (`Fa2/0.200`). NAT domain membership is a property of
the interface that owns the IP address, so `ip nat inside` belongs on the subinterface; placed on the
parent trunk — which has `no ip address` — it is accepted without error and does nothing. This is the same
class of defect as referencing a `GigabitEthernet` interface on a c7200: the configuration applies cleanly
and the feature is absent. `ip nat inside` is configured on `Fa2/0.200`, and the build notes now list this
as an assertion to check with `show ip nat statistics`.

### R-17
**Redundant static default route.** *(Low — fixed)*
`ip route 0.0.0.0 0.0.0.0 FastEthernet0/0 dhcp` duplicated the default route that `ip address dhcp` already
installs from the lease's gateway option, producing two identical candidate defaults in `show ip route` and
an ambiguous expected output in the test plan. Removed; `default-information originate always` already
covers the transient case the static route was intended to protect against, which is why that keyword is
used in the first place.

### R-18
**Shadowed DNS permits in `ACL_HQ_USERS_IN`.** *(Low — fixed)*
The two entries permitting VLAN 10 → `10.20.30.10` port 53 sit above `permit ip 10.10.10.0 0.0.0.255 any`
with no intervening deny that would match DNS traffic, so they can never be the deciding entry and their
counters merely duplicate the general permit. They were retained in the previous revision as documentation.
They are now removed from `ACL_HQ_USERS_IN`, because a permit that never decides anything makes ACL match
counters harder to reason about during troubleshooting — the opposite of the documentation value intended.
The equivalent entries in `ACL_GUEST_IN` and `ACL_WAN_BR_IN` are **not** redundant and are retained: there
they sit above denies that would otherwise match, and they are the entries that make selective guest name
resolution work.

---

## Design and security findings

### R-04
**Documentation modelled 19 nodes; the live project has 32.** *(High — fixed)*

The repository described 4 routers, 6 switches, 4 Docker nodes, 4 VPCS hosts and a NAT cloud. The GNS3
project that will be screenshotted for the submission contains five routers (`FW-EDGE` added), eleven
switches, seven servers, eight endpoints, an Internet-facing DMZ zone and a redundant WAN link. Every
artefact keyed to the smaller model was therefore wrong in a way a marker can see by comparing a diagram to
a screenshot: the node inventory, the mermaid diagram, the link table, the switch port matrix, the
addressing plan, the interface inventory in the test plan, and the expected OSPF routing table.

Divergence between a report and the built artefact is one of the few things that reliably costs marks
regardless of how good either one is on its own, because it undermines the credibility of all the evidence.

**Resolution.** `docs/TOPOLOGY.md` and `docs/IP_ADDRESSING.md` were rewritten against the live build:
32 nodes, 32 links, 8 VLANs, 5 WAN /30s, a DMZ zone and the redundant Branch uplink, with the router
interface allocation extended to slot 3 on `HQ-CORE` and `BR-EDGE` to accommodate it. `report/PartA_Report.md`
is generated from the same tables, and `docs/TOPOLOGY_APPENDIX_COMPLEXITY.md` holds the further additive
expansion so that future growth lands in one reviewable place instead of drifting into the lab unrecorded.

### R-05
**Internet edge, PAT and OSPF core collapsed onto one router.** *(Medium — fixed)*

`HQ-CORE` simultaneously terminated the untrusted upstream link, performed PAT, filtered inbound Internet
traffic, originated the default route, and served as the hub of the area-0 backbone with adjacencies to
three other routers. The design justification claimed `HQ-CORE` "is the security boundary … it holds no user
VLANs, so a change to the user access layer can never accidentally modify the Internet edge" — but the same
argument applies with more force one level up: a change to the *backbone* should not be able to modify the
Internet edge either, and on a single device it can. There was also no device that could be described as a
firewall, and no DMZ, so an Internet-facing service could not be offered at all without either exposing an
internal subnet or port-forwarding into the user population.

**Resolution.** A dedicated edge router, `FW-EDGE`, now owns the untrusted interface, PAT, the inbound edge
ACL, the static translation for the DMZ web service, and default-route origination. `HQ-CORE` becomes a pure
area-0 core: five interfaces, no NAT, no external origination, no host VLANs. The DMZ (VLAN 200,
`10.40.200.0/24`, OSPF area 40) hangs off `FW-EDGE` on its own subinterface, which is the only place in the
topology where an inbound-initiated session from the Internet terminates.

This also produces the three-tier trust model the report needs to discuss credibly: untrusted (upstream),
semi-trusted (DMZ, may be reached from outside, may not initiate inward), and trusted (the three internal
sites).

### R-07
**DHCP pool on the management VLAN.** *(Medium — fixed)*

`HQ-DIST` served `VLAN99_HQ_MGMT` (`10.10.99.0/24`) by DHCP, while every host on that VLAN is statically
addressed — the pool had, by the test plan's own admission, zero expected leases. It was not merely useless.
`ACL_VTY` permitted SSH from all of `10.10.99.0/24`, so any device connected to an access port on
`SW-HQ-3` would be automatically addressed into the one subnet that is allowed to administer every router in
the enterprise. A DHCP pool on a management VLAN converts a physical-access problem into a
management-plane-access problem.

**Resolution.** The pool is removed. The management VLAN is static-only by design, which is now stated as a
design decision rather than an omission, and the reserved-address rationale is documented alongside
[R-08](#r-08).

### R-08
**`ACL_VTY` permitted a whole /24 of management sources.** *(Medium — fixed)*

Two `/24`s were permitted to reach every router's VTY. Combined with [R-07](#r-07) that was a wide grant;
even without it, the principle of least privilege argues for naming the hosts that legitimately administer
network equipment, since there are exactly two.

**Resolution.**

```
ip access-list extended ACL_VTY
 permit tcp host 10.10.99.10 any eq 22
 permit tcp host 10.10.99.11 any eq 22
 permit tcp 10.20.30.0 0.0.0.255 any eq 22
 deny   ip any any log
```

`10.10.99.10` is `AUTO-SRV`, which is also the Part B Ansible control node; `10.10.99.11` is the reserved
address for the management jump host in
[`TOPOLOGY_APPENDIX_COMPLEXITY.md`](TOPOLOGY_APPENDIX_COMPLEXITY.md). The Data Centre infrastructure VLAN
retains subnet-level access as a deliberate break-glass path for the case where the HQ management VLAN or
`HQ-DIST` itself is unreachable — with only host entries, a failure of one router would lock administrators
out of the entire estate. That trade-off is stated in the report rather than left implicit.

### R-09
**Unauthenticated OSPF adjacencies on a redundant backbone.** *(Medium — fixed)*

The previous revision declared this a known gap and justified omitting it so that neighbour-formation
evidence would isolate addressing faults from authentication mismatches. That was reasonable for a
three-adjacency chain. It is no longer reasonable: the backbone now has five routers and six adjacencies
including a redundant path, and any device that can reach a WAN segment can inject LSAs and attract or
black-hole traffic for the entire enterprise. The control is also a specific, checkable item under the
security element of the rubric, and leaving it out trades a mark for a convenience that only applies during
first bring-up.

**Resolution.** MD5 cryptographic authentication is enabled on the area-0 backbone on all five routers:

```
router ospf 1
 area 0 authentication message-digest
!
interface FastEthernet1/0
 ip ospf message-digest-key 1 md5 <key>
```

Applied per-area rather than per-interface so a new backbone link cannot be brought up unauthenticated by
omission. The non-backbone areas carry no adjacencies at all — every LAN interface is passive — so
authenticating them would add key management with no threat reduction; that reasoning is recorded so the
asymmetry reads as a decision rather than an oversight. `verification/CHECKS.md` gains a check for
`Message digest authentication enabled` on each backbone interface, and a troubleshooting entry for the
one-sided-key symptom (neighbour stuck down with `%OSPF-4-BADLENGTH`/mismatch logging).

### R-21
**CDP enabled on untrusted and guest-facing interfaces.** *(Medium — fixed)*

CDP is on by default. On the upstream interface it advertises the platform, IOS version, hostname and native
VLAN of the enterprise edge router to whatever is on the other side; on the guest and DMZ segments it hands
the same reconnaissance to any untrusted host. Nothing in this design consumes CDP.

**Resolution.** `no cdp enable` on the upstream interface, the DMZ subinterface and the guest subinterface.
CDP is retained on the internal WAN links, where its neighbour table is genuinely useful for verifying
cabling against the link table, and that split is documented rather than applying a blanket `no cdp run`.

### R-22
**Part A requirements with no artefact.** *(Medium — fixed)*

Reviewing the deliverables against the assessment requirements rather than against the previous
documentation surfaced four gaps:

| Requirement area | Gap | Resolution |
|------------------|-----|------------|
| Formal report | The repository held design notes and a test plan, but no assessable report — no executive summary, no introduction, no discussion or conclusion, no references | [`report/PartA_Report.md`](../report/PartA_Report.md) with an IEEE-referenced structure and [`report/BUILD_PDF.md`](../report/BUILD_PDF.md) for PDF production |
| Internet-facing service | No DMZ and no inbound service, so the NAT discussion covered only outbound PAT | DMZ zone, `WEB-SRV`, and a static port translation exercised and verified |
| Resilience | Redundancy discussed as future work only | Redundant Branch uplink, cost-engineered as a backup, with a documented failover test |
| Server tiering | All servers on one VLAN, so no east-west policy could be demonstrated | Data Centre split into infrastructure (VLAN 30) and application (VLAN 31) tiers |

---

## Documentation and evidence defects

### R-13
**`auto-srv-setup.sh` breaks its own package install.** *(Medium — fixed)*
The script overwrote `/etc/resolv.conf` with `nameserver 10.20.30.10` and then ran `apt-get update`. During
first bring-up the `DNS` container is often not yet running, and even when it is, `dnsmasq` forwards to
`8.8.8.8` through PAT that may not be up. The result is `apt-get` failing to resolve the Ubuntu mirrors, so
`ansible` and `netmiko` are never installed — the failure surfacing much later as an unexplained Part B
problem. Package installation now completes first, using the container's inherited resolver, and the
enterprise resolver is written afterwards. `DEBIAN_FRONTEND=noninteractive` and `set -u` were added, and
every script now ends by printing a self-check so a successful run is visibly distinguishable from a
partial one.

### R-14
**Container scripts added a second address instead of replacing GNS3's.** *(Medium — fixed)*
`ip addr add 10.20.30.10/24 dev eth0 || true` leaves any address GNS3 configured on `eth0` in place, so the
container can answer on two addresses and source packets from the wrong one — which shows up as a service
that works from one subnet and not another. The scripts now flush `eth0` before configuring it, and replace
the default route rather than adding a second one.

### R-15
**Syslog collector wrote all devices into one undifferentiated file.** *(Medium — fixed)*
`rsyslog` was configured to listen on UDP and TCP 514 but not to separate senders, so evidence gathering
meant grepping `/var/log/syslog` for hostnames. The collector now also writes
`/var/log/network/<source-ip>.log` per device, which makes per-device evidence a `cat` rather than a `grep`,
and makes an absent device obvious by an absent file. `$PreserveFQDN` and an explicit template retain the
loopback source address that `logging source-interface Loopback0` produces.

### R-16
**DNS zone data omitted the servers added since the first build.** *(Low — fixed)*
`dnsmasq` resolved four names. The live build has seven servers plus the routers. All are now defined, along
with `PTR` records so reverse lookups resolve, and `log-queries` so name resolution can be evidenced from
the server side as well as the client side.

### R-19
**Verification plan overclaimed VPCS DHCP option 42 visibility.** *(Low — fixed)*
The plan stated that hosts "obtain their address, gateway, DNS server and NTP server (DHCP option 42) from
the local router" and presented `show ip` as the evidence. VPCS does not request or display option 42; the
option is configured in the IOS pools and is verifiable on the router with `show ip dhcp pool` and in a
packet capture on the access link, not in `show ip`. The claim is now scoped to what the named command
actually shows, with the option-42 evidence moved to the router-side check and an optional Wireshark capture.

### R-20
**Expected OSPF metrics and router roles invalidated by the new topology.** *(Low — fixed)*
The expected `show ip route ospf` output, the adjacency count (3), the ABR/ASBR role table and the
traceroute hop list all described the four-router chain. With five routers, six adjacencies, a cost-50
backup link and area 40, every one of those expectations changed. `verification/CHECKS.md` was recomputed
from the new topology rather than adjusted, including the hop-by-hop traceroute that demonstrates the
Data Centre transit path is still preferred over the direct Branch uplink.

---

## Accepted risks

### R-23
**Broad wildcard mask on the WAN deny entry.** *(Low — accepted)*
`deny ip 10.30.50.0 0.0.0.255 10.255.0.0 0.0.255.255 log` covers `10.255.0.0/16` where only
`10.255.0.0/24` is allocated. Retained deliberately: it pre-covers any future WAN allocation inside
`10.255.0.0/16` and cannot over-block, because nothing else in the plan uses that space. Narrowing it to
`0.0.0.255` would create exactly the maintenance obligation that caused [R-06](#r-06).

### R-24
**Layer 2 cannot be made redundant.** *(Medium — accepted)*
The GNS3 built-in Ethernet switch implements access ports and 802.1Q tagging and nothing else — no STP, no
port security, no LACP, no `switchport trunk allowed vlan` pruning. The access and distribution layers are
therefore deliberately loop-free trees, and Layer 2 redundancy is out of scope. Redundancy is demonstrated at
Layer 3 instead, where OSPF provides it, which is where this design would put it in production anyway. The
alternative — eleven IOSvL2 instances — needs roughly 8 GB of RAM in the GNS3 VM against the 4 GB available,
and on an Apple silicon host would additionally require x86 software emulation. The consequence for the
report is that port security and RSTP root-bridge election are discussed as design intent with the
configuration that would implement them, and are explicitly not claimed as verified.

### R-25
**Stateless inspection at the Internet edge.** *(Medium — accepted, upgrade path documented)*
After the [R-02](#r-02) rework, `FW-EDGE` enforces an allow-list, but it is still a *stateless* one:
return traffic is matched structurally — `established` for TCP, a high destination port for UDP, and the
three diagnostic ICMP types — rather than against a session table. Two residual gaps follow, and they are
worth naming rather than glossing over. A crafted TCP segment with the ACK bit set matches
`permit tcp any any established` without belonging to any session, and `permit udp any any gt 1023` is a wide
grant because stateless filtering cannot tell a DNS reply from an unsolicited packet to a high port.

A genuinely stateful edge is available on this platform through CBAC (`ip inspect`), which would let items 3
and 4 of `ACL_INTERNET_IN` collapse into `deny ip any any log` with the return pinholes opened dynamically per
session. It is not enabled in the baseline for two reasons: `ip inspect` session tracking is measurably
expensive on emulated MIPS hardware shared with four other Dynamips instances, and a stateful edge is not a
Part A requirement. The exact configuration is provided as a commented block in
[`configs/FW-EDGE.cfg`](../configs/FW-EDGE.cfg) and discussed in the report, so the gap is a stated scope
boundary with a costed remedy rather than an omission.

---

## Verification of the fixes

Every change above is covered by a check in [`verification/CHECKS.md`](../verification/CHECKS.md):

| Finding | Verified by |
|---------|-------------|
| R-01 | §7.1 — `ping web.corp.local` from a router resolves and replies |
| R-02 | §6.1 — outside interface holds a lease regardless of the upstream network |
| R-03 | §2.4 and §5.2 — Data Centre path preferred at cost 2; guest denies counted on `HQ-CORE Fa3/0` during failover |
| R-06 | §5.1 — `ping 10.40.200.10` from `PC4` is administratively prohibited |
| R-07, R-08 | §5.4 — SSH permitted from `AUTO-SRV`, refused from every other source, denial logged |
| R-09 | §2.6 — `Message digest authentication enabled` on all six backbone interfaces |
| R-10 | §2.5 — exactly one `O*E2 0.0.0.0/0`, originated by `4.4.4.4` |
| R-11, R-12 | §6.2 — DMZ host translated; `show ip nat statistics` lists `Fa2/0.200` as an inside interface |
| R-13 to R-16 | §7 — service-by-service confirmation on each container |
| R-21 | §5.6 — `show cdp interface` omits the upstream, DMZ and guest interfaces |
| R-22 | §6.4 inbound DMZ service, §4.5 failover, §8 sign-off matrix |
