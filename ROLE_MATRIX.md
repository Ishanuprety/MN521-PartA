# ROLE_MATRIX — MN521-PartA (every node has a functional role)

> **Quick reference.** For the full per-node breakdown — purpose, addressing, VLAN,
> gateway, switch port and the specific configuration artefact implementing each of the
> 44 nodes — see [`docs/NODE_INVENTORY.md`](docs/NODE_INVENTORY.md), which also argues
> why each addition beyond the brief's 4/6/1 minimum carries capability.
>
> **Two corrections to the tables below**, both from the live topology export:
>
> - `HQ-CORE Fa0/0` is `10.255.0.18/30` to `FW-EDGE` and runs **no NAT**. PAT is on
>   `FW-EDGE` only. A device still showing `ip nat outside` on `Fa0/0` is running a
>   superseded config — see [`docs/REVIEW_FINDINGS.md`](docs/REVIEW_FINDINGS.md) R-01.
> - `PC5` is on `SW-HQ-3` (VLAN 10) and `PC8` on `SW-HQ-4` (VLAN 20) — both at **HQ**,
>   not the Branch. Branch endpoints are `PC3`, `PC6`, `PC7` (VLAN 40) and `PC4`, `PC9`
>   (VLAN 50). See R-17 for the open decision.

Creds: `admin` / `Cisco123!` (routers). Project configs root:
`/Users/reckless/GNS3/projects/9c25a374-f40d-4407-a6c8-4cd996d061d0/configs/`

## Summary counts
| Type | Count | Role |
|------|------:|------|
| Dynamips routers | 5 | FW + HQ core/dist + DC/BR edge |
| Ethernet switches | 17 | VLAN access/trunk fabric |
| Docker hosts | 9 | DNS/NTP/Syslog/FILE/MON/WEB/APP/AUTO/JUMP |
| VPCS | 10 | End-user / DMZ clients |
| NAT | 1 | Internet breakout |
| Cloud / hub | 2 | ISP-Cloud + WAN-Cloud L2 transit |
| **Total** | **44** | |

## Routers
| Node | Purpose | Key interfaces / IPs | Config |
|------|---------|----------------------|--------|
| FW-EDGE | Internet edge firewall, PAT, DMZ GW | Fa0/0 DHCP outside (via ISP-Cloud); Fa1/0 **10.255.0.17/30**→HQ-CORE; Fa2/0.60 **10.60.60.1/24** DMZ; Lo0 4.4.4.4 | `configs/FW-EDGE.cfg` |
| HQ-CORE | HQ WAN core, OSPF ABR, default inject | Fa0/0 **10.255.0.18/30**→FW; Fa1/0 **10.255.0.1/30**→DC; Fa2/0 **10.255.0.9/30**→DIST; Fa3/0 **10.255.0.21/30** backup via WAN-Cloud; Lo0 1.1.1.1 | `configs/HQ-CORE.cfg` |
| HQ-DIST | HQ ROAS + DHCP VLANs 10/20/99 | Fa0/0 **10.255.0.10/30**; Fa2/0.10/20/99 **.1** gateways; Fa1/0 shut (no STP) | `configs/HQ-DIST.cfg` |
| DC-EDGE | DC ROAS + DHCP VLAN30 + WAN transit | Fa0/0 **10.255.0.2/30**; Fa1/0 **10.255.0.5/30**; Fa3/0.30 **10.20.30.1**; Fa2/0 shut | `configs/DC-EDGE.cfg` |
| BR-EDGE | Branch ROAS + DHCP 40/50 + backup WAN | Fa0/0 **10.255.0.6/30**; Fa2/0 **10.255.0.22/30** backup; Fa3/0.40/50 **.1**; Fa1/0 shut | `configs/BR-EDGE.cfg` |

## L2 transit (not decoration)
| Node | Purpose | Addressing |
|------|---------|------------|
| Internet-NAT | GNS3 NAT cloud to real Internet | DHCP server for FW Fa0/0 |
| ISP-Cloud | L2 transit Internet-NAT↔FW-EDGE | No IP — transit only |
| WAN-Cloud | L2 transit HQ-CORE Fa3/0↔BR-EDGE Fa2/0 | /30 on router ifaces 10.255.0.20/30 |

## HQ switches
| Node | Purpose | VLAN map file |
|------|---------|---------------|
| SW-HQ-DIST | HQ aggregation trunks | `configs/switches/ports_mapping.json` |
| SW-HQ-1 | Access VLAN10/99 (PC1, AUTO-SRV, MGMT uplink) | same |
| SW-HQ-2 | Access VLAN20 (PC2) | same |
| SW-HQ-3 | Access VLAN10 (PC5) | same |
| SW-HQ-4 | Access VLAN20 (PC8) | same |
| MGMT-SW | Mgmt access VLAN99 (JUMP-SRV) | same |

## DC switches
| Node | Purpose |
|------|---------|
| SW-DC-CORE | DC aggregation trunks to DC-EDGE |
| SW-DC-1 | Access VLAN30: DNS, NTP, Syslog |
| SW-DC-2 | DC access/expansion (trunked) |
| SW-DC-3 | Access VLAN30: FILE-SRV |
| SW-DC-4 | Access VLAN30: MON-SRV |

## Branch switches
| Node | Purpose |
|------|---------|
| SW-BR-DIST | Branch aggregation to BR-EDGE |
| SW-BR-1 | Access VLAN40: PC3, PC7 |
| SW-BR-2 | Access VLAN50: PC4 |
| SW-BR-3 | Access VLAN40: PC6 |
| SW-BR-4 | Access VLAN50: PC9 |
| SW-DMZ-1 | Access VLAN60: WEB, APP, PC-DMZ; trunk to FW |

## Docker hosts
| Node | IP | Purpose | Setup script |
|------|-----|---------|--------------|
| DNS | 10.20.30.10/24 | dnsmasq corp.local | `configs/linux/dns-setup.sh` |
| NTP | 10.20.30.11/24 | chrony/ntp stratum 10 | `configs/linux/ntp-setup.sh` |
| Syslog | 10.20.30.12/24 | rsyslog :514 | `configs/linux/syslog-setup.sh` |
| FILE-SRV | 10.20.30.13/24 | HTTP file share | `configs/linux/file-srv-setup.sh` |
| MON-SRV | 10.20.30.14/24 | monitoring stub :9090 | `configs/linux/mon-srv-setup.sh` |
| WEB-SRV | 10.60.60.10/24 | nginx DMZ web | `configs/linux/web-srv-setup.sh` |
| APP-SRV | 10.60.60.11/24 | app :8080 | `configs/linux/app-srv-setup.sh` |
| AUTO-SRV | 10.10.99.10/24 | Ansible automation | `configs/linux/auto-srv-setup.sh` |
| JUMP-SRV | 10.10.99.11/24 | SSH jump | `configs/linux/jump-srv-setup.sh` |

Netplan mirrors: `configs/netplan/*.yaml`.

## VPCS
| Node | VLAN | Addressing | Script |
|------|------|------------|--------|
| PC1 | 10 | DHCP | `configs/vpcs/PC1.txt` |
| PC2 | 20 | DHCP | `configs/vpcs/PC2.txt` |
| PC3 | 40 | DHCP | `configs/vpcs/PC3.txt` |
| PC4 | 50 | DHCP | `configs/vpcs/PC4.txt` |
| PC5 | 10 | DHCP | `configs/vpcs/PC5.txt` |
| PC6 | 40 | DHCP | `configs/vpcs/PC6.txt` |
| PC7 | 40 | DHCP | `configs/vpcs/PC7.txt` |
| PC8 | 20 | DHCP | `configs/vpcs/PC8.txt` |
| PC9 | 50 | DHCP | `configs/vpcs/PC9.txt` |
| PC-DMZ | 60 | DHCP | `configs/vpcs/PC-DMZ.txt` |

## WAN addressing quick ref
| Link | Network | Ends |
|------|---------|------|
| HQ↔DC | 10.255.0.0/30 | .1 HQ-CORE / .2 DC-EDGE |
| DC↔BR | 10.255.0.4/30 | .5 DC-EDGE / .6 BR-EDGE |
| HQ↔DIST | 10.255.0.8/30 | .9 HQ-CORE / .10 HQ-DIST |
| FW↔HQ | 10.255.0.16/30 | .17 FW / .18 HQ-CORE |
| Backup WAN | 10.255.0.20/30 | .21 HQ-CORE / .22 BR-EDGE |
