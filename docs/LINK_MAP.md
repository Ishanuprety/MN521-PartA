# LINK_MAP — MN521-PartA (from topology-export.json)

Source: evidence/topology-export.json (live snapshot). Adapter N on dynamips = FastEthernetN/0.

| # | Node A | Interface | Node B | Interface | Role |
|---|--------|-----------|--------|-----------|------|
| 1 | SW-HQ-1 | Eth7 | SW-HQ-2 | Eth0 |  |
| 2 | SW-HQ-1 | Eth1 | PC1 | e0 |  |
| 3 | SW-HQ-2 | Eth1 | PC2 | e0 |  |
| 4 | SW-DC-1 | Eth7 | SW-DC-2 | Eth0 |  |
| 5 | SW-BR-1 | Eth7 | SW-BR-2 | Eth0 |  |
| 6 | SW-BR-1 | Eth1 | PC3 | e0 |  |
| 7 | SW-BR-2 | Eth1 | PC4 | e0 |  |
| 8 | HQ-CORE | Fa1/0 | DC-EDGE | Fa0/0 | Primary WAN HQ↔DC /30 10.255.0.0 |
| 9 | HQ-CORE | Fa2/0 | HQ-DIST | Fa0/0 | HQ core↔dist /30 10.255.0.8 |
| 10 | DC-EDGE | Fa1/0 | BR-EDGE | Fa0/0 | Primary WAN DC↔BR /30 10.255.0.4 |
| 11 | HQ-DIST | Fa1/0 | SW-HQ-1 | Eth0 |  |
| 12 | SW-HQ-1 | Eth2 | AUTO-SRV | eth0 |  |
| 13 | DC-EDGE | Fa2/0 | SW-DC-1 | Eth0 |  |
| 14 | SW-DC-1 | Eth1 | DNS | eth0 |  |
| 15 | SW-DC-1 | Eth2 | NTP | eth0 |  |
| 16 | SW-DC-1 | Eth3 | Syslog | eth0 |  |
| 17 | BR-EDGE | Fa1/0 | SW-BR-1 | Eth0 |  |
| 18 | Internet-NAT | nat0 | FW-EDGE | Fa0/0 | Internet edge (export direct; design may insert ISP-Cloud) |
| 19 | FW-EDGE | Fa1/0 | HQ-CORE | Fa0/0 | FW↔HQ /30 10.255.0.16 |
| 20 | FW-EDGE | Fa2/0 | SW-DMZ-1 | Eth0 | DMZ trunk VLAN60 |
| 21 | SW-DMZ-1 | Eth1 | WEB-SRV | eth0 |  |
| 22 | SW-DMZ-1 | Eth2 | APP-SRV | eth0 |  |
| 23 | SW-DMZ-1 | Eth3 | PC-DMZ | e0 |  |
| 24 | HQ-CORE | Fa3/0 | BR-EDGE | Fa2/0 | Backup WAN (export direct; design via WAN-Cloud) /30 10.255.0.20 |
| 25 | HQ-DIST | Fa2/0 | SW-HQ-DIST | Eth0 |  |
| 26 | SW-HQ-DIST | Eth2 | SW-HQ-2 | Eth2 |  |
| 27 | SW-HQ-DIST | Eth3 | SW-HQ-3 | Eth0 |  |
| 28 | SW-HQ-3 | Eth1 | PC5 | e0 |  |
| 29 | DC-EDGE | Fa3/0 | SW-DC-CORE | Eth0 |  |
| 30 | SW-DC-CORE | Eth1 | SW-DC-1 | Eth6 |  |
| 31 | SW-DC-CORE | Eth2 | SW-DC-2 | Eth6 |  |
| 32 | SW-DC-CORE | Eth3 | SW-DC-3 | Eth0 |  |
| 33 | SW-DC-3 | Eth1 | FILE-SRV | eth0 |  |
| 34 | SW-BR-DIST | Eth1 | SW-BR-1 | Eth6 |  |
| 35 | SW-BR-DIST | Eth2 | SW-BR-2 | Eth6 |  |
| 36 | SW-BR-DIST | Eth3 | SW-BR-3 | Eth0 |  |
| 37 | SW-BR-3 | Eth1 | PC6 | e0 |  |
| 38 | SW-BR-1 | Eth3 | PC7 | e0 |  |
| 39 | SW-HQ-DIST | Eth1 | SW-HQ-1 | Eth4 |  |
| 40 | BR-EDGE | Fa3/0 | SW-BR-DIST | Eth0 |  |
| 41 | SW-HQ-1 | Eth5 | MGMT-SW | Eth0 |  |
| 42 | MGMT-SW | Eth1 | JUMP-SRV | eth0 |  |
| 43 | SW-HQ-DIST | Eth5 | SW-HQ-4 | Eth0 |  |
| 44 | SW-HQ-4 | Eth1 | PC8 | e0 |  |
| 45 | SW-DC-CORE | Eth5 | SW-DC-4 | Eth0 |  |
| 46 | SW-DC-4 | Eth1 | MON-SRV | eth0 |  |
| 47 | SW-BR-DIST | Eth5 | SW-BR-4 | Eth0 |  |
| 48 | SW-BR-4 | Eth1 | PC9 | e0 |  |

## Design note — ISP-Cloud / WAN-Cloud

Live node list includes **ISP-Cloud** (`cloud`) and **WAN-Cloud** (`ethernet_hub`).
This export's link list shows **Internet-NAT↔FW-EDGE** and **HQ-CORE↔BR-EDGE** as direct adjacencies
(hubs may be mid-path L2 transit without appearing as named endpoints in some exports, or need rewiring).

**Intended functional roles (not decoration):**
- `ISP-Cloud`: L2 transit Internet-NAT ↔ FW-EDGE Fa0/0 (DHCP/NAT outside on FW).
- `WAN-Cloud`: L2 transit HQ-CORE Fa3/0 (10.255.0.21/30) ↔ BR-EDGE Fa2/0 (10.255.0.22/30).

Addressing lives on the **router** interfaces attached to those segments.
