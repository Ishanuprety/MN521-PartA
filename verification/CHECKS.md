# MN521 Part A — Verification & Test Evidence

Run the sections in order: an OSPF problem invalidates every reachability test after it, and a DHCP problem
invalidates every host test. Each check lists the **exact command**, **where to run it**, and the **expected
result** that constitutes a pass. Capture the output of every command marked **[EVIDENCE]** as a screenshot
for the submission.

Device roles, addresses and link IDs referenced below come from [../docs/IP_ADDRESSING.md](../docs/IP_ADDRESSING.md)
and [../docs/TOPOLOGY.md](../docs/TOPOLOGY.md).

---

## 0. Pre-flight

| # | Where | Command | Expected result |
|---|-------|---------|-----------------|
| 0.1 | each router | `show version \| include IOS Software\|bytes of memory` | c7200 platform, IOS 15.x Advanced Enterprise |
| 0.2 | each router | `show ip interface brief` | see §1.1 — no `administratively down` except `HQ-DIST Fa2/0` |
| 0.3 | each router | `show running-config \| include hostname\|ip domain-name` | correct hostname and `ip domain-name corp.local` |
| 0.4 | each router | `show logging \| include Trap\|Logging to` | `Logging to 10.20.30.12` … `informational` |

---

## 1. Layer 1 / Layer 2 / interface state

### 1.1 Interface inventory **[EVIDENCE]**

```
show ip interface brief
```

Expected, per device (`YES DHCP`/`YES manual`, `up up` in both status columns):

| Device | Interface | IP-Address | Status | Protocol |
|--------|-----------|-----------|--------|----------|
| `HQ-CORE` | `FastEthernet0/0` | `192.168.122.x` (DHCP) | up | up |
| `HQ-CORE` | `FastEthernet1/0` | `10.255.0.1` | up | up |
| `HQ-CORE` | `FastEthernet2/0` | `10.255.0.9` | up | up |
| `HQ-CORE` | `Loopback0` | `1.1.1.1` | up | up |
| `HQ-DIST` | `FastEthernet0/0` | `10.255.0.10` | up | up |
| `HQ-DIST` | `FastEthernet1/0` | unassigned | up | up |
| `HQ-DIST` | `FastEthernet1/0.10` | `10.10.10.1` | up | up |
| `HQ-DIST` | `FastEthernet1/0.20` | `10.10.20.1` | up | up |
| `HQ-DIST` | `FastEthernet1/0.99` | `10.10.99.1` | up | up |
| `HQ-DIST` | `FastEthernet2/0` | unassigned | **administratively down** | down |
| `HQ-DIST` | `Loopback0` | `1.1.1.4` | up | up |
| `DC-EDGE` | `FastEthernet0/0` | `10.255.0.2` | up | up |
| `DC-EDGE` | `FastEthernet1/0` | `10.255.0.5` | up | up |
| `DC-EDGE` | `FastEthernet2/0` | unassigned | up | up |
| `DC-EDGE` | `FastEthernet2/0.30` | `10.20.30.1` | up | up |
| `DC-EDGE` | `Loopback0` | `2.2.2.2` | up | up |
| `BR-EDGE` | `FastEthernet0/0` | `10.255.0.6` | up | up |
| `BR-EDGE` | `FastEthernet1/0` | unassigned | up | up |
| `BR-EDGE` | `FastEthernet1/0.40` | `10.30.40.1` | up | up |
| `BR-EDGE` | `FastEthernet1/0.50` | `10.30.50.1` | up | up |
| `BR-EDGE` | `Loopback0` | `3.3.3.3` | up | up |

`HQ-DIST Fa2/0` being administratively down is the **expected** state — it is the documented reserved growth
port, not a fault.

### 1.2 802.1Q subinterface encapsulation

```
show vlans
show interfaces FastEthernet1/0.10 | include Encapsulation|line protocol
```

On `HQ-DIST` expect `show vlans` to list Virtual LAN IDs 10, 20 and 99, each with its own IP address and
non-zero received/transmitted packet counters once PC1/PC2/AUTO-SRV are up. Zero received packets on a VLAN
means the GNS3 switch port for that VLAN is misconfigured (check the port matrix in §4 of `TOPOLOGY.md`).
`show interfaces` must report `Encapsulation 802.1Q Virtual LAN, Vlan ID 10.`

Repeat on `DC-EDGE` (VLAN 30) and `BR-EDGE` (VLANs 40, 50).

### 1.3 Directly connected neighbour reachability

| Where | Command | Expected |
|-------|---------|----------|
| `HQ-CORE` | `ping 10.255.0.2` | `!!!!!` — success rate is 100 percent (5/5) |
| `HQ-CORE` | `ping 10.255.0.10` | `!!!!!` |
| `DC-EDGE` | `ping 10.255.0.6` | `!!!!!` |
| `HQ-DIST` | `ping 10.255.0.9` | `!!!!!` |
| `BR-EDGE` | `ping 10.255.0.5` | `!!!!!` |

A first-packet `.!!!!` (4/5) is normal ARP behaviour, not a failure. Repeat the ping to confirm 5/5.

---

## 2. OSPF

### 2.1 Neighbour table **[EVIDENCE]**

```
show ip ospf neighbor
```

All adjacencies must be `FULL`. The interfaces are broadcast-type Ethernet, so the state shows
`FULL/DR` or `FULL/BDR` (the higher router ID wins the DR election on each segment).

| Run on | Neighbour ID | Interface | Expected state |
|--------|--------------|-----------|----------------|
| `HQ-CORE` | `2.2.2.2` | `Fa1/0` | `FULL/DR` |
| `HQ-CORE` | `1.1.1.4` | `Fa2/0` | `FULL/DR` |
| `HQ-DIST` | `1.1.1.1` | `Fa0/0` | `FULL/BDR` |
| `DC-EDGE` | `1.1.1.1` | `Fa0/0` | `FULL/BDR` |
| `DC-EDGE` | `3.3.3.3` | `Fa1/0` | `FULL/DR` |
| `BR-EDGE` | `2.2.2.2` | `Fa0/0` | `FULL/BDR` |

Note on DR/BDR: the interfaces are broadcast-type, and with equal OSPF priorities the router with the
numerically **highest router ID** on a segment wins — so `2.2.2.2` is DR on `10.255.0.0/30`, `1.1.1.4` is DR
on `10.255.0.8/30` and `3.3.3.3` is DR on `10.255.0.4/30`. DR election is non-preemptive, so if the routers
were started at very different times the DR/BDR roles may be reversed. **The DR/BDR split is therefore not a
pass criterion — `FULL` is.** Any neighbour stuck in `INIT`, `2WAY`, `EXSTART` or `EXCHANGE` is a failure;
see §8.1.

Expected count: 3 adjacencies total across the topology (one per WAN /30).

### 2.2 Interface and area roles

```
show ip ospf interface brief
show ip ospf | include Router ID|area|It is an
```

| Run on | Expected |
|--------|----------|
| `HQ-CORE` | Router ID `1.1.1.1`; `Fa1/0`, `Fa2/0`, `Lo0` all in area 0; "It is an autonomous system boundary router" (because of `default-information originate`) |
| `HQ-DIST` | Router ID `1.1.1.4`; `Fa0/0` area 0; `Fa1/0.10/.20/.99` and `Lo0` area 10; "It is an area border router" |
| `DC-EDGE` | Router ID `2.2.2.2`; `Fa0/0`, `Fa1/0`, `Lo0` area 0; `Fa2/0.30` area 20; "It is an area border router" |
| `BR-EDGE` | Router ID `3.3.3.3`; `Fa0/0` area 0; `Fa1/0.40/.50` and `Lo0` area 30; "It is an area border router" |

### 2.3 Passive interfaces are correct

```
show ip ospf interface | include line protocol|Passive
show ip protocols | begin Passive
```

Expected: every LAN subinterface and `Loopback0` is listed as **passive**; the WAN FastEthernet interfaces
are **not** passive. If a LAN subinterface is active, OSPF hellos are leaking onto a user VLAN.

### 2.4 Routing table **[EVIDENCE]**

```
show ip route ospf
```

Expected prefix set on **`BR-EDGE`** (the most distant device — proves end-to-end LSDB propagation). Every
next hop is `10.255.0.5` (`DC-EDGE Fa1/0`) via `FastEthernet0/0`:

| Prefix | Type | Metric | Notes |
|--------|------|--------|-------|
| `1.1.1.1/32` | `O` | `[110/2]` | HQ-CORE loopback — **intra-area**, area 0 |
| `1.1.1.4/32` | `O IA` | `[110/3]` | HQ-DIST loopback — advertised into area 0 from area 10 |
| `2.2.2.2/32` | `O` | `[110/1]` | DC-EDGE loopback, intra-area 0 |
| `10.10.10.0/24` | `O IA` | `[110/4]` | HQ users |
| `10.10.20.0/24` | `O IA` | `[110/4]` | HQ corporate |
| `10.10.99.0/24` | `O IA` | `[110/4]` | HQ management |
| `10.20.30.0/24` | `O IA` | `[110/2]` | DC servers |
| `10.255.0.0/30` | `O` | `[110/2]` | HQ-CORE ↔ DC-EDGE |
| `10.255.0.8/30` | `O` | `[110/3]` | HQ-CORE ↔ HQ-DIST |
| `0.0.0.0/0` | `O*E2` | `[110/1]` | default injected by `HQ-CORE` |

The metric column is worth checking rather than skimming. Because every link is FastEthernet, each transit
hop costs exactly 1 (`10^8 / 10^8`), so the metric equals the number of hops traversed — `[110/1]` to the
adjacent router's loopback, `[110/4]` to the HQ user VLAN three routers away. Any other value means an
interface bandwidth or cost was changed by hand. The external default keeps `[110/1]` because E2 metrics are
not accumulated across the OSPF domain.

Note that `1.1.1.1/32` is `O` and not `O IA`: `HQ-CORE` places its loopback in area 0, and `BR-EDGE`
participates in area 0 on its WAN link, so the route is intra-area. `1.1.1.4/32` is `O IA` because
`HQ-DIST` places its loopback in area 10. Getting these two the wrong way round is the classic misreading of
a multi-area table.

On `HQ-DIST` the equivalent check is that `10.20.30.0/24`, `10.30.40.0/24` and `10.30.50.0/24` all appear as
`O IA` via `10.255.0.9`.

```
show ip route 0.0.0.0
```
must return `Known via "ospf 1", distance 110, metric 1, candidate default path, type extern 2` on
`HQ-DIST`, `DC-EDGE` and `BR-EDGE`.

### 2.5 Database sanity

```
show ip ospf database summary | include Link ID|Summary
show ip ospf border-routers
```

Expected: type-3 summary LSAs exist for the remote site prefixes (proof that areas are being summarised
across ABRs rather than flooded as type-1/2), and `show ip ospf border-routers` on `BR-EDGE` lists
`1.1.1.4` and `2.2.2.2` as ABRs plus `1.1.1.1` as an ASBR.

---

## 3. DHCP

### 3.1 Pool state

```
show ip dhcp pool
show ip dhcp binding
show ip dhcp conflict
```

| Run on | Expected pools | Expected leased addresses |
|--------|----------------|---------------------------|
| `HQ-DIST` | `VLAN10_HQ_USERS`, `VLAN20_HQ_CORP`, `VLAN99_HQ_MGMT` | `10.10.10.21` (PC1), `10.10.20.21` (PC2); VLAN 99 pool has 0 leases because `AUTO-SRV` is statically addressed |
| `DC-EDGE` | `VLAN30_DC_SERVERS` | 0 leases — all three DC containers are statically addressed |
| `BR-EDGE` | `VLAN40_BR_USERS`, `VLAN50_BR_GUEST` | `10.30.40.21` (PC3), `10.30.50.21` (PC4) |

`show ip dhcp pool` must show `Current index` inside the pool range and `Leased addresses` matching the
count above. `show ip dhcp conflict` must be **empty** — any entry means a static address overlaps a pool
(check the `ip dhcp excluded-address 10.x.x.1 10.x.x.20` statements).

Leases start at `.21` because `.1`–`.20` are excluded on every subnet.

### 3.2 Client-side confirmation **[EVIDENCE]**

On each VPCS host (`PC1`–`PC4`):

```
ip dhcp -r
show ip
```

Expected `show ip` output, e.g. for `PC1`:

```
NAME        : PC1[1]
IP/MASK     : 10.10.10.21/24
GATEWAY     : 10.10.10.1
DNS         : 10.20.30.10
DHCP SERVER : 10.10.10.1
DOMAIN NAME : corp.local
```

| Host | Expected IP | Gateway | DNS | Domain |
|------|-------------|---------|-----|--------|
| `PC1` | `10.10.10.21/24` | `10.10.10.1` | `10.20.30.10` | `corp.local` |
| `PC2` | `10.10.20.21/24` | `10.10.20.1` | `10.20.30.10` | `corp.local` |
| `PC3` | `10.30.40.21/24` | `10.30.40.1` | `10.20.30.10` | `corp.local` |
| `PC4` | `10.30.50.21/24` | `10.30.50.1` | `10.20.30.10` | `guest.corp.local` |

`PC4` receiving `guest.corp.local` and a shorter lease is the proof that it was served by the dedicated
guest pool rather than the corporate pool.

---

## 4. End-to-end reachability (should succeed)

### 4.1 From `PC1` (HQ user, VLAN 10) **[EVIDENCE]**

```
ping 10.10.10.1
ping 10.10.20.1
ping 10.255.0.9
ping 1.1.1.1
ping 10.20.30.10
ping 10.30.40.1
trace 10.30.40.1
```

Expected: all pings reply. VPCS prints e.g. `84 bytes from 10.20.30.10 icmp_seq=1 ttl=61 time=15.3 ms`.
`trace 10.30.40.1` must show four hops — three transit routers, then the destination gateway. Each router
reports the address of the interface the probe **arrived on**:

```
1  10.10.10.1    ...      (HQ-DIST, Fa1/0.10)
2  10.255.0.9    ...      (HQ-CORE, Fa2/0)
3  10.255.0.2    ...      (DC-EDGE, Fa0/0)
4  *10.30.40.1   ...      (BR-EDGE, destination)
```

This traceroute is the evidence that the WAN transits the Data Centre as designed rather than taking some
unintended path.

### 4.2 From `PC3` (Branch user, VLAN 40)

```
ping 10.30.40.1
ping 10.20.30.10
ping 10.20.30.11
ping 10.20.30.12
ping 10.10.20.1
```

Expected: all succeed. Branch corporate users have full access to Data Centre services and HQ.

### 4.3 From `AUTO-SRV` (management, VLAN 99)

```
ip route
ping -c 4 10.10.99.1
ping -c 4 10.20.30.10
ping -c 4 1.1.1.1
ping -c 4 3.3.3.3
```

Expected: `ip route` shows `default via 10.10.99.1 dev eth0`; all four pings return `0% packet loss`.
Reaching `3.3.3.3` from the management VLAN proves the loopbacks are advertised across all areas, which is
what Part B's Ansible inventory will target.

### 4.4 Router-sourced reachability

| Where | Command | Expected |
|-------|---------|----------|
| `HQ-CORE` | `ping 3.3.3.3 source Loopback0` | 5/5 success |
| `BR-EDGE` | `ping 10.20.30.12 source Loopback0` | 5/5 success — confirms the syslog source address is routable |
| `HQ-DIST` | `ping 10.20.30.11 source Loopback0` | 5/5 success — confirms NTP reachability |

---

## 5. Security enforcement (must FAIL where stated)

A "pass" in this section means the traffic is **blocked**. Clear the counters first so the hit counts are
attributable to the test.

### 5.1 Guest isolation from `PC4` (VLAN 50) **[EVIDENCE]**

Prepare on `BR-EDGE`:

```
clear ip access-list counters ACL_GUEST_IN
```

From `PC4`:

| Command | Expected result | Why |
|---------|-----------------|-----|
| `ping 10.30.50.1` | **succeeds** | explicit `permit icmp 10.30.50.0/24 host 10.30.50.1` — guest must reach its gateway |
| `ping 10.20.30.10` | **fails** — `*10.30.50.1 icmp_seq=1 ttl=255 time=… (ICMP type:3, code:13, Communication administratively prohibited)` | `deny ip 10.30.50.0/24 10.20.0.0/16 log` |
| `ping 10.10.99.10` | **fails**, same administratively-prohibited response | `deny ip 10.30.50.0/24 10.10.0.0/16 log` |
| `ping 10.10.20.1` | **fails** | same deny |
| `ping 10.30.40.1` | **fails** | `deny ip 10.30.50.0/24 10.30.40.0/24 log` — guest cannot reach the branch corporate VLAN |
| `ping 10.255.0.5` | **fails** | `deny ip 10.30.50.0/24 10.255.0.0/16 log` — guest cannot probe WAN transit addresses |
| `ping 8.8.8.8` | **succeeds** (once NAT is verified in §6) | final `permit ip 10.30.50.0/24 any` — guests get Internet only |

Then on `BR-EDGE`:

```
show ip access-lists ACL_GUEST_IN
show logging | include ACL_GUEST_IN|list ACL_GUEST_IN denied
```

Expected: non-zero `(N matches)` counters against the specific `deny` entries that were exercised, and
corresponding `%SEC-6-IPACCESSLOGDP` messages in the log (also visible on the syslog collector, §7.3). Zero
matches on a deny entry that should have been hit means the ACL is not applied to `Fa1/0.50` — confirm with
`show ip interface FastEthernet1/0.50 | include access list`.

### 5.2 Second enforcement point on `DC-EDGE`

```
clear ip access-list counters ACL_WAN_BR_IN
```

Temporarily remove the branch ACL to prove the Data Centre defends itself independently:

```
BR-EDGE(config)# interface FastEthernet1/0.50
BR-EDGE(config-subif)# no ip access-group ACL_GUEST_IN in
```

From `PC4`: `ping 10.20.30.10` must **still fail**, and on `DC-EDGE`
`show ip access-lists ACL_WAN_BR_IN` must show matches on
`deny ip 10.30.50.0 0.0.0.255 10.20.30.0 0.0.0.255`. **Restore the branch ACL immediately afterwards:**

```
BR-EDGE(config-subif)# ip access-group ACL_GUEST_IN in
```

### 5.3 HQ user-to-management isolation

From `PC1` (VLAN 10):

| Command | Expected |
|---------|----------|
| `ping 10.10.99.10` | **fails** — administratively prohibited (`ACL_HQ_USERS_IN` denies VLAN 10 → VLAN 99) |
| `ping 10.10.99.1` | **fails** — the gateway address is inside the denied destination range |
| `ping 10.20.30.10` | **succeeds** — users are not cut off from Data Centre services |

Confirm with `show ip access-lists ACL_HQ_USERS_IN` on `HQ-DIST`.

### 5.4 VTY access control **[EVIDENCE]**

| From | Command | Expected |
|------|---------|----------|
| `AUTO-SRV` (`10.10.99.10`) | `ssh -o StrictHostKeyChecking=no admin@10.255.0.9` | login banner, then `HQ-CORE>` / `HQ-CORE#` prompt — **permitted** |
| `AUTO-SRV` | `ssh admin@3.3.3.3` | permitted |
| `PC2` / any VLAN 20 host | attempt SSH to `10.255.0.9` | **refused/timeout** — `ACL_VTY` has no entry for `10.10.20.0/24` |
| any router | `telnet 10.255.0.1` | **refused** — `transport input ssh` permits SSH only |

On the target router, verify the denial was logged and counted:

```
show ip access-lists ACL_VTY
show logging | include ACL_VTY
show users
```

Expected: `deny ip any any log` shows matches after the VLAN 20 attempt; `show users` lists only the
permitted session, with its source address.

### 5.5 Edge anti-spoofing

On `HQ-CORE`:

```
show ip access-lists ACL_INTERNET_IN
show ip interface FastEthernet0/0 | include access list
```

Expected: `Inbound  access list is ACL_INTERNET_IN`, and the `deny ip 10.0.0.0 0.255.255.255 any log` entry
present as the first rule. Match counters will typically be zero in a lab with no hostile traffic — the
control is verified by *presence and placement*, which is the correct expectation to state rather than
fabricating hits.

### 5.6 Management-plane hardening spot checks

| Where | Command | Expected |
|-------|---------|----------|
| each router | `show ip ssh` | `SSH Enabled - version 2.0`, `Authentication timeout: 60 secs; Authentication retries: 2` |
| each router | `show running-config \| include ^no ip http\|^no service pad` | `no ip http server`, `no ip http secure-server`, `no service pad` |
| each router | `show line` | `aux 0` present with no active session; VTY lines 0–15 configured |
| each router | `show archive log config all` | the configuration-change audit log, with secrets shown as `<removed>` (effect of `hidekeys`) |

---

## 6. NAT / Internet access

### 6.1 Outside interface has a lease

On `HQ-CORE`:

```
show dhcp lease
show ip interface brief FastEthernet0/0
show ip route 0.0.0.0
```

Expected: a bound lease from the GNS3 NAT cloud (`192.168.122.0/24` by default) with
`Temp default-gateway addr: 192.168.122.1`, `Fa0/0` showing that address as `YES DHCP up up`, and a default
route present. If `Fa0/0` has no address, the NAT cloud is not attached or the GNS3 VM has no upstream —
nothing in §6 will pass until this is fixed.

> If your GNS3 installation's NAT cloud uses a network inside `10.0.0.0/8` rather than the default
> `192.168.122.0/24`, the first entry of `ACL_INTERNET_IN`
> (`deny ip 10.0.0.0 0.255.255.255 any log`) will drop the DHCP offer and all return traffic, because the
> anti-spoofing rule assumes internal addresses never legitimately arrive from outside. In that case narrow
> the rule to the three site blocks (`deny ip 10.10.0.0 0.0.255.255 any log` and equivalents for
> `10.20.0.0/16`, `10.30.0.0/16`) instead of removing it.

### 6.2 Translation table **[EVIDENCE]**

On `HQ-CORE`:

```
clear ip nat translation *
clear ip nat statistics
```

From `PC1`, then `PC3`, then `PC4`:

```
ping 8.8.8.8
```

Back on `HQ-CORE`:

```
show ip nat translations
show ip nat statistics
```

Expected `show ip nat translations` — one ICMP entry per source, all sharing the single outside address
(this is what proves **overload/PAT** rather than one-to-one NAT):

```
Pro Inside global         Inside local          Outside local         Outside global
icmp 192.168.122.50:1     10.10.10.21:1         8.8.8.8:1             8.8.8.8:1
icmp 192.168.122.50:2     10.30.40.21:2         8.8.8.8:2             8.8.8.8:2
icmp 192.168.122.50:3     10.30.50.21:3         8.8.8.8:3             8.8.8.8:3
```

Expected `show ip nat statistics`:

```
Total active translations: 3 (0 static, 3 dynamic; 3 extended)
Outside interfaces: FastEthernet0/0
Inside interfaces: FastEthernet1/0, FastEthernet2/0
Hits: <non-zero>  Misses: <low>
Dynamic mappings:
-- Inside Source
[Id: 1] access-list ACL_NAT_INSIDE interface FastEthernet0/0 refcount 3
```

The `Inside interfaces` line listing **both** WAN interfaces is the check that `ip nat inside` was not
forgotten on one of them — the single most common cause of "one site has Internet, the other does not".

### 6.3 NAT scope

```
show ip access-lists ACL_NAT_INSIDE
```

Expected three `permit` entries (`10.10.0.0/16`, `10.20.0.0/16`, `10.30.0.0/16`) with match counters
incrementing, and **no** entry for `10.255.0.0/24` — WAN transit addresses are deliberately not translated.

---

## 7. Infrastructure services

### 7.1 DNS

On the `DNS` container:

```
ps aux | grep dnsmasq
ss -lunp | grep :53
```

From a router:

```
HQ-CORE# ping auto.corp.local
```

Expected: `Translating "auto.corp.local"...domain server (10.20.30.10) [OK]` followed by
`Sending 5, 100-byte ICMP Echos to 10.10.99.10`. Note that `no ip domain-lookup` is configured, so name
resolution from the CLI works because `ip name-server` is set explicitly; if resolution is required
interactively, add `ip domain-lookup` temporarily.

From `PC1`: `ping auto.corp.local` — VPCS resolves via the DHCP-supplied server `10.20.30.10`. Not every
VPCS build includes a resolver; if the name is not resolved, run the equivalent test from `AUTO-SRV`
(`nslookup auto.corp.local 10.20.30.10`) instead and note which host produced the evidence.

Guest name resolution is the important asymmetry to demonstrate. From `PC4`, `nslookup dns.corp.local
10.20.30.10` (or `ping dns.corp.local`) **succeeds** because `ACL_GUEST_IN` explicitly permits UDP and TCP
port 53 toward `10.20.30.10`, while `ping 10.20.30.10` from the same host **fails**. That pair of results is
the evidence that guest isolation is selective — the guest network is restricted, not broken.

### 7.2 NTP **[EVIDENCE]**

On the `NTP` container:

```
chronyc tracking
chronyc clients
```

On each router:

```
show ntp status
show ntp associations
show clock detail
```

Expected `show ntp status`:

```
Clock is synchronized, stratum 11, reference is 10.20.30.11
nominal freq is 250.0000 Hz, actual freq is 250.0000 Hz, precision is 2**18
reference time is ...
clock offset is ... msec, root delay is ... msec
```

Expected `show ntp associations`: the line for `10.20.30.11` prefixed with `*~` (system peer, configured
with `prefer`), `st` = 10, non-zero `poll` and `reach` = 377 once fully polled. Expected `show clock detail`:
the time is **not** prefixed with `*` (a leading `*` means the clock is unauthoritative) and the timezone
shows `AEST`.

Synchronisation can take up to ~10 minutes after boot on emulated hardware. `stratum 11` on the routers is
correct: the `chrony` server is a `local stratum 10` source, so its clients are stratum 11.

### 7.3 Syslog **[EVIDENCE]**

On each router, generate a deterministic event:

```
HQ-CORE# configure terminal
HQ-CORE(config)# interface Loopback99
HQ-CORE(config-if)# description SYSLOG-TEST
HQ-CORE(config-if)# exit
HQ-CORE(config)# no interface Loopback99
HQ-CORE(config)# end
```

On the `SYSLOG` container:

```
tail -n 50 /var/log/syslog
grep -E "HQ-CORE|HQ-DIST|DC-EDGE|BR-EDGE" /var/log/syslog | tail -20
grep "SEC-6-IPACCESSLOGDP" /var/log/syslog | tail
```

Expected: entries from all four routers. Because `logging source-interface Loopback0` is configured, the
source address of each message is the router's loopback (`1.1.1.1`, `1.1.1.4`, `2.2.2.2`, `3.3.3.3`), giving
stable per-device attribution, e.g.:

```
Sep 12 14:22:07 1.1.1.1 1234: HQ-CORE: *Sep 12 14:22:06.998 AEST: %LINEPROTO-5-UPDOWN: Line protocol on Interface Loopback99, changed state to up
```

The `%SEC-6-IPACCESSLOGDP` grep must return the guest-isolation denials generated in §5.1 — this closes the
loop between the ACL test and the centralised logging requirement.

Also verify locally: `show logging` on each router must report `Trap logging: level informational` and a
non-zero `message lines logged` count to host `10.20.30.12`.

---

## 8. Troubleshooting quick reference

### 8.1 OSPF neighbour not reaching FULL

| Symptom | Likely cause | Check |
|---------|--------------|-------|
| No neighbour at all | link down, or interface is passive | `show ip ospf interface brief`, `show ip protocols` — is the WAN interface in the passive list by mistake? |
| Stuck in `INIT` | one side's hellos are being dropped | `show ip access-lists ACL_WAN_BR_IN` — is `permit ospf any any` present and matching? |
| Stuck in `EXSTART`/`EXCHANGE` | MTU mismatch | `show interfaces \| include MTU` — must be 1500 both ends |
| Stuck in `2WAY` on a /30 | expected only with >2 routers; on a /30 it indicates an area or subnet mask mismatch | `show ip ospf interface FastEthernet0/0 \| include Area\|Network Type\|Hello` |
| Flapping | duplicate router ID | `show ip ospf \| include Router ID` on both ends |

### 8.2 VPCS host gets no address

Check in this order: `show ip dhcp pool` on the local router (is the pool defined for the right subnet?),
`show vlans` on the router (are packets arriving on that VLAN ID?), then the GNS3 switch port matrix
(`TOPOLOGY.md` §4) — an access port left on VLAN 1 is the usual cause.

### 8.3 A permitted flow is being blocked

```
show ip access-lists
show ip interface <interface> | include access list
debug ip packet detail <acl>
```

Check entry **order** first: within `ACL_GUEST_IN` the DHCP and DNS permits must appear above the deny
rules, and `ACL_HQ_USERS_IN` must permit DHCP before its deny entries. Turn `debug` off with
`undebug all` immediately — packet debugging on emulated hardware can saturate the console.

### 8.4 SSH refused everywhere

Almost always the missing post-boot RSA key. `show ip ssh` reporting `SSH Disabled` confirms it; follow the
"Post-boot SSH enablement" steps in the README.

---

## 9. Sign-off checklist

| # | Requirement | Section | Pass |
|---|-------------|---------|------|
| 1 | All interfaces up with the designed addresses | §1.1 | ☐ |
| 2 | 802.1Q subinterfaces passing tagged traffic | §1.2 | ☐ |
| 3 | 3 OSPF adjacencies, all `FULL` | §2.1 | ☐ |
| 4 | Correct ABR/ASBR roles, multi-area LSDB | §2.2, §2.5 | ☐ |
| 5 | OSPF passive on all LAN segments | §2.3 | ☐ |
| 6 | Full inter-area routing table incl. default | §2.4 | ☐ |
| 7 | DHCP leases on PC1–PC4 with correct options | §3 | ☐ |
| 8 | End-to-end reachability HQ ↔ DC ↔ Branch | §4 | ☐ |
| 9 | Guest VLAN isolated, DNS still permitted | §5.1, §7.1 | ☐ |
| 10 | Guest isolation enforced at two points | §5.2 | ☐ |
| 11 | HQ users isolated from management VLAN | §5.3 | ☐ |
| 12 | SSH permitted only from mgmt/DC subnets; Telnet refused | §5.4 | ☐ |
| 13 | Anti-spoofing filter applied on the NAT edge | §5.5 | ☐ |
| 14 | PAT translating all three sites via one address | §6.2 | ☐ |
| 15 | WAN transit excluded from NAT | §6.3 | ☐ |
| 16 | DNS resolving `corp.local` for routers and hosts | §7.1 | ☐ |
| 17 | All routers NTP-synchronised, stratum 11, AEST | §7.2 | ☐ |
| 18 | Syslog receiving from all four loopback sources | §7.3 | ☐ |
