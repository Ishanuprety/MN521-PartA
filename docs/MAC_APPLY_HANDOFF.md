# Handoff to the Mac / GNS3 agent — READY_FOR_MAC_APPLY

**Status: repository work complete. All configuration fixes are on
`cursor/full-config-pack-marks` (PR #2) and pass both gates.**

```bash
python3 scripts/validate_configs.py     # 5 configs, 0 fail, 0 warn
python3 scripts/check_consistency.py    # 68 assertions, 0 mismatch
```

Run both before applying. They are fast and they catch the class of defect that
otherwise only shows up as a lab that behaves oddly.

Division of work: the cloud agent owns the repository (configs, docs, report); the Mac
agent owns the live GNS3 project (apply, rewire, capture evidence). This document is
the interface between the two.

---

## 1. Confirmation of the four items you are applying

All four are already correct in the repository — verified, not assumed.

| # | Your item | Repo state | Where |
|---|-----------|-----------|-------|
| 1 | `SW-DMZ-1 Eth0` trunk → native VLAN **1** | `{"port_number": 0, "type": "dot1q", "vlan": 1}` | [`configs/switches/ports_mapping.json`](../configs/switches/ports_mapping.json) |
| 2 | Delete the L2 loop cross-links | Exact ports listed in §3 below | [`TOPOLOGY.md`](TOPOLOGY.md) §3.6 |
| 3 | Re-upload and start the five routers | All five rewritten and validated | [`configs/`](../configs/) |
| 4 | Keep `PC5`/`PC8` at HQ per the live map | Documented everywhere; decision now recorded | [`REVIEW_FINDINGS.md`](REVIEW_FINDINGS.md) R-17 |

On item 4 — thanks for confirming. R-17 is now closed as *keep at HQ as wired*, so no
recabling and no config change: `PC5` takes a VLAN 10 lease and `PC8` a VLAN 20 lease
from `HQ-DIST` automatically. Every document already stated this distribution, so
nothing needed editing beyond recording the decision.

One extra item you did not list, which came out of the same review and is worth
applying in the same pass:

| # | Item | Why |
|---|------|-----|
| 5 | `SW-DC-2` ports `Eth1`–`Eth3` → `access` VLAN **30** | The switch previously had no host ports at all. Provisioning them gives the `VLAN30_DC_SERVERS` DHCP pool its only possible client, so "zero leases" becomes a *designed* steady state rather than a pool with nowhere to go |

It is already in `ports_mapping.json`, so `scripts/apply_on_mac.py` applies it with the
rest of the switch matrix.

---

## 2. Router configurations — apply all five in ONE pass

```bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
cd /path/to/MN521-PartA
git checkout cursor/full-config-pack-marks && git pull
python3 scripts/validate_configs.py && python3 scripts/check_consistency.py
python3 scripts/apply_on_mac.py
```

### Why it has to be one pass, not device by device

Two changes are estate-wide, and applying them partially leaves the lab in a worse
state than before:

1. **`HQ-CORE Fa0/0` is no longer a NAT/DHCP interface.** It is now a routed
   `10.255.0.18/30` to `FW-EDGE`. A router still holding the previous revision requests
   DHCP from a device that runs no DHCP server on that link, so the interface never
   binds and `HQ-CORE` is partitioned from the Internet edge — while its other four
   adjacencies still look perfectly healthy. That is the most misleading failure state
   available here, so please confirm after applying:

   ```
   HQ-CORE# show running-config interface FastEthernet0/0
   ```

   Must show `10.255.0.18` and contain **no** `ip nat` command.

2. **OSPF area 0 now uses MD5 authentication.** Keys must match on both ends of every
   backbone link, so a partial apply drops those adjacencies until the rest catch up.
   Expect a brief reconvergence when the last router lands. There are **10 keyed
   interfaces** across the five configs, which is 5 adjacencies × 2 ends:
   `FW-EDGE` 1, `HQ-CORE` 4, `HQ-DIST` 1, `DC-EDGE` 2, `BR-EDGE` 2.

   Verify both ends of any link that does not come back:

   ```
   show ip ospf interface FastEthernet<n> | include authentication
   ```

   Rollback if it blocks you (per router — tell me and I will remove it from the repo
   rather than leaving the lab and the repo divergent):

   ```
   configure terminal
   router ospf 1
    no area 0 authentication message-digest
   end
   ```

### Boot order

`FW-EDGE` → `HQ-CORE` → `DC-EDGE` → `HQ-DIST` → `BR-EDGE`, **one at a time**, waiting
for each prompt. Five simultaneous Dynamips boots will saturate a 4 GB GNS3 VM.

### Post-boot: RSA host keys, once per router

```
enable
configure terminal
crypto key generate rsa modulus 2048 label SSH-KEY
end
write memory
```

`crypto key generate rsa` is exec-mode and cannot live in a startup config, so **this
is not restored by re-applying a config** — it has to be redone after this apply pass.
Until it runs, `show ip ssh` reports `SSH Disabled` and every SSH attempt fails
regardless of the ACLs. That is the first thing to check if §6.6 of the verification
plan fails.

### Two things that will bite an automation script

| Property | Consequence |
|----------|-------------|
| `login local` on `line console 0` | The console prompts for `Username:` on a fresh boot. A script expecting `Router>` will hang. `admin` / `Cisco123!` |
| `ACL_VTY` permits only `10.10.99.10`, `10.10.99.11` and `10.20.30.0/24` | **SSH from the Mac or the GNS3 host is denied.** Drive the devices over the GNS3 console port, not over VTY. This is the intended control, not a fault |

---

## 3. Links to delete — exact ports

| Delete | Loop it closes | After deletion, that switch still reaches its router via |
|--------|----------------|----------------------------------------------------------|
| `SW-HQ-1 Eth7` ↔ `SW-HQ-2 Eth0` | `SW-HQ-1` – `SW-HQ-2` – `SW-HQ-DIST` – `SW-HQ-1` | `SW-HQ-2 Eth2` → `SW-HQ-DIST Eth2` |
| `SW-DC-1 Eth7` ↔ `SW-DC-2 Eth0` | `SW-DC-1` – `SW-DC-2` – `SW-DC-CORE` – `SW-DC-1` | `SW-DC-2 Eth6` → `SW-DC-CORE Eth2` |
| `SW-BR-1 Eth7` ↔ `SW-BR-2 Eth0` | `SW-BR-1` – `SW-BR-2` – `SW-BR-DIST` – `SW-BR-1` | `SW-BR-2 Eth6` → `SW-BR-DIST Eth2` |

**Nothing is disconnected.** Each switch keeps its aggregation uplink.

### Do NOT also touch these three

| Link | Leave exactly as-is |
|------|---------------------|
| `HQ-DIST Fa1/0` ↔ `SW-HQ-1 Eth0` | Cabled, router port `shutdown` |
| `DC-EDGE Fa2/0` ↔ `SW-DC-1 Eth0` | Cabled, router port `shutdown` |
| `BR-EDGE Fa1/0` ↔ `SW-BR-1 Eth0` | Cabled, router port `shutdown` |

These are pre-cabled standby recovery paths and they address a **different** loop —
each router's two attachments to the same access switch. Deleting them loses the
recovery path; issuing `no shutdown` on them creates that second loop. The configs hold
them down deliberately with a `CABLED_..._HELD_DOWN_NO_STP` description, so an
inadvertent `no shutdown` is at least self-documenting.

### Expected result

44 forwarding links + 3 held-down standby = **47**, from 50 as currently wired.
`scripts/apply_on_mac.py` writes a fresh `LINK_MAP_LIVE.md`; diff it against
[`TOPOLOGY.md`](TOPOLOGY.md) §3 to confirm.

---

## 4. Evidence capture

[`../verification/CHECKS.md`](../verification/CHECKS.md) is the plan: 12 sections,
~60 checks, each with the device, the exact command and a pass criterion written
*before* the test. Nothing in it asserts a measured result — every result cell is blank
and every derived value is labelled *expected by design*.

**Save screenshots as `report/figures/SS-nn-<slug>.png`** using the names in `CHECKS.md`
§12. The report and the plan both reference those names, so correct naming at capture
time means no renaming later. 41 slots.

Run in dependency order — an OSPF fault invalidates every later reachability result, and
a DHCP fault invalidates every host test.

### The seven captures that carry the most weight

Each proves something the design claims and could plausibly have got wrong:

| Slot | Proves |
|------|--------|
| `SS-07` | 5 OSPF adjacencies FULL — the whole routing design rests on it |
| `SS-12` | `BR-EDGE` reaches HQ via `DC-EDGE`, **not** the cost-50 backup. Confirms the cost engineering, and therefore that the `DC-EDGE` policy chokepoint is actually in the path |
| `SS-22` + `SS-25` | Guest blocked from five destinations, **and** still able to resolve names. The pair is the proof — a failing ping alone is indistinguishable from a broken network |
| `SS-23` | Guest containment holding during WAN failover, with deny counters on `HQ-CORE Fa3/0`. This is the R-05 regression test |
| `SS-31` | Several sources sharing one inside global address — proves PAT, not one-to-one NAT |
| `SS-32` | Inbound HTTP reaching `WEB-SRV` through the static translation. **This path was completely non-functional before the fix (R-03)**, so it is the single highest-value capture in the set |
| `SS-37` + `SS-38` | Five per-device log files with wall-clock timestamps, containing the ACL denials generated in §6.1. Closes the loop between two separate requirements |

### Results that are correct but look like failures

Please do not "fix" these — each is asserted as the expected outcome:

- `HQ-DIST Fa1/0`, `DC-EDGE Fa2/0`, `BR-EDGE Fa1/0` **administratively down**.
- `DC-EDGE` `VLAN30_DC_SERVERS` pool showing **zero leases** — all five DC servers are
  static; the pool serves the new `SW-DC-2` staging ports.
- **Inbound ping to the public address fails.** `ACL_OUTSIDE_IN` permits no inbound
  `echo`. TCP 80 and 8080 work; ICMP does not, by design.
- Routers report **stratum 11**, not 10 — `NTP` is a `local stratum 10` source, so
  clients sit one level below.
- `ACL_OUTSIDE_IN` anti-spoofing counters will be **zero** in a lab with no hostile
  traffic. That control is verified by presence and placement, not by hit count.
- NTP can take **~10 minutes** after boot to synchronise on emulated hardware.
- `PC4`/`PC9` receive domain `guest.corp.local` and `PC-DMZ` receives `dmz.corp.local`
  — different from `corp.local` on purpose; that is the scope-separation evidence.

---

## 5. Please report back

So I can close out §6 of the report and the sign-off matrix:

1. **Confirmation of the two blockers**: `HQ-CORE Fa0/0` clean of NAT, and the three
   cross-links deleted.
2. **Any check that fails**, with the command output. I would rather fix a real defect
   in the repo than have the report claim something the lab does not do.
3. **Anything that surprised you** — a working config that needed a manual nudge is a
   repo defect I should encode, not a one-off.
4. **`LINK_MAP_LIVE.md`** from the apply run, so I can diff it against `TOPOLOGY.md`
   §3 and confirm 47 links.

Once the screenshots are in `report/figures/`, I will fill in `CHECKS.md`, remove the
"pending execution" banner from §6 of the report, complete the sign-off matrix, and the
package is submission-ready via [`../report/BUILD_DOCX.md`](../report/BUILD_DOCX.md).

---

## 6. Complete fix list

Every fix is recorded as `R-01`–`R-20` in
[`REVIEW_FINDINGS.md`](REVIEW_FINDINGS.md), each with the severity, the evidence it was
derived from, and what changed. Summary of the ones that alter live behaviour:

| R | Severity | Fix | Visible effect once applied |
|---|----------|-----|-----------------------------|
| R-01 | High | `HQ-CORE Fa0/0` is a routed /30, NAT removed | `HQ-CORE`–`FW-EDGE` adjacency forms |
| R-02 | Critical | Three loop cross-links to delete | No broadcast storm; project stays responsive |
| R-03 | Critical | Static PAT for `WEB-SRV:80` and `APP-SRV:8080`; edge ACL matches the pre-NAT destination | Inbound DMZ services reachable for the first time |
| R-04 | High | `default-information originate` removed from `HQ-CORE` | Exactly one `O*E2` default, from `4.4.4.4` |
| R-05 | Critical | `ACL_WAN_BR_IN` on `HQ-CORE Fa3/0` too; cost 50 both ends | Guest policy holds on either WAN path |
| R-06 | Critical | `ACL_GUEST_IN` denies every zone by name | Guests can no longer reach staff VLAN, DMZ or WAN addresses |
| R-07 | High | `ACL_DMZ_IN` denies all trusted zones | DMZ cannot pivot inward |
| R-08 | Medium | VLAN 99 pool removed; `ACL_VTY` narrowed to two hosts, denials logged | Unauthorised SSH refused **and** logged |
| R-09 | High | `dnsmasq` `no-resolv` + explicit upstreams + PTR records | External names resolve |
| R-10 | High | Edge ACL return traffic matched structurally; inbound port 53 hole closed | Outbound DNS/NTP replies no longer dropped |
| R-11 | High | `ip domain-lookup` enabled, sourced from `Loopback0` | Names resolve from a router console |
| R-12 | Medium | Container scripts install packages before repointing the resolver | Ansible, chrony, nginx, rsyslog actually install |
| R-13 | Medium | `SW-DMZ-1 Eth0` native VLAN 1 | DMZ carries tagged VLAN 60; `PC-DMZ` gets a lease |
| R-14 | Medium | `service timestamps` + `clock timezone` + `logging origin-id` | Log entries carry wall-clock time and a device name |
| R-15 | Medium | One block per interface; `line vty 5 15` guarded | ACL cannot be bypassed on a sixth session |
| R-17 | Low | `PC5`/`PC8` confirmed at HQ | No action — repo already matches the lab |
| R-18 | Low | WAN transit removed from the NAT scope | No `10.255.0.x` in the translation table |

`R-16` (no STP / port security on the built-in switch) and `R-19` (stateless edge
inspection) are accepted platform limitations, documented with their upgrade paths
rather than silently omitted.
