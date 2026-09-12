# Part A — Design Justification

## Architecture
Three-site hierarchical enterprise: Headquarters (users + Internet edge), Data Centre (shared services), and Branch Office. WAN is hub-and-spoke via DC as transit with OSPF multi-area (Area 0 backbone, Areas 10/20/30 per site) for scalable route control.

## Device choice (compatibility)
- **Cisco c7200 Dynamips** (IOS 15.0 Adv Enterprise): already installed on the GNS3 VM; supports OSPF, DHCP, NAT, SSH, ACLs, subinterfaces (802.1Q), NTP client, Syslog. Fits Apple M3 Pro via GNS3 VM; avoids large x86 QEMU IOSv images that stress a 4 GB VM and limited free disk (~44 GB).
- **GNS3 Ethernet switches**: VLAN access/trunk port mapping for inter-VLAN labs without IOU/L2 images.
- **Ubuntu 22.04 Docker (arm64)**: AUTO-SRV (Ansible host for Part B), plus DNS/NTP/Syslog roles in DC — lightweight vs full QEMU VMs.

## Services mapping
| Requirement | Implementation |
|-------------|----------------|
| VLANs / Inter-VLAN | 802.1Q ROAS on HQ-DIST, DC-EDGE, BR-EDGE |
| OSPF | Process 1, multi-area, loopback RIDs |
| DHCP | Pools on HQ-DIST, DC-EDGE, BR-EDGE |
| SSH | Local AAA, RSA keys, VTY ACL |
| ACLs | VTY harden + guest isolation at branch/DC |
| NAT | PAT on HQ-CORE Fa0/0 toward GNS3 NAT |
| DNS / NTP / Syslog | DC servers 10.20.30.10–12; routers point to them |

## Scalability
Addressing uses 10.0.0.0/8 site-aligned blocks; new branches add /24s and OSPF stub/NSSA areas without renumbering the core.
