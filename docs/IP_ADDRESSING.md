# MN521 Part A — Enterprise IP Addressing Plan (updated FW/ISP/WAN)

## Sites
| Site | Role | OSPF Area |
|------|------|-----------|
| Internet edge / DMZ | FW-EDGE PAT + VLAN60 | 0 (FW) |
| Headquarters (HQ) | Users, mgmt, automation | 10 |
| Data Centre (DC) | Shared services | 20 |
| Branch Office (BR) | Users + guest | 30 |
| WAN backbone | Site interconnect + backup | 0 |

## VLANs
| VLAN | Name | Subnet | Gateway | Site |
|------|------|--------|---------|------|
| 10 | HQ_USERS | 10.10.10.0/24 | 10.10.10.1 (HQ-DIST) | HQ |
| 20 | HQ_CORP | 10.10.20.0/24 | 10.10.20.1 | HQ |
| 99 | HQ_MGMT | 10.10.99.0/24 | 10.10.99.1 | HQ |
| 30 | DC_SERVERS | 10.20.30.0/24 | 10.20.30.1 (DC-EDGE) | DC |
| 40 | BR_USERS | 10.30.40.0/24 | 10.30.40.1 (BR-EDGE) | BR |
| 50 | BR_GUEST | 10.30.50.0/24 | 10.30.50.1 | BR |
| 60 | DMZ | 10.60.60.0/24 | 10.60.60.1 (FW-EDGE) | Edge |

## WAN /30 links
| Link | Network | Ends |
|------|---------|------|
| HQ-CORE ↔ DC-EDGE | 10.255.0.0/30 | .1 ↔ .2 |
| DC-EDGE ↔ BR-EDGE | 10.255.0.4/30 | .5 ↔ .6 |
| HQ-CORE ↔ HQ-DIST | 10.255.0.8/30 | .9 ↔ .10 |
| FW-EDGE ↔ HQ-CORE | 10.255.0.16/30 | .17 ↔ .18 |
| HQ-CORE ↔ BR-EDGE (WAN-Cloud backup) | 10.255.0.20/30 | .21 ↔ .22 |
| FW-EDGE ↔ Internet-NAT (via ISP-Cloud) | DHCP | Fa0/0 on FW |

## Hosts
| Device | Address |
|--------|---------|
| DNS | 10.20.30.10 |
| NTP | 10.20.30.11 |
| Syslog | 10.20.30.12 |
| FILE-SRV | 10.20.30.13 |
| MON-SRV | 10.20.30.14 |
| WEB-SRV | 10.60.60.10 |
| APP-SRV | 10.60.60.11 |
| AUTO-SRV | 10.10.99.10 |
| JUMP-SRV | 10.10.99.11 |
| PC1–9 / PC-DMZ | DHCP |

## Loopbacks (OSPF RID)
| Device | Loopback0 |
|--------|-----------|
| HQ-CORE | 1.1.1.1/32 |
| HQ-DIST | 1.1.1.4/32 |
| DC-EDGE | 2.2.2.2/32 |
| BR-EDGE | 3.3.3.3/32 |
| FW-EDGE | 4.4.4.4/32 |
