# Part A — Design Justification (FW / ISP / WAN update)

## Architecture
Three-site hierarchical enterprise plus an **Internet edge / DMZ**:
- **FW-EDGE** terminates Internet-NAT (via **ISP-Cloud** L2 transit), performs PAT, and hosts DMZ VLAN60.
- **HQ-CORE** is the campus/WAN core (no longer DHCP/NAT to Internet). Fa0/0 is the /30 to FW; Fa3/0 is backup WAN via **WAN-Cloud**.
- Primary WAN HQ↔DC↔BR; backup HQ↔BR over WAN-Cloud with higher OSPF cost (50).

## Device choice
- Cisco c7200 Dynamips (slots 0–3 FE) for FW + four site routers.
- GNS3 ethernet_switch fabric for VLANs (access/dot1q ports_mapping).
- ISP-Cloud / WAN-Cloud as real L2 transit segments (addressing on attached router ifaces).
- Ubuntu Docker for DNS/NTP/Syslog/FILE/MON/WEB/APP/AUTO/JUMP.

## NAT placement
PAT moved from HQ-CORE to **FW-EDGE** Fa0/0 so the firewall owns outside policy and DMZ publishing (WEB :80/:443, APP :8080).

## Loop avoidance
GNS3 ethernet_switch has no STP. Dual ROAS attachments + access-switch cross-links create loops.
Mitigation: HQ-DIST Fa1/0, DC-EDGE Fa2/0, BR-EDGE Fa1/0 administratively shut; ROAS only on DIST/CORE uplinks.
