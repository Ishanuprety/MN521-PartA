# Ethernet switch ports_mapping

Applied via GNS3 node `properties.ports_mapping` (access / dot1q).

## L2 loop warning
Export contains SW-HQ-1↔SW-HQ-2 plus both to SW-HQ-DIST (triangle). GNS3 `ethernet_switch` has **no STP**.
Mitigations in this pack: HQ-DIST Fa1/0 / DC-EDGE Fa2/0 / BR-EDGE Fa1/0 **shutdown**; prefer star via *-DIST/*-CORE.
Optional: delete SW-HQ-1 Eth7↔SW-HQ-2 Eth0 and similar redundant access-switch cross-links.

## SW-DMZ-1
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 60 | FW-EDGE |
| Eth1 | access | 60 | WEB-SRV |
| Eth2 | access | 60 | APP-SRV |
| Eth3 | access | 60 | PC-DMZ |

## SW-HQ-DIST
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | HQ-DIST |
| Eth1 | dot1q | 1 | SW-HQ-1 |
| Eth2 | dot1q | 1 | SW-HQ-2 |
| Eth3 | dot1q | 1 | SW-HQ-3 |
| Eth5 | dot1q | 1 | SW-HQ-4 |

## SW-HQ-1
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | HQ-DIST(shut) |
| Eth1 | access | 10 | PC1 |
| Eth2 | access | 99 | AUTO-SRV |
| Eth4 | dot1q | 1 | SW-HQ-DIST |
| Eth5 | access | 99 | MGMT-SW |
| Eth7 | dot1q | 1 | SW-HQ-2 |

## SW-HQ-2
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | SW-HQ-1 |
| Eth1 | access | 20 | PC2 |
| Eth2 | dot1q | 1 | SW-HQ-DIST |

## SW-HQ-3
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | SW-HQ-DIST |
| Eth1 | access | 10 | PC5 |

## SW-HQ-4
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | SW-HQ-DIST |
| Eth1 | access | 20 | PC8 |

## MGMT-SW
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | access | 99 | SW-HQ-1 |
| Eth1 | access | 99 | JUMP-SRV |

## SW-DC-CORE
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | DC-EDGE |
| Eth1 | dot1q | 1 | SW-DC-1 |
| Eth2 | dot1q | 1 | SW-DC-2 |
| Eth3 | dot1q | 1 | SW-DC-3 |
| Eth5 | dot1q | 1 | SW-DC-4 |

## SW-DC-1
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | DC-EDGE(shut) |
| Eth1 | access | 30 | DNS |
| Eth2 | access | 30 | NTP |
| Eth3 | access | 30 | Syslog |
| Eth6 | dot1q | 1 | SW-DC-CORE |
| Eth7 | dot1q | 1 | SW-DC-2 |

## SW-DC-2
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | SW-DC-1 |
| Eth6 | dot1q | 1 | SW-DC-CORE |

## SW-DC-3
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | SW-DC-CORE |
| Eth1 | access | 30 | FILE-SRV |

## SW-DC-4
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | SW-DC-CORE |
| Eth1 | access | 30 | MON-SRV |

## SW-BR-DIST
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | BR-EDGE |
| Eth1 | dot1q | 1 | SW-BR-1 |
| Eth2 | dot1q | 1 | SW-BR-2 |
| Eth3 | dot1q | 1 | SW-BR-3 |
| Eth5 | dot1q | 1 | SW-BR-4 |

## SW-BR-1
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | BR-EDGE(shut) |
| Eth1 | access | 40 | PC3 |
| Eth3 | access | 40 | PC7 |
| Eth6 | dot1q | 1 | SW-BR-DIST |
| Eth7 | dot1q | 1 | SW-BR-2 |

## SW-BR-2
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | SW-BR-1 |
| Eth1 | access | 50 | PC4 |
| Eth6 | dot1q | 1 | SW-BR-DIST |

## SW-BR-3
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | SW-BR-DIST |
| Eth1 | access | 40 | PC6 |

## SW-BR-4
| Port | Type | VLAN | Typical peer |
|------|------|------|--------------|
| Eth0 | dot1q | 1 | SW-BR-DIST |
| Eth1 | access | 50 | PC9 |
