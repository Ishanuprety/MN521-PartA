# Part A — Connectivity Verification Plan

An ordered test plan with a **screenshot slot** for each piece of evidence.

> **STATUS: NOT YET EXECUTED.** No output in this document has been captured from
> the lab. Every result cell is an empty slot to be filled in after the tests are
> run. Nothing here fabricates a ping count, an OSPF metric, a translation table or
> a log line — where a value can be *derived from the design* it is labelled
> **(expected by design)**; where it can only come from the device it is left blank.

Run the sections in order. An OSPF fault invalidates every reachability result after
it, and a DHCP fault invalidates every host test — so a failure early on means stop
and fix, not carry on.

- Addressing: [`../docs/IP_ADDRESSING.md`](../docs/IP_ADDRESSING.md)
- Cabling: [`../docs/TOPOLOGY.md`](../docs/TOPOLOGY.md)
- Screenshot files: save into [`../report/figures/`](../report/figures/) using the
  `SS-nn` names below, so the report picks them up without renaming.

---

## How to fill this in

For each check: run the command where stated, decide pass/fail against the criterion,
tick the box, and save the screenshot as `report/figures/SS-nn-<slug>.png`.

| Column | Meaning |
|--------|---------|
| **Check** | What is being proved |
| **Where / command** | Device and exact command |
| **Pass criterion** | What makes it a pass — written before the test, not after |
| **SS** | Screenshot slot. `—` means no screenshot needed |
| **Result** | Leave blank until executed. Record `PASS` / `FAIL` + note |

---

## 0. Pre-flight

| # | Check | Where / command | Pass criterion | SS | Result |
|---|-------|-----------------|----------------|----|--------|
| 0.1 | Configs are structurally valid | repo: `python3 scripts/validate_configs.py` | Exits `0`, reports `0 fail` | — | |
| 0.2 | Correct config revision is live | each router: `show running-config interface FastEthernet0/0` | `HQ-CORE Fa0/0` is `10.255.0.18/30` with **no** `ip nat` command. Anything else means the superseded NAT-on-`Fa0/0` revision is still loaded — see `REVIEW_FINDINGS.md` R-01 | `SS-01` | |
| 0.3 | Loop links removed | GNS3 topology | `SW-HQ-1 Eth7`, `SW-DC-1 Eth7`, `SW-BR-1 Eth7` have **no** cable. See `REVIEW_FINDINGS.md` R-02 | `SS-02` | |
| 0.4 | SSH host keys generated | each router: `show ip ssh` | `SSH Enabled - version 2.0`. `SSH Disabled` means the post-boot RSA key step was skipped | — | |
| 0.5 | Platform sanity | each router: `show version \| include IOS Software` | c7200, IOS 15.x | — | |

---

## 1. Interfaces and Layer 1/2

| # | Check | Where / command | Pass criterion | SS | Result |
|---|-------|-----------------|----------------|----|--------|
| 1.1 | Interface inventory | each router: `show ip interface brief` | Every address matches `IP_ADDRESSING.md` §4. `up/up` on all addressed interfaces | `SS-03` | |
| 1.2 | Standby ports are down **by design** | `HQ-DIST`, `DC-EDGE`, `BR-EDGE` | `HQ-DIST Fa1/0`, `DC-EDGE Fa2/0`, `BR-EDGE Fa1/0` are `administratively down`. This is the expected state, not a fault | — | |
| 1.3 | No broadcast storm | any switch-attached host, and GNS3 CPU usage | Idle CPU normal; VPCS hosts get leases promptly. A storm presents as GNS3 becoming unresponsive rather than as an error | — | |
| 1.4 | Directly connected neighbours | `HQ-CORE`: `ping 10.255.0.17`, `ping 10.255.0.2`, `ping 10.255.0.10`, `ping 10.255.0.22` | All four succeed. `10.255.0.22` proves the `WAN-Cloud` hub segment carries traffic | — | |

**Expected by design** — addresses to check in 1.1:

| Device | Interface | Address |
|--------|-----------|---------|
| `FW-EDGE` | `Fa0/0` / `Fa1/0` / `Fa2/0.60` / `Lo0` | DHCP / `10.255.0.17` / `10.60.60.1` / `4.4.4.4` |
| `HQ-CORE` | `Fa0/0` / `Fa1/0` / `Fa2/0` / `Fa3/0` / `Lo0` | `10.255.0.18` / `10.255.0.1` / `10.255.0.9` / `10.255.0.21` / `1.1.1.1` |
| `HQ-DIST` | `Fa0/0` / `Fa2/0.10` / `.20` / `.99` / `Lo0` | `10.255.0.10` / `10.10.10.1` / `10.10.20.1` / `10.10.99.1` / `1.1.1.4` |
| `DC-EDGE` | `Fa0/0` / `Fa1/0` / `Fa3/0.30` / `Lo0` | `10.255.0.2` / `10.255.0.5` / `10.20.30.1` / `2.2.2.2` |
| `BR-EDGE` | `Fa0/0` / `Fa2/0` / `Fa3/0.40` / `.50` / `Lo0` | `10.255.0.6` / `10.255.0.22` / `10.30.40.1` / `10.30.50.1` / `3.3.3.3` |

---

## 2. VLANs and inter-VLAN routing

| # | Check | Where / command | Pass criterion | SS | Result |
|---|-------|-----------------|----------------|----|--------|
| 2.1 | Subinterface encapsulation | `HQ-DIST`: `show vlans` | VLAN IDs 10, 20, 99 listed, each with its address, and **non-zero received counters** once hosts are up. Zero received on a VLAN means the switch access port is on the wrong VLAN | `SS-04` | |
| 2.2 | DMZ VLAN arrives **tagged** | `FW-EDGE`: `show vlans`; `PC-DMZ`: `dhcp` | VLAN 60 shows received traffic and `PC-DMZ` gets a lease. This specifically re-tests `REVIEW_FINDINGS.md` R-13 — the trunk previously carried VLAN 60 untagged and the DMZ was dark | `SS-05` | |
| 2.3 | Remaining VLANs | `DC-EDGE`: `show vlans` (30); `BR-EDGE`: `show vlans` (40, 50) | Each VLAN present with its gateway address | — | |
| 2.4 | Inter-VLAN routing works | `PC1`: `ping 10.10.20.1` then `ping <PC2 address>` | Both succeed — VLAN 10 to VLAN 20 via the router | `SS-06` | |
| 2.5 | VLAN 1 unused | switch port matrix vs `ports_mapping.json` | No host port is on VLAN 1; all trunks have native VLAN 1 | — | |

---

## 3. OSPF

| # | Check | Where / command | Pass criterion | SS | Result |
|---|-------|-----------------|----------------|----|--------|
| 3.1 | Adjacencies | each router: `show ip ospf neighbor` | **5 adjacencies total.** Neighbour counts: `HQ-CORE` 4, `DC-EDGE` 2, `BR-EDGE` 2, `FW-EDGE` 1, `HQ-DIST` 1. All in `FULL`. DR/BDR split is **not** a pass criterion — `FULL` is | `SS-07` | |
| 3.2 | Router IDs and roles | each router: `show ip ospf` | `FW-EDGE` reports autonomous system boundary router; `HQ-DIST`, `DC-EDGE`, `BR-EDGE` report area border router; `HQ-CORE` reports **neither** (it is pure transit — if it reports ASBR, the superseded `default-information originate` is still present, R-04) | `SS-08` | |
| 3.3 | Area 0 authentication | each router: `show ip ospf interface FastEthernet<n>` | `Message digest authentication enabled` on every area 0 interface. A one-sided key leaves the neighbour down with a mismatch log — see §10.2 | `SS-09` | |
| 3.4 | Passive interfaces | `HQ-DIST`, `DC-EDGE`, `BR-EDGE`, `FW-EDGE`: `show ip protocols` | Every LAN/DMZ subinterface and `Loopback0` is passive; WAN interfaces are not. An active LAN subinterface means hellos are leaking onto a user VLAN | — | |
| 3.5 | One default route only | `HQ-DIST`, `DC-EDGE`, `BR-EDGE`: `show ip route 0.0.0.0` | Exactly **one** `O*E2 0.0.0.0/0`, advertised by router ID `4.4.4.4`. Two entries, or one from `1.1.1.1`, means R-04 has regressed | `SS-10` | |
| 3.6 | Full routing table | `BR-EDGE`: `show ip route ospf` | All remote prefixes present: `10.10.10.0/24`, `10.10.20.0/24`, `10.10.99.0/24`, `10.20.30.0/24`, `10.60.60.0/24`, the WAN /30s, and the four remote loopbacks | `SS-11` | |
| 3.7 | Backup path is **not** preferred | `BR-EDGE`: `show ip route 10.10.10.0` | Next hop is `10.255.0.5` (`DC-EDGE`), **not** `10.255.0.21`. Cost 50 on the backup is what produces this; a next hop of `10.255.0.21` means the cost was not applied and the `DC-EDGE` enforcement point is being bypassed (R-05) | `SS-12` | |
| 3.8 | Loopback area placement | `BR-EDGE`: `show ip route 1.1.1.1` and `show ip route 1.1.1.4` | `1.1.1.1/32` is intra-area `O`; `1.1.1.4/32` is inter-area `O IA`. `HQ-CORE` puts its loopback in area 0, `HQ-DIST` in area 10 — getting these the wrong way round is the classic misreading of a multi-area table | — | |

**Metric check (expected by design, verify on the device).** Every link is
FastEthernet, so each hop costs exactly 1 (`10^8 / 10^8`) and the metric should equal
the number of egress interfaces traversed. The only deliberate exception is the
backup WAN at cost 50. Any other value means an interface bandwidth or cost was
changed by hand — worth checking rather than skimming.

---

## 4. DHCP

| # | Check | Where / command | Pass criterion | SS | Result |
|---|-------|-----------------|----------------|----|--------|
| 4.1 | Pools and bindings | `HQ-DIST`, `BR-EDGE`, `FW-EDGE`: `show ip dhcp pool`, `show ip dhcp binding` | Six pools across three routers. Leases present for the endpoints in each VLAN. **All leases start at `.21`** because `.1`–`.20` are excluded | `SS-13` | |
| 4.2 | No pool on the management VLAN | `HQ-DIST`: `show ip dhcp pool` | **No** `VLAN99` pool. Its presence is R-08 — a pool on the subnet `ACL_VTY` trusts | — | |
| 4.3 | Data Centre pool has zero leases | `DC-EDGE`: `show ip dhcp pool VLAN30_DC_SERVERS` | `Leased addresses: 0` — all five DC servers are static. **Zero is the correct result here**, not a fault | — | |
| 4.4 | No address conflicts | each DHCP router: `show ip dhcp conflict` | Empty. Any entry means a static address overlaps a pool | — | |
| 4.5 | Client-side confirmation | `PC1`, `PC2`, `PC3`, `PC5`–`PC9`: `show ip` | Correct subnet, mask, gateway, DNS `10.20.30.10`, domain `corp.local`. Which host gets `.21` vs `.22` depends on boot order and is **not** a pass criterion | `SS-14` | |
| 4.6 | Guest scope is distinct | `PC4`, `PC9`: `show ip` | Domain is **`guest.corp.local`**, not `corp.local`. This is the client-side proof that scope separation works, visible without touching a router | `SS-15` | |
| 4.7 | DMZ scope is distinct | `PC-DMZ`: `show ip` | Domain is **`dmz.corp.local`**, served by `FW-EDGE` not a site router | `SS-16` | |
| 4.8 | Option 42 (NTP) is offered | `HQ-DIST`: `show running-config \| section dhcp pool` | `option 42 ip 10.20.30.11` present in the corporate pools and **absent** from the guest pool. Note: VPCS neither requests nor displays option 42, so `show ip` is **not** evidence for it — this is the router-side check instead | — | |

---

## 5. End-to-end reachability (must succeed)

| # | Check | Where / command | Pass criterion | SS | Result |
|---|-------|-----------------|----------------|----|--------|
| 5.1 | HQ user → DC services | `PC1`: `ping 10.20.30.10`, `ping 10.20.30.13` | Both succeed | `SS-17` | |
| 5.2 | Branch staff → DC services | `PC3`: `ping 10.20.30.10`, `ping 10.20.30.13` | Both succeed — the positive control for §6.1 | `SS-18` | |
| 5.3 | Path traverses the Data Centre | `PC3`: `trace 10.10.10.1` | Hops show `10.30.40.1` → `10.255.0.5` → `10.255.0.1`/`10.255.0.9` → destination. Proves the primary path, not the backup | `SS-19` | |
| 5.4 | Cross-site loopback reachability | `AUTO-SRV`: `ping 4.4.4.4`, `1.1.1.1`, `1.1.1.4`, `2.2.2.2`, `3.3.3.3` | All five succeed. These are the Part B Ansible targets | `SS-20` | |
| 5.5 | Router-sourced service reachability | `BR-EDGE`: `ping 10.20.30.12 source Loopback0` | Succeeds — confirms the syslog source address is routable from the most distant site | — | |
| 5.6 | Estate sweep | `MON-SRV`: `curl http://127.0.0.1:9090/health` | All 14 targets report `UP`. One artefact covering the whole estate | `SS-21` | |

---

## 6. Security enforcement (must FAIL where stated)

A **pass** here means the traffic is blocked. Clear counters first so hits are
attributable: `clear ip access-list counters <name>`.

| # | Check | Where / command | Pass criterion | SS | Result |
|---|-------|-----------------|----------------|----|--------|
| 6.1 | Guest containment | `PC4`: ping `10.30.40.1`, `10.20.30.13`, `10.10.99.10`, `10.60.60.10`, `10.255.0.5` | **All five fail**, administratively prohibited. `10.30.40.1` (Branch staff, adjacent switch) and `10.60.60.10` (DMZ) are the two that the previous ACL permitted — R-06 | `SS-22` | |
| 6.2 | Guest containment survives failover | shut `DC-EDGE Fa1/0`, wait for reconvergence, repeat 6.1 from `PC4`, then `show ip access-lists ACL_WAN_BR_IN` on `HQ-CORE` | Still blocked, with **non-zero deny counters on `HQ-CORE`**. This is the R-05 regression test. Restore `DC-EDGE Fa1/0` afterwards | `SS-23` | |
| 6.3 | DMZ cannot pivot inward | `WEB-SRV`: `ping 10.20.30.13`, `ping 10.10.10.1`; then `FW-EDGE`: `show ip access-lists ACL_DMZ_IN` | Both fail, with deny counters incrementing. R-07 | `SS-24` | |
| 6.4 | Guest **can** still resolve names | `PC4`: resolve a `corp.local` name against `10.20.30.10`, then `ping 10.20.30.10` | Resolution **succeeds**, ping **fails**. That pair together is the evidence that isolation is selective rather than the guest network simply being broken | `SS-25` | |
| 6.5 | HQ users cannot reach management | `PC1`: `ping 10.10.99.10`; then `HQ-DIST`: `show ip access-lists ACL_HQ_USERS_IN` | Fails, deny counter increments. `PC1` → `10.20.30.10` still succeeds (users are not cut off from DC services) | `SS-26` | |
| 6.6 | SSH permitted from the two named hosts | `AUTO-SRV`: `ssh admin@1.1.1.1`; `JUMP-SRV`: `ssh hq-core` | Both reach a login banner and prompt | `SS-27` | |
| 6.7 | SSH refused from anywhere else | `PC2` or `FILE-SRV`: attempt SSH to `1.1.1.1`; then on `HQ-CORE`: `show ip access-lists ACL_VTY` and `show logging` | Refused, **and** the `deny ip any any log` counter increments with a log entry. R-08 | `SS-28` | |
| 6.8 | Telnet refused everywhere | any host: `telnet 1.1.1.1` | Refused — `transport input ssh` permits SSH only | — | |
| 6.9 | Both VTY ranges guarded | each router: `show running-config \| section line vty` | `access-class ACL_VTY in` on **`line vty 0 4` and `line vty 5 15`**. R-15 | — | |
| 6.10 | Anti-spoofing present | `FW-EDGE`: `show ip access-lists ACL_OUTSIDE_IN`, `show ip interface FastEthernet0/0 \| include access list` | ACL applied inbound; the five enterprise-zone deny entries present and first. Counters will typically be **zero** in a lab with no hostile traffic — this control is verified by presence and placement, which is the correct expectation to state rather than manufacturing hits | `SS-29` | |
| 6.11 | CDP off where it should be | `FW-EDGE`, `BR-EDGE`: `show cdp interface` | `Fa0/0`, `Fa2/0.60` and `Fa3/0.50` absent from the list | — | |

---

## 7. NAT

| # | Check | Where / command | Pass criterion | SS | Result |
|---|-------|-----------------|----------------|----|--------|
| 7.1 | Outside interface has a lease | `FW-EDGE`: `show dhcp lease`, `show ip interface brief \| include Fa0/0` | A bound lease and an address on `Fa0/0`. If absent, nothing else in §7 can pass. Note the closing `deny` in `ACL_OUTSIDE_IN` makes the `bootps→bootpc` permit load-bearing — R-10 | `SS-30` | |
| 7.2 | Outbound PAT | from `PC1`, `PC3`, `PC4` ping an Internet address; then `FW-EDGE`: `show ip nat translations`, `show ip nat statistics` | One entry per source, **all sharing one inside global address** — that is what proves overload/PAT rather than one-to-one. `Inside interfaces` must list `Fa1/0` **and** `Fa2/0.60`. **No** `10.255.0.x` address appears — R-18 | `SS-31` | |
| 7.3 | Inbound published web service | from outside the enterprise: HTTP to `FW-EDGE`'s outside address; then `show ip nat translations` | The `WEB-SRV` page is returned and a static translation entry is present. This is the R-03 regression test — the whole inbound path was previously non-functional | `SS-32` | |
| 7.4 | Inbound published app service | from outside: HTTP to the outside address on port `8080` | The `APP-SRV` JSON payload is returned | `SS-33` | |
| 7.5 | Inbound ping is refused **by design** | from outside: ping `FW-EDGE`'s outside address | **Fails.** `ACL_OUTSIDE_IN` permits no inbound `echo`. Expected, not a fault | — | |
| 7.6 | Static translations present | `FW-EDGE`: `show ip nat statistics \| begin Static` | Two static entries: `10.60.60.10:80` and `10.60.60.11:8080` | — | |

---

## 8. Infrastructure services

| # | Check | Where / command | Pass criterion | SS | Result |
|---|-------|-----------------|----------------|----|--------|
| 8.1 | DNS — internal name from a router | any router: `ping web.corp.local` | Resolves to `10.60.60.10` and replies. Fails outright if `no ip domain-lookup` is present — R-11 | `SS-34` | |
| 8.2 | DNS — external name and reverse | `DNS`: resolve an external name, and reverse-resolve `10.60.60.10` | External name resolves (proves upstream forwarding, R-09) and the reverse lookup returns `web.corp.local` (proves `host-record` PTRs) | `SS-35` | |
| 8.3 | DNS server-side evidence | `DNS`: `tail /var/log/dnsmasq.log` | Queries from router and host addresses visible | — | |
| 8.4 | NTP synchronisation | each router: `show ntp status`, `show ntp associations`; `NTP`: `chronyc clients` | Routers report **synchronised at stratum 11** (the server is `local stratum 10`, so 11 is correct) and reference `10.20.30.11`. Allow **up to ~10 minutes** after boot — unsynchronised immediately after boot is expected, not a fault | `SS-36` | |
| 8.5 | Clock and timezone | each router: `show clock detail` | Time is **not** prefixed with `*` (a leading `*` means unauthoritative) and the zone shows `AEST` | — | |
| 8.6 | Syslog collection | `SYSLOG`: `ls /var/log/network/`, then `tail /var/log/network/all-devices.log` | **Five** sender files, one per router. Entries carry **wall-clock timestamps** — R-14, previously absent | `SS-37` | |
| 8.7 | Syslog captures a real security event | after §6.1: `SYSLOG`: grep the collector for the ACL denial messages | The guest-isolation denials appear on the collector. This closes the loop between the ACL test and the centralised logging requirement | `SS-38` | |
| 8.8 | Automation server ready | `AUTO-SRV`: `ansible --version`, `ansible-inventory --list`, `ansible routers -m ios_facts` | Ansible and Netmiko installed, inventory parses, all five routers reachable. Confirms the R-12 script-ordering fix and sets up Part B | `SS-39` | |
| 8.9 | Container self-checks | each of the nine: re-run its `*-setup.sh` | Each ends with its self-check block showing address, listening socket and a successful local service probe | — | |

---

## 9. Resilience

| # | Check | Where / command | Pass criterion | SS | Result |
|---|-------|-----------------|----------------|----|--------|
| 9.1 | Baseline path | `BR-EDGE`: `show ip route 10.10.10.0` | Next hop `10.255.0.5` via the Data Centre | — | |
| 9.2 | Failover | shut `DC-EDGE Fa1/0`; from `PC3` ping `10.10.10.1` continuously; then `BR-EDGE`: `show ip route 10.10.10.0` | Connectivity restores after OSPF reconvergence, next hop becomes `10.255.0.21` via `WAN-Cloud`. Record how many pings were lost | `SS-40` | |
| 9.3 | Policy holds during failover | see §6.2 | — | — | |
| 9.4 | Failback | restore `DC-EDGE Fa1/0`; recheck 9.1 | Next hop returns to `10.255.0.5`, because cost 50 makes the backup less preferred | `SS-41` | |

---

## 10. Troubleshooting quick reference

### 10.1 A host gets no DHCP lease
Check in this order: the switch access port VLAN in `ports_mapping.json` (a port left
at the GNS3 default `1 / access` is the most common cause); `show vlans` on the
router (is traffic arriving on that VLAN ID at all?); `show ip dhcp pool` (is a pool
defined for that subnet?); then the ACL on that subinterface.

### 10.2 An OSPF neighbour will not reach FULL

| Symptom | Likely cause | Check |
|---------|--------------|-------|
| No neighbour at all | Interface passive, or link down | `show ip protocols` — is the WAN interface in the passive list by mistake? |
| Neighbour down after re-applying configs | MD5 key on one side only | `show ip ospf interface <if>` both ends; both must show message digest authentication enabled. Rollback if needed: `no area 0 authentication message-digest` |
| Stuck in `EXSTART`/`EXCHANGE` | MTU mismatch | `show interfaces \| include MTU` — 1500 both ends |
| Flapping | Duplicate router ID | `show ip ospf \| include Router ID` |

### 10.3 Internet works from one site but not another
`show ip nat statistics` on `FW-EDGE` — `Inside interfaces` must list both `Fa1/0`
and `Fa2/0.60`. A missing `ip nat inside` on one interface is the classic
half-working NAT symptom.

### 10.4 Whole project becomes unresponsive
Suspect a Layer 2 loop before suspecting host performance. Verify the three
cross-links in §0.3 are deleted.

### 10.5 SSH refused everywhere
Almost always the missing post-boot RSA key. `show ip ssh` reporting `SSH Disabled`
confirms it. Note the key is **not** restored by re-applying a startup config — key
material is not part of the configuration.

---

## 11. Sign-off matrix

Each row maps a Part A required service to the checks that prove it.

| # | Requirement | Checks | Pass |
|---|-------------|--------|------|
| 1 | Topology built as designed, loop-free | §0.3, §1.1–1.3 | ☐ |
| 2 | VLANs configured and carrying tagged traffic | §2.1–2.3, §2.5 | ☐ |
| 3 | Inter-VLAN routing | §2.4, §5.1 | ☐ |
| 4 | OSPF multi-area, correct roles, authenticated | §3.1–3.4 | ☐ |
| 5 | OSPF converged, single default, correct path preference | §3.5–3.8 | ☐ |
| 6 | DHCP across six pools with full options | §4.1–4.8 | ☐ |
| 7 | End-to-end reachability across all zones | §5 | ☐ |
| 8 | SSH secured and source-restricted | §6.6–6.9 | ☐ |
| 9 | ACLs enforcing guest, DMZ and management isolation | §6.1–6.5, §6.10 | ☐ |
| 10 | NAT: outbound PAT and inbound publishing | §7 | ☐ |
| 11 | DNS | §8.1–8.3 | ☐ |
| 12 | NTP | §8.4–8.5 | ☐ |
| 13 | Syslog | §8.6–8.7 | ☐ |
| 14 | Linux automation server | §8.8 | ☐ |
| 15 | Redundancy demonstrated by failover | §9 | ☐ |

---

## 12. Screenshot index

Save as `report/figures/SS-nn-<slug>.png`. The report references these names, so
correct naming means no editing later.

| Slot | Caption for the report |
|------|------------------------|
| `SS-01` | `HQ-CORE Fa0/0` running the current revision — routed /30, no NAT |
| `SS-02` | GNS3 topology after removing the three access-layer cross-links |
| `SS-03` | `show ip interface brief` across all five routers |
| `SS-04` | `show vlans` on `HQ-DIST` — VLANs 10, 20, 99 with traffic counters |
| `SS-05` | DMZ VLAN 60 tagged correctly; `PC-DMZ` obtains a lease |
| `SS-06` | Inter-VLAN routing: `PC1` to VLAN 20 |
| `SS-07` | `show ip ospf neighbor` — five adjacencies, all FULL |
| `SS-08` | OSPF roles: `FW-EDGE` as ASBR, three ABRs, `HQ-CORE` neither |
| `SS-09` | Area 0 MD5 authentication enabled |
| `SS-10` | Single `O*E2` default route, originated by `4.4.4.4` |
| `SS-11` | `show ip route ospf` on `BR-EDGE` — full inter-area table |
| `SS-12` | Primary path preferred: `BR-EDGE` to HQ via `DC-EDGE`, not the cost-50 backup |
| `SS-13` | DHCP pools and bindings across the three DHCP routers |
| `SS-14` | `show ip` on the corporate endpoints |
| `SS-15` | Guest endpoints receiving `guest.corp.local` |
| `SS-16` | `PC-DMZ` receiving `dmz.corp.local` from `FW-EDGE` |
| `SS-17` | HQ user reaching Data Centre services |
| `SS-18` | Branch staff reaching Data Centre services |
| `SS-19` | `trace` from `PC3` confirming the Data Centre transit path |
| `SS-20` | `AUTO-SRV` reaching all five router loopbacks |
| `SS-21` | `MON-SRV` estate sweep — 14 targets up |
| `SS-22` | Guest containment: five destinations refused from `PC4` |
| `SS-23` | Guest containment holding during failover, counters on `HQ-CORE` |
| `SS-24` | DMZ unable to initiate into a trusted zone |
| `SS-25` | Selective isolation: guest resolves names but cannot ping the DNS host |
| `SS-26` | HQ users blocked from the management VLAN |
| `SS-27` | SSH permitted from `AUTO-SRV` and `JUMP-SRV` |
| `SS-28` | SSH refused from an unauthorised source, and logged |
| `SS-29` | Perimeter anti-spoofing ACL applied inbound on `FW-EDGE Fa0/0` |
| `SS-30` | `FW-EDGE` outside interface holding a DHCP lease |
| `SS-31` | Outbound PAT: several sources sharing one inside global address |
| `SS-32` | Inbound published web service reaching `WEB-SRV` |
| `SS-33` | Inbound published app service reaching `APP-SRV` |
| `SS-34` | Name resolution from a router console |
| `SS-35` | External resolution and reverse lookup on `DNS` |
| `SS-36` | Routers synchronised at stratum 11 |
| `SS-37` | Syslog collector: five per-device files with wall-clock timestamps |
| `SS-38` | ACL denials from §6.1 arriving at the collector |
| `SS-39` | `AUTO-SRV`: Ansible inventory parsing and reaching all five routers |
| `SS-40` | Failover onto the backup WAN via `WAN-Cloud` |
| `SS-41` | Failback to the primary Data Centre path |
