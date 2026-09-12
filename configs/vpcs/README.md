# VPCS startup scripts

Paste into VPCS console or place as startup script:

```
set pcname PC1
dhcp
```

All PCs use DHCP from site edge routers / FW-EDGE (DMZ VLAN60).
Excluded server range .1–.20 on each subnet; leases start at .21+.
