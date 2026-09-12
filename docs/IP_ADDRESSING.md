# MN521 Part A — Enterprise IP Addressing Plan

## Sites
| Site | Role | OSPF Area |
|------|------|-----------|
| Headquarters (HQ) | Users, mgmt, automation, Internet edge | 10 |
| Data Centre (DC) | DNS, NTP, Syslog, server farm | 20 |
| Branch Office (BR) | Branch users + guest | 30 |
| WAN backbone | Site interconnect | 0 |

## VLANs
| VLAN | Name | Subnet | Gateway | Site |
|------|------|--------|---------|------|
| 10 | HQ_USERS | 10.10.10.0/24 | 10.10.10.1 | HQ |
| 20 | HQ_CORP | 10.10.20.0/24 | 10.10.20.1 | HQ |
| 99 | HQ_MGMT | 10.10.99.0/24 | 10.10.99.1 | HQ |
| 30 | DC_SERVERS | 10.20.30.0/24 | 10.20.30.1 | DC |
| 40 | BR_USERS | 10.30.40.0/24 | 10.30.40.1 | BR |
| 50 | BR_GUEST | 10.30.50.0/24 | 10.30.50.1 | BR |

## WAN /30 links
| Link | Network | HQ-CORE / DC / BR end |
|------|---------|------------------------|
| HQ-CORE ↔ DC-EDGE | 10.255.0.0/30 | .1 ↔ .2 |
| DC-EDGE ↔ BR-EDGE | 10.255.0.4/30 | .5 ↔ .6 |
| HQ-CORE ↔ HQ-DIST | 10.255.0.8/30 | .9 ↔ .10 |
| HQ-CORE ↔ NAT | DHCP | Fa0/0 dhcp |

## Device addressing
| Device | Interface | Address | Notes |
|--------|-----------|---------|-------|
| HQ-CORE | Fa0/0 | DHCP | NAT outside → Internet |
| HQ-CORE | Fa1/0 | 10.255.0.1/30 | to DC-EDGE |
| HQ-CORE | Fa2/0 | 10.255.0.9/30 | to HQ-DIST |
| HQ-DIST | Fa0/0 | 10.255.0.10/30 | to HQ-CORE |
| HQ-DIST | Fa1/0.10 | 10.10.10.1/24 | HQ users SVI (ROAS) |
| HQ-DIST | Fa1/0.20 | 10.10.20.1/24 | HQ corp |
| HQ-DIST | Fa1/0.99 | 10.10.99.1/24 | HQ mgmt |
| DC-EDGE | Fa0/0 | 10.255.0.2/30 | to HQ-CORE |
| DC-EDGE | Fa1/0 | 10.255.0.5/30 | to BR-EDGE |
| DC-EDGE | Fa2/0.30 | 10.20.30.1/24 | DC servers |
| BR-EDGE | Fa0/0 | 10.255.0.6/30 | to DC-EDGE |
| BR-EDGE | Fa1/0.40 | 10.30.40.1/24 | Branch users |
| BR-EDGE | Fa1/0.50 | 10.30.50.1/24 | Branch guest |
| AUTO-SRV | eth0 | 10.10.99.10/24 | Ansible host |
| DNS | eth0 | 10.20.30.10/24 | dnsmasq/bind |
| NTP | eth0 | 10.20.30.11/24 | chrony/ntp |
| Syslog | eth0 | 10.20.30.12/24 | rsyslog |
| PC1 | eth0 | DHCP (VLAN10) | HQ user |
| PC2 | eth0 | DHCP (VLAN20) | HQ corp |
| PC3 | eth0 | DHCP (VLAN40) | Branch user |
| PC4 | eth0 | DHCP (VLAN50) | Branch guest |

## Loopbacks (OSPF router-id)
| Device | Loopback0 |
|--------|-----------|
| HQ-CORE | 1.1.1.1/32 |
| HQ-DIST | 1.1.1.4/32 |
| DC-EDGE | 2.2.2.2/32 |
| BR-EDGE | 3.3.3.3/32 |
