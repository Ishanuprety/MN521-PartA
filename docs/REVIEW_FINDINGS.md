# Part A — Technical Review Findings Register

A structured review of the Part A package: the five IOS startup configurations, the
switch port matrix, the container and endpoint configurations, and the topology as
exported from the live GNS3 project — checked against the assessment requirements.

Each finding records what is wrong, how it was established, why it matters, and what
changed. Findings marked **Accepted** are deliberately not fixed, with the reason
stated. Nothing here is hypothetical: every entry traces to a specific line of a
configuration file, a specific entry in `ports_mapping.json`, or a specific link in
the topology export.

| Severity | Meaning |
|----------|---------|
| **Critical** | Breaks a security control the design claims to enforce, or makes a required service non-functional |
| **High** | Causes a functional failure, or a documented claim the build cannot substantiate |
| **Medium** | Design weakness, unnecessary attack surface, or documentation that diverges from the built lab |
| **Low** | Redundancy, imprecision or cosmetic inconsistency |

---

## Summary

| ID | Severity | Area | Finding | Status |
|----|----------|------|---------|--------|
| [R-01](#r-01) | High | Drift | Live routers may still run NAT on `HQ-CORE Fa0/0` after the edge redesign | Fixed in repo; **requires re-apply** |
| [R-02](#r-02) | Critical | Topology | Three Layer 2 loops in the access layer, with no STP to break them | Fixed in docs; **requires GNS3 link deletion** |
| [R-03](#r-03) | Critical | NAT | Published DMZ services could not work: no static translation, and the ACL matched the post-NAT address | Fixed |
| [R-04](#r-04) | High | Routing | Two routers originated the default route | Fixed |
| [R-05](#r-05) | Critical | Security | Backup WAN bypassed the guest containment enforcement point | Fixed |
| [R-06](#r-06) | Critical | Security | Guest ACL denied two /24s then permitted everything else | Fixed |
| [R-07](#r-07) | High | Security | DMZ could initiate sessions into the user VLANs and the Branch | Fixed |
| [R-08](#r-08) | Medium | Security | DHCP pool on the management VLAN; `ACL_VTY` trusted a whole /24 | Fixed |
| [R-09](#r-09) | High | Services | `dnsmasq` had no upstream and forwarded to itself | Fixed |
| [R-10](#r-10) | High | Services | Perimeter ACL dropped outbound DNS and NTP replies, and permitted inbound DNS | Fixed |
| [R-11](#r-11) | High | Services | `no ip domain-lookup` made every name-resolution test impossible to pass | Fixed |
| [R-12](#r-12) | Medium | Services | Container scripts broke their own package installation | Fixed |
| [R-13](#r-13) | Medium | Switching | DMZ trunk carried VLAN 60 untagged, so the DMZ gateway saw nothing | Fixed |
| [R-14](#r-14) | Medium | Evidence | No `service timestamps`, so syslog evidence had no timestamps | Fixed |
| [R-15](#r-15) | Medium | Config quality | Duplicate interface blocks, unprotected `vty 5 15`, byte-identical duplicate config tree | Fixed |
| [R-16](#r-16) | Medium | Platform | No STP, port security or LACP on GNS3 built-in switches | Accepted |
| [R-17](#r-17) | Low | Docs | `PC5`/`PC8` documented at Branch but wired at HQ | **Resolved — keep at HQ as wired** |
| [R-18](#r-18) | Low | Config | WAN transit included in the NAT scope | Fixed |
| [R-19](#r-19) | Medium | Security | Stateless inspection at the Internet edge | Accepted, upgrade path documented |
| [R-20](#r-20) | Medium | Requirements | No assessable report, and several rubric items had no artefact | Fixed |

---

## Drift between the repository and the live lab

### R-01
**Live routers may still run NAT on `HQ-CORE Fa0/0`.** *(High — fixed in repo, requires re-apply)*

The design moved the Internet edge to `FW-EDGE`: PAT, the perimeter filter and
default-route origination now live there, and `HQ-CORE Fa0/0` became a routed /30 to
it (`10.255.0.18/30`). `configs/HQ-CORE.cfg` in this repository reflects that.

The risk is not in the repository, it is in the gap between the repository and the
devices. A router still holding the earlier revision has `ip address dhcp` and
`ip nat outside` on `Fa0/0`, which after the rewiring means:

- `Fa0/0` requests DHCP from `FW-EDGE`, which runs no DHCP server on that interface,
  so the interface never gets an address and the `10.255.0.16/30` adjacency never
  forms;
- `HQ-CORE` is then partitioned from `FW-EDGE`, so the whole enterprise loses the
  default route while OSPF still shows four healthy-looking adjacencies elsewhere.

**Resolution.** `configs/HQ-CORE.cfg` carries an explicit header stating that it
supersedes the NAT-on-`Fa0/0` revision, and `docs/APPLY_STEPS.md` makes re-applying
all five configurations a single atomic step. To confirm which revision a device is
running:

```
HQ-CORE# show ip interface brief | include FastEthernet0/0
HQ-CORE# show running-config interface FastEthernet0/0
```

`Fa0/0` must show `10.255.0.18` and the interface must contain no `ip nat` command.
Anything else means the device is running the superseded configuration.

### R-02
**Three Layer 2 loops in the access layer.** *(Critical — fixed in docs, requires GNS3 link deletion)*

The GNS3 built-in Ethernet switch implements access ports and 802.1Q tagging and
nothing else. It has **no spanning tree**, so there is no mechanism to block a
redundant path. The topology export contains three triangles:

| Loop | Links involved |
|------|----------------|
| `SW-HQ-1` – `SW-HQ-2` – `SW-HQ-DIST` – `SW-HQ-1` | `SW-HQ-1 Eth7`↔`SW-HQ-2 Eth0`, plus both switches' uplinks to `SW-HQ-DIST` |
| `SW-DC-1` – `SW-DC-2` – `SW-DC-CORE` – `SW-DC-1` | `SW-DC-1 Eth7`↔`SW-DC-2 Eth0`, plus both uplinks |
| `SW-BR-1` – `SW-BR-2` – `SW-BR-DIST` – `SW-BR-1` | `SW-BR-1 Eth7`↔`SW-BR-2 Eth0`, plus both uplinks |

A loop here does not degrade gracefully. Broadcast frames — ARP, DHCP DISCOVER,
every unknown-unicast flood — circulate indefinitely and multiply at each switch.
On a 4 GB GNS3 VM the storm saturates the host, and the visible symptom is that
the whole project becomes unresponsive, which looks like GNS3 being slow rather
than a cabling fault.

The previous documentation identified the risk and applied a mitigation that
addresses a *different* loop: `HQ-DIST Fa1/0`, `DC-EDGE Fa2/0` and `BR-EDGE Fa1/0`
are held down because each router was cabled to both an access switch and its
aggregation switch. That is correct and necessary, but it does nothing about the
three switch-to-switch triangles, which remain closed.

**Resolution.** The three cross-links must be **deleted in GNS3**:

| Delete | Loop broken |
|--------|-------------|
| `SW-HQ-1 Eth7` ↔ `SW-HQ-2 Eth0` | HQ triangle |
| `SW-DC-1 Eth7` ↔ `SW-DC-2 Eth0` | Data Centre triangle |
| `SW-BR-1 Eth7` ↔ `SW-BR-2 Eth0` | Branch triangle |

Nothing is disconnected by this: `SW-HQ-2` keeps its uplink on `Eth2`, `SW-DC-2` on
`Eth6` and `SW-BR-2` on `Eth6`, all to their aggregation switch. The resulting
loop-free tree is drawn in [`TOPOLOGY.md`](TOPOLOGY.md) §5, and the deletions are a
numbered step in [`APPLY_STEPS.md`](APPLY_STEPS.md).

---

## Functional defects

### R-03
**The published DMZ services could not work.** *(Critical — fixed)*

`ACL_OUTSIDE_IN` contained what looked like the right permits:

```
permit tcp any host 10.60.60.10 eq 80
permit tcp any host 10.60.60.10 eq 443
permit tcp any host 10.60.60.11 eq 8080
```

Two independent defects made inbound access impossible.

**First, the ACL could never match.** For traffic arriving on a NAT *outside*
interface, IOS evaluates the inbound ACL **before** performing outside-to-inside
translation. At that point the destination address in the packet is still the
outside global address — the DHCP-learned address of `Fa0/0` — not `10.60.60.10`.
The three entries therefore matched nothing, ever, and the packet fell through to
the closing `deny ip any any log`.

**Second, there was nothing to translate to.** No `ip nat inside source static`
entry existed. Even with a permissive ACL, a packet arriving for the outside global
address on TCP 80 has no mapping to `10.60.60.10:80`, so it would be processed as
traffic addressed to the router itself and dropped.

This mattered disproportionately: inbound publishing is the only NAT behaviour in
the design beyond outbound PAT, so the NAT requirement rested on a path that could
not carry a packet.

**Resolution.** Static port translations added on `FW-EDGE`:

```
ip nat inside source static tcp 10.60.60.10 80 interface FastEthernet0/0 80
ip nat inside source static tcp 10.60.60.11 8080 interface FastEthernet0/0 8080
```

and the ACL entries rewritten to match the pre-translation destination, with a
`remark` recording why:

```
permit tcp any any eq www
permit tcp any any eq 8080
```

TCP 443 was **removed** rather than corrected: nothing in the DMZ terminates TLS, so
publishing it would have advertised a port with no listener behind it and produced a
failing test for the wrong reason. `WEB-SRV` serves HTTP only.

### R-04
**Two routers originated the default route.** *(High — fixed)*

`FW-EDGE` had `default-information originate`, correctly, as the ASBR. `HQ-CORE`
also had `default-information originate` together with
`ip route 0.0.0.0 0.0.0.0 10.255.0.17`. Both therefore injected an
`O*E2 0.0.0.0/0` into the domain.

Downstream routers saw two external defaults with equal metrics and installed both,
load-sharing Internet-bound traffic between a next hop toward `FW-EDGE` (correct)
and a next hop toward `HQ-CORE` (which then had to forward it on again). The
observable symptom is asymmetric paths and NAT translation entries appearing for
some flows and not others — intermittent, source-dependent Internet behaviour that
is painful to diagnose because both routes look valid.

**Resolution.** `HQ-CORE` no longer originates a default and no longer holds a static
one; it learns `0.0.0.0/0` as `O*E2` from `FW-EDGE` like every other router.
`show ip route 0.0.0.0` on any device is now unambiguous evidence of where Internet
traffic leaves the enterprise. `FW-EDGE` uses `default-information originate always`
because its own default comes from a DHCP lease whose renewal timing is outside our
control, and `always` keeps the domain default stable across a renewal instead of
black-holing all four zones for the duration.

### R-11
**`no ip domain-lookup` made name resolution untestable.** *(High — fixed)*

All five configurations contained both:

```
no ip domain-lookup
ip name-server 10.20.30.10
```

`no ip domain-lookup` disables the IOS resolver process outright, so `ip name-server`
is stored and never consulted. Any name typed at the CLI returns
`% Unrecognized host or address, or protocol not running.` DNS is an explicitly
required service, and the only router-side evidence for it — resolving a name from a
router console — could not be produced, despite the server being configured
correctly.

**Resolution.** All five routers now configure:

```
ip domain-lookup
ip domain-lookup source-interface Loopback0
ip name-server 10.20.30.10
```

Sourcing lookups from `Loopback0` means the query reaches `DNS` from a stable
OSPF-advertised address regardless of which interface the packet leaves by, which
matters on `BR-EDGE` with its two WAN paths. The original motivation for disabling
lookups — a mistyped command being treated as a hostname and hanging the console —
is addressed by the fact that a resolver *is* configured and answers immediately, so
a failed lookup returns in milliseconds instead of timing out.

### R-09
**`dnsmasq` forwarded to itself.** *(High — fixed)*

`dns-setup.sh` wrote `nameserver 10.20.30.10` into `/etc/resolv.conf` — the
container's own address — and configured `dnsmasq` with neither `no-resolv` nor any
`server=` directive. `dnsmasq` reads `/etc/resolv.conf` to discover its upstream
forwarders, so it adopted itself as its own upstream.

Names inside `corp.local` still resolved, because those are answered locally from
the configuration. Every external name failed: the query was forwarded to
`10.20.30.10`, which forwarded it to `10.20.30.10`, until `dnsmasq`'s recursion
guard returned `SERVFAIL`. The partial success is what makes this one hard to spot —
`nslookup web.corp.local` works perfectly while `nslookup google.com` fails.

**Resolution.** Upstreams are named explicitly and `/etc/resolv.conf` is no longer
used for forwarder discovery:

```
no-resolv
server=8.8.8.8
server=1.1.1.1
domain-needed
bogus-priv
```

`domain-needed` and `bogus-priv` additionally stop unqualified names and RFC 1918
reverse lookups being sent to public resolvers, which they cannot answer and which
would leak internal names. Zone data was also converted from `address=` to
`host-record=`, which creates the reverse `PTR` record as well as the forward `A`
record, and extended to cover all five routers, all nine servers and all seven
gateways.

### R-10
**Perimeter ACL dropped outbound DNS and NTP replies, and permitted inbound DNS.** *(High — fixed)*

`ACL_OUTSIDE_IN` contained:

```
permit udp any any eq 53
permit tcp any any eq 53
```

Both the direction and the effect were wrong.

**They do not match the traffic they were intended for.** A reply to an outbound DNS
query has *source* port 53 and a high destination port. `eq 53` after the
destination matches the destination port, so a reply never matches. With the closing
`deny ip any any log`, `dnsmasq`'s forwarded queries to `8.8.8.8` were dropped on
the way back — compounding R-09, so external resolution had two independent reasons
to fail.

**They do match traffic that should be denied.** Any inbound packet to UDP or TCP
port 53 on any inside address was permitted from anywhere on the Internet.

Separately, no entry covered generic UDP return traffic, so `chrony`'s upstream
synchronisation would also have been dropped had it been enabled.

**Resolution.** The return-traffic entries now match on the properties return
traffic actually has:

```
permit tcp any any established
permit udp any any gt 1023
permit udp any eq ntp any eq ntp
permit icmp any any echo-reply
permit icmp any any unreachable
permit icmp any any time-exceeded
```

and the inbound port-53 permits are gone. `permit udp any any gt 1023` covers UDP
replies to PAT-assigned high ports; the explicit NTP pair covers the case where PAT
preserves source port 123. The three ICMP types are what `ping` and `traceroute` from
inside need in return, without permitting inbound `echo` — so the public address
does not answer ping, by design.

`permit udp any eq bootps any eq bootpc` was also added, and is easy to miss: with a
closing deny, the DHCP `OFFER` that gives `Fa0/0` its outside address is itself
unsolicited inbound traffic. Without that entry the interface never binds and every
test in the NAT section fails at step one.

### R-13
**DMZ trunk carried VLAN 60 untagged.** *(Medium — fixed)*

In `ports_mapping.json`, `SW-DMZ-1 Eth0` — the trunk to `FW-EDGE Fa2/0` — was
configured as `{"type": "dot1q", "vlan": 60}`. For a `dot1q` port the `vlan` field is
the **native** VLAN, and native-VLAN traffic egresses a trunk *untagged*. So frames
from the DMZ access ports left the trunk with no 802.1Q tag, while
`FW-EDGE Fa2/0.60` accepts only frames tagged with VLAN 60 and discarded them.

Every other trunk in the file correctly uses native VLAN 1, which is what made this
one identifiable as a typo rather than a deliberate choice. The symptom would be a
DMZ that is completely dark — no DHCP for `PC-DMZ`, no reachability for `WEB-SRV` or
`APP-SRV` — with a switch and router configuration that both look right.

**Resolution.** `SW-DMZ-1 Eth0` is now `{"type": "dot1q", "vlan": 1}`, consistent
with every other trunk, so VLAN 60 is tagged.

### R-18
**WAN transit included in the NAT scope.** *(Low — fixed)*
`ACL_NAT` permitted `10.255.0.0 0.0.0.255`. WAN /30 addresses are point-to-point
router interfaces that never source Internet traffic, so translating them serves no
purpose and obscures which zones a translation belongs to in
`show ip nat translations`. Removed, with a `remark` recording that the exclusion is
deliberate.

---

## Security defects

### R-05
**The backup WAN bypassed the guest containment enforcement point.** *(Critical — fixed)*

Guest containment was designed with two enforcement points: `ACL_GUEST_IN` at the
first hop on `BR-EDGE Fa3/0.50`, and a second pass on `DC-EDGE Fa1/0` for defence in
depth — so that if the branch ACL were removed during a change, or a guest host
found its way onto the staff VLAN, the Data Centre would still refuse guest-sourced
traffic.

That second control rests on a topological assumption: that every packet leaving the
Branch passes through `DC-EDGE Fa1/0`. The backup WAN via `WAN-Cloud` makes the
assumption false. `HQ-CORE Fa3/0` had no ACL, so any Branch traffic taking the
backup path was unfiltered.

Worse, without cost engineering the bypass would have been the *normal* path, not
the failure path. Every link is FastEthernet with a default cost of 1, so
`BR-EDGE → HQ-CORE` direct costs 1 while `BR-EDGE → DC-EDGE → HQ-CORE` costs 2.
OSPF prefers the shorter path, so all Branch-to-HQ traffic would have taken the
unfiltered link by default.

**Resolution.** Two changes, applied together because either alone is insufficient:

1. **Policy follows the packet, not the path.** `ACL_WAN_BR_IN` is applied inbound on
   `HQ-CORE Fa3/0` as well as `DC-EDGE Fa1/0`, with identical entries. Every WAN
   interface a Branch-sourced packet can arrive on is filtered, so the control holds
   in any failover state.
2. **The backup is genuinely a backup.** `ip ospf cost 50` on both ends of
   `10.255.0.20/30` makes the Data Centre path (cost 2) preferred over the direct
   path (cost 50), so normal traffic still traverses the intended chokepoint and the
   routing table matches the documented flow table.

Making the redundant path deliberately *less preferred* rather than equal-cost is the
design decision here. Equal-cost multipath would send roughly half of all Branch
traffic over each link, halving the effective coverage of any per-interface counter
and making packet paths non-deterministic — a poor property in a lab whose evidence
is per-interface ACL hit counts.

### R-06
**Guest ACL denied two /24s then permitted everything else.** *(Critical — fixed)*

`ACL_GUEST` on `BR-EDGE Fa3/0.50` was:

```
permit udp 10.30.50.0 0.0.0.255 host 10.20.30.10 eq 53
permit tcp 10.30.50.0 0.0.0.255 host 10.20.30.10 eq 53
deny   ip 10.30.50.0 0.0.0.255 10.10.99.0 0.0.0.255 log
deny   ip 10.30.50.0 0.0.0.255 10.20.30.0 0.0.0.255 log
permit ip any any
```

Only the HQ management VLAN and the Data Centre server VLAN were denied. The
trailing `permit ip any any` granted the guest VLAN full access to everything else
that exists in the network:

| Guest could reach | Should have been denied |
|-------------------|-------------------------|
| `10.10.10.0/24` HQ users | yes |
| `10.10.20.0/24` HQ corporate | yes |
| `10.30.40.0/24` Branch staff — same site, adjacent switch | yes |
| `10.60.60.0/24` DMZ | yes |
| `10.255.0.0/24` all WAN transit addresses | yes |

Guest access to the Branch staff VLAN is the most serious of these: it is the
shortest path from an untrusted device to a trusted one, needs no routing beyond the
local router, and is precisely the risk that putting guests in their own VLAN was
supposed to remove.

This is the characteristic failure mode of deny-list filtering at a trust boundary.
The ACL was very likely correct when written, and every subnet added to the network
since silently widened it.

**Resolution.** `ACL_GUEST_IN` now denies every enterprise zone by name, with the
DHCP, DNS and gateway-ICMP permits above the denies so the guest network stays
functional, and a closing `deny ip any any log` so drops are always counted:

```
permit udp any eq bootpc any eq bootps
permit udp 10.30.50.0 0.0.0.255 host 10.20.30.10 eq domain
permit tcp 10.30.50.0 0.0.0.255 host 10.20.30.10 eq domain
permit icmp 10.30.50.0 0.0.0.255 host 10.30.50.1
deny   ip 10.30.50.0 0.0.0.255 10.10.0.0 0.0.255.255 log
deny   ip 10.30.50.0 0.0.0.255 10.20.0.0 0.0.255.255 log
deny   ip 10.30.50.0 0.0.0.255 10.30.0.0 0.0.255.255 log
deny   ip 10.30.50.0 0.0.0.255 10.60.60.0 0.0.0.255 log
deny   ip 10.30.50.0 0.0.0.255 10.255.0.0 0.0.0.255 log
permit ip 10.30.50.0 0.0.0.255 any
deny   ip any any log
```

Note that the deny list now includes the guest VLAN's own zone (`10.30.0.0/16`).
Guest-to-guest traffic within `10.30.50.0/24` is switched, never reaching the router,
so it is unaffected; what this blocks is a guest reaching the staff VLAN or any other
address on the gateway. `ACL_WAN_BR_IN` at both WAN enforcement points was widened
the same way.

### R-07
**DMZ could initiate sessions into the user VLANs and the Branch.** *(High — fixed)*

`ACL_DMZ_IN` denied `10.10.99.0/24` and `10.20.30.0/24`, then ended
`permit ip 10.60.60.0 0.0.0.255 any`. The DMZ could therefore open sessions into
`10.10.10.0/24`, `10.10.20.0/24`, `10.30.40.0/24`, `10.30.50.0/24` and all WAN
transit addresses.

The DMZ is the one zone deliberately exposed to the Internet, which makes it the
most likely place in the design to be compromised. Its defining property must be
that it cannot initiate a session inward, or publishing a service converts a web
application vulnerability into a foothold on the internal network.

**Resolution.** `ACL_DMZ_IN` now permits the infrastructure services the DMZ
legitimately consumes — DNS, NTP and syslog, named per host and per port — plus
`established` and `echo-reply` so replies to clients that reached the published
services still work, then denies every trusted zone by name, then permits Internet
egress for patching. The `established` and `echo-reply` entries are load-bearing
rather than decorative: they sit above the zone denies and are what distinguish a
reply from an initiation.

### R-08
**DHCP pool on the management VLAN, and `ACL_VTY` trusting a whole /24.** *(Medium — fixed)*

Two findings that compound each other. `HQ-DIST` served a DHCP pool on
`10.10.99.0/24`, while both hosts on that VLAN are statically addressed — so the
pool had no legitimate client. And `ACL_VTY` on all five routers permitted:

```
permit tcp 10.10.99.0 0.0.0.255 any eq 22
permit tcp 10.20.30.0 0.0.0.255 any eq 22
```

Together: any device connected to an access port on `SW-HQ-1` or `MGMT-SW` would be
automatically addressed into the one subnet permitted to administer every router in
the enterprise. A DHCP pool on a management VLAN converts a physical-access problem
into a management-plane-access problem.

`ACL_VTY` also ended `deny ip any any` with no `log`, so refused administrative
attempts were silently dropped — the single most useful thing to have in the log.

**Resolution.** The VLAN 99 pool is removed and the management VLAN is static-only
by design. `ACL_VTY` names the two hosts that legitimately administer network
equipment, and logs refusals:

```
permit tcp host 10.10.99.10 any eq 22    ! AUTO-SRV  - automated changes
permit tcp host 10.10.99.11 any eq 22    ! JUMP-SRV  - interactive access
permit tcp 10.20.30.0 0.0.0.255 any eq 22
deny   ip any any log
```

The Data Centre server VLAN deliberately keeps subnet-level access as a break-glass
path: with only host entries, losing `HQ-DIST` or the HQ management VLAN would lock
administrators out of the entire estate. `MON-SRV` on that VLAN is the intended
recovery origin. That trade-off is stated rather than left implicit.

### R-14
**No `service timestamps`, so syslog evidence had no timestamps.** *(Medium — fixed)*

None of the five configurations set `service timestamps`, and none set
`clock timezone`. Messages therefore reached the collector carrying only an uptime
counter, with no wall-clock time and no timezone.

This undermined the whole logging chain. Centralised logging is a required service,
and its purpose is to let events on different devices be correlated — which requires
comparable timestamps. NTP was configured on every router, so the clocks were
correct; nothing was stamping the messages with them.

**Resolution.** All five routers now set:

```
service timestamps debug datetime msec localtime show-timezone
service timestamps log datetime msec localtime show-timezone
clock timezone AEST 10 0
logging origin-id hostname
```

`logging origin-id hostname` additionally makes messages carry the device name, so
the collector files under `/var/log/network/` are named per device rather than per
source IP. `syslog-setup.sh` also now writes a merged, time-ordered file, because
correlating an ACL denial on `BR-EDGE` with the OSPF adjacency change on `DC-EDGE`
that caused it is far easier in a single stream than across five.

---

## Configuration quality and completeness

### R-12
**Container scripts broke their own package installation.** *(Medium — fixed)*

Every script that used `apt-get` wrote `/etc/resolv.conf` to point at
`10.20.30.10` *before* running it. During first bring-up the `DNS` container is
usually not running yet, and even when it is, external resolution depends on PAT
being up. `apt-get update` therefore failed to resolve the Ubuntu mirrors, and
`ansible`, `netmiko`, `chrony`, `nginx` and `rsyslog` were silently never
installed — the scripts continued because every command was guarded with `|| true`.

The failure surfaces much later as an unexplained Part B problem, or as a service
that is simply absent with no error to point at.

**Resolution.** Package installation now completes first, using whatever resolver
the container inherited, and the enterprise resolver is written afterwards. Every
script also ends with a self-check that prints the interface address, the listening
socket and a live service probe, so a partial run is visibly distinguishable from a
successful one. Services are restarted rather than stacked, so re-running a script
after a container restart does not leave two listeners on a port.

### R-15
**Duplicate blocks, unprotected VTY range, duplicate config tree.** *(Medium — fixed)*

Three separate maintainability defects, each with a functional edge:

- **Duplicate `interface` blocks.** Several configurations declared an interface
  twice — once to address it, once to apply an ACL. IOS merges the blocks, so this
  works by accident. It makes the files unusable as Part B Jinja2 template targets,
  and it means an interface's complete policy cannot be read in one place.
- **`line vty 5 15` unprotected.** All five configurations applied
  `access-class ACL_VTY in` to `line vty 0 4` only. IOS supports 16 VTY lines; with
  five sessions already open, a sixth connection lands on line 5 and is subject to
  no ACL at all. The control appeared to be applied and was bypassable under load.
- **A byte-identical duplicate config tree.** `configs/routers/*.cfg` duplicated
  `configs/*.cfg`. `scripts/apply_on_mac.py` uploads from `configs/<NAME>.cfg`, so an
  edit made only in the other directory would be documented in the report and never
  reach a router, with nothing reporting an error.

**Resolution.** One block per interface and per line range; both VTY ranges carry
`access-class ACL_VTY in`; the duplicate tree is replaced by a pointer README. All
three properties are now enforced mechanically by
[`scripts/validate_configs.py`](../scripts/validate_configs.py), which also checks
that interface names exist on a c7200 with slots 0–3, that no ACL is referenced
before it is defined, that no exec-mode command appears in a startup config, that
banner delimiters balance, and that the security baseline the report claims is
actually present on all five devices. It exits non-zero on failure, so it can gate a
commit.

### R-20
**No assessable report, and rubric items with no artefact.** *(Medium — fixed)*

Reviewing the deliverables against the assessment brief rather than against the
previous documentation surfaced several gaps:

| Brief requirement | Gap | Resolution |
|-------------------|-----|------------|
| Technical report with Executive Summary, Introduction, Testing, Discussion, Conclusion, ≥5 IEEE references | The repository held design notes and a nine-line checklist, but nothing assessable | [`report/PartA_Report.md`](../report/PartA_Report.md) |
| MS Word, 1.5 spacing, 11 pt Calibri, 2.54 cm margins | No build path to a compliant document | [`report/BUILD_DOCX.md`](../report/BUILD_DOCX.md) |
| 2000-word limit across Parts A–C | Unbounded prose would have consumed the whole budget on Part A | Report is word-budgeted: ~700 words of narrative, with tables and configurations in appendices |
| Connectivity verification | Nine unordered one-line checks, no expected results | [`verification/CHECKS.md`](../verification/CHECKS.md) rewritten as an ordered plan with expected output |
| Screenshots | No specification of what to capture | Numbered evidence list with a figure caption for each |
| GenAI citation | Not addressed | Declaration in the report, IEEE-referenced |

---

## Accepted risks

### R-16
**No STP, port security or LACP on the GNS3 built-in switches.** *(Medium — accepted)*

The built-in Ethernet switch implements access-port VLAN assignment and 802.1Q
tagging, and nothing else. The consequences are accepted deliberately:

- The Layer 2 topology must be a loop-free tree by construction (R-02), so Layer 2
  redundancy is out of scope. Redundancy is provided at Layer 3 by OSPF instead,
  which is where this design would put it in production regardless.
- Port security, BPDU guard and RSTP root-bridge election cannot be demonstrated.
  They are discussed in the report as design intent with the configuration that
  would implement them, and explicitly **not** claimed as verified.

The alternative is 17 IOSvL2 instances, needing roughly 8 GB of RAM in the GNS3 VM
against the 4 GB available — and on an Apple silicon host, x86 software emulation on
top of that. The trade-off is stated rather than hidden: the switching layer is
functionally sufficient to prove VLAN segmentation, inter-VLAN routing, per-VLAN
DHCP and VLAN-based ACL enforcement, which is what Part A requires of it.

### R-19
**Stateless inspection at the Internet edge.** *(Medium — accepted, upgrade path documented)*

After R-10, `ACL_OUTSIDE_IN` is an allow-list ending in an explicit deny, which is a
substantial improvement — but it is still *stateless*. Return traffic is matched
structurally rather than against a session table, and two residual gaps follow:

- A crafted TCP segment with the ACK bit set matches `permit tcp any any established`
  without belonging to any session.
- `permit udp any any gt 1023` is a wide grant, because stateless filtering cannot
  distinguish a DNS reply from an unsolicited packet to a high port.

Genuine stateful inspection is available on this platform through CBAC, which would
let the return-traffic entries collapse into `deny ip any any log` with pinholes
opened per session. It is not enabled in the baseline because `ip inspect` session
tracking is measurably expensive on emulated MIPS hardware shared with four other
Dynamips instances, and a stateful edge is not a Part A requirement. The exact
configuration is provided as a commented block in
[`configs/FW-EDGE.cfg`](../configs/FW-EDGE.cfg), so the gap is a stated scope
boundary with a costed remedy rather than an omission.

---

### R-17
**`PC5`/`PC8` documented at Branch but wired at HQ.** *(Low — resolved: keep at HQ)*

A briefing note described `PC5`–`PC9` as Branch hosts. The live topology export
([`LINK_MAP.md`](LINK_MAP.md) links 28 and 44) has `PC5` on `SW-HQ-3 Eth1` and `PC8`
on `SW-HQ-4 Eth1`, both at HQ, and `ports_mapping.json` has those ports on VLAN 10
and VLAN 20 respectively.

**Decision: keep them at HQ, as wired.** Confirmed with the lab operator, so no
recabling is required and no configuration changes: `PC5` takes a VLAN 10 lease and
`PC8` a VLAN 20 lease from `HQ-DIST` automatically. The final endpoint distribution is:

| Site | VLAN | Endpoints |
|------|-----:|-----------|
| HQ | 10 | `PC1` (`SW-HQ-1`), `PC5` (`SW-HQ-3`) |
| HQ | 20 | `PC2` (`SW-HQ-2`), `PC8` (`SW-HQ-4`) |
| Branch | 40 | `PC3`, `PC7` (`SW-BR-1`), `PC6` (`SW-BR-3`) |
| Branch | 50 | `PC4` (`SW-BR-2`), `PC9` (`SW-BR-4`) |
| DMZ | 60 | `PC-DMZ` (`SW-DMZ-1`) |

This distribution is what every document in the repository already states —
`NODE_INVENTORY.md` §5, `TOPOLOGY.md` §3.4, `configs/vpcs/README.md`,
`report/tables/hosts.csv` and `report/PartA_Report.md` Table 4 — so nothing needed
changing beyond recording the decision here.

It also happens to be the better arrangement for the evidence. Each site ends up with
two endpoints per VLAN on **two different access switches**, so a DHCP screenshot
proves the scope reaches a second access block rather than just a second port, and the
Branch keeps its staff/guest split across four separate switches.

The alternative was to move both to `SW-BR-3`/`SW-BR-4`. What would **not** have been
acceptable is changing only the documents, which would have reintroduced exactly the
report-versus-lab divergence this register exists to eliminate.

---

## Verification of the fixes

Every fix above is covered by a numbered check in
[`../verification/CHECKS.md`](../verification/CHECKS.md):

| Finding | Verified by |
|---------|-------------|
| R-01 | §1.1 — `HQ-CORE Fa0/0` shows `10.255.0.18` and no `ip nat` |
| R-02 | §1.3 — no broadcast storm; each access switch has exactly one uplink |
| R-03 | §7.3 — inbound HTTP to the outside address reaches `WEB-SRV` |
| R-04 | §3.5 — exactly one `O*E2 0.0.0.0/0`, originated by `4.4.4.4` |
| R-05 | §6.2 — guest denies counted on `HQ-CORE Fa3/0` during failover |
| R-06 | §6.1 — `PC4` cannot reach the staff VLAN, DMZ or WAN addresses |
| R-07 | §6.3 — `WEB-SRV` cannot open a session into any trusted zone |
| R-08 | §6.4 — SSH permitted from `AUTO-SRV`, refused and logged elsewhere |
| R-09, R-11 | §8.1 — a router resolves a name; an external name resolves |
| R-10 | §7.1 — `Fa0/0` holds a lease; §8.1 external resolution works |
| R-12 | §8 — each container's self-check output |
| R-13 | §2.2 — VLAN 60 arrives tagged; `PC-DMZ` gets a lease |
| R-14 | §8.3 — collector entries carry wall-clock time and a device name |
| R-15 | §0.2 — `validate_configs.py` exits zero; `show line` shows both ranges guarded |
| R-18 | §7.2 — no WAN transit address appears in the translation table |
