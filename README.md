# MN521 Part A — Enterprise Network Design and Configuration

MIT **MN521 Network Automation**, Trimester T2 2026. Part A (30 marks) of the group
project: a four-zone enterprise network designed, built and verified in GNS3, and the
configuration package that Part B automates with Ansible.

**44 nodes** — 5 Cisco c7200 routers, 17 Ethernet switches, 9 Ubuntu servers,
10 VPCS endpoints, 1 NAT cloud, 2 L2 transit hubs.
**All ten required services**: VLANs, inter-VLAN routing, OSPF, DHCP, SSH, ACLs, NAT,
DNS, NTP, Syslog.

> The brief's minimum is 4 routers, 6 switches and 1 Linux automation server. Every
> addition beyond that carries policy or service rather than visual weight — the
> argument for each is in [`docs/NODE_INVENTORY.md`](docs/NODE_INVENTORY.md) §7.

---

## Start here

| If you want to… | Read |
|-----------------|------|
| Read the assessable report | [`report/PartA_Report.md`](report/PartA_Report.md) |
| Produce the submission `.docx` | [`report/BUILD_DOCX.md`](report/BUILD_DOCX.md) |
| Understand what every node does | [`docs/NODE_INVENTORY.md`](docs/NODE_INVENTORY.md) |
| See the topology and cabling | [`docs/TOPOLOGY.md`](docs/TOPOLOGY.md) |
| Look up an address | [`docs/IP_ADDRESSING.md`](docs/IP_ADDRESSING.md) |
| Know *why* it is built this way | [`docs/DESIGN_JUSTIFICATION.md`](docs/DESIGN_JUSTIFICATION.md) |
| See what was broken and fixed | [`docs/REVIEW_FINDINGS.md`](docs/REVIEW_FINDINGS.md) |
| Build or re-apply the lab | [`docs/APPLY_STEPS.md`](docs/APPLY_STEPS.md) |
| Test it | [`verification/CHECKS.md`](verification/CHECKS.md) |

## Repository layout

| Path | Contents |
|------|----------|
| [`configs/*.cfg`](configs/) | The five IOS startup configurations — the source of truth |
| [`configs/switches/`](configs/switches/) | Port/VLAN matrix for all 17 switches, JSON + readable table |
| [`configs/linux/`](configs/linux/) | Idempotent setup scripts for the nine Ubuntu servers |
| [`configs/netplan/`](configs/netplan/) | Declarative equivalents of the server addressing |
| [`configs/vpcs/`](configs/vpcs/) | Ten endpoint definitions, all DHCP |
| [`docs/`](docs/) | Topology, addressing, node inventory, design justification, findings, apply steps, live link map |
| [`report/`](report/) | The report, `.docx` build instructions, figure placeholders, CSV tables |
| [`verification/`](verification/) | Ordered test plan with 60 checks and 41 screenshot slots |
| [`scripts/`](scripts/) | Config validator, docs/config consistency checker, GNS3 apply script |

## Validate before you apply

```bash
python3 scripts/validate_configs.py     # IOS structure + security baseline (5 configs)
python3 scripts/check_consistency.py    # docs tables agree with the configs
```

Both exit `0` when clean. The first asserts what fails *silently* on this platform —
interface names that exist on a c7200 with slots 0–3, one block per interface and line
range, no ACL referenced before definition, no exec-mode command in a startup config,
both VTY ranges guarded. A config naming `GigabitEthernet0/0` applies without error and
does nothing, so this is a correctness check, not style.

## Design at a glance

| Zone | Trust | Gateway | Area | Contents |
|------|-------|---------|-----:|----------|
| Internet | untrusted | — | — | `Internet-NAT`, `ISP-Cloud` |
| DMZ | semi-trusted | `FW-EDGE Fa2/0.60` | 0 | `WEB-SRV` (TCP 80 published), `APP-SRV` (8080), `PC-DMZ` |
| Backbone | trusted | — | 0 | 5 routers, `WAN-Cloud` backup segment |
| Headquarters | trusted | `HQ-DIST Fa2/0.10/.20/.99` | 10 | `AUTO-SRV`, `JUMP-SRV`, `PC1`/`PC2`/`PC5`/`PC8` |
| Data Centre | trusted | `DC-EDGE Fa3/0.30` | 20 | `DNS`, `NTP`, `SYSLOG`, `FILE-SRV`, `MON-SRV` |
| Branch — staff | trusted | `BR-EDGE Fa3/0.40` | 30 | `PC3`, `PC6`, `PC7` |
| Branch — guest | **untrusted** | `BR-EDGE Fa3/0.50` | 30 | `PC4`, `PC9` |

- **Routing**: OSPF process 1, areas 0/10/20/30, 5 adjacencies, MD5 on the backbone.
  `FW-EDGE` is the sole ASBR.
- **Resilience**: a second Branch uplink via `WAN-Cloud`, at `ip ospf cost 50` so it is
  a genuine backup rather than an equal-cost path that would bypass the Data Centre
  policy chokepoint.
- **Security**: 6 named ACLs at 7 enforcement points, all with logged denials.

## Two actions required in the lab

Both are in [`docs/APPLY_STEPS.md`](docs/APPLY_STEPS.md); neither is optional.

1. **Re-apply all five router configurations in one pass.** `HQ-CORE Fa0/0` is no
   longer a NAT/DHCP interface, and OSPF area 0 authentication has to land on all five
   devices together.
2. **Delete three links in GNS3** — `SW-HQ-1 Eth7↔SW-HQ-2 Eth0`,
   `SW-DC-1 Eth7↔SW-DC-2 Eth0`, `SW-BR-1 Eth7↔SW-BR-2 Eth0`. Each closes a Layer 2 loop
   on a switching platform with no spanning tree. Nothing is disconnected — every switch
   keeps its aggregation uplink.

## Status

| Area | State |
|------|-------|
| Router configurations | Complete, validated, 0 failures |
| Switch port matrix | Complete, 17 switches |
| Server and endpoint configs | Complete, 9 + 10, addresses cross-checked |
| Documentation | Complete |
| Report | Drafted, with figure and screenshot placeholders |
| **Verification** | **Planned, not executed** — 60 checks and 41 screenshot slots awaiting capture |

No verification result in this repository is asserted ahead of capture. Nothing
fabricates a ping count, routing metric, translation table or log line.

## Credentials

| Purpose | Username | Password |
|---------|----------|----------|
| Console, SSH and `enable` on all five routers | `admin` | `Cisco123!` |

Lab values only, deliberately shared so the package is self-contained and reproducible
by a marker. In production this would be centralised AAA with per-administrator
accounts and SSH public-key authentication. The management-plane controls that *are*
implemented — source-restricted VTY access on both line ranges, session timeouts,
disabled aux and HTTP management, and login/configuration audit logging exported
off-box — are described in
[`docs/DESIGN_JUSTIFICATION.md`](docs/DESIGN_JUSTIFICATION.md) §4.1.

SSH additionally requires a one-time RSA host key per router after boot
(`APPLY_STEPS.md` §4). `crypto key generate rsa` is an exec-mode command and cannot
live in a startup configuration, so re-applying a config does not restore the keys.

## No IOS images

**No Cisco IOS binary image is included in this repository.** IOS images are
proprietary and cannot be redistributed. Supply your own c7200 image, and run GNS3's
Idle-PC calibration — without it each router consumes a full host core while idle and
five routers make the project unusable.
