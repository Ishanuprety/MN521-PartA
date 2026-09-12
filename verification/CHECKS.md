# Connectivity verification checklist
1. `show ip ospf neighbor` on all routers — FULL/DR or FULL/BDR as expected
2. `show ip route ospf` — see remote site networks
3. From PC1: ping 10.10.10.1, 10.20.30.10, 10.30.40.1
4. From PC4 (guest): ping 10.30.50.1 OK; ping 10.10.99.10 / 10.20.30.10 should FAIL (ACL)
5. `show ip dhcp binding` on HQ-DIST / BR-EDGE / DC-EDGE
6. SSH from AUTO-SRV to routers (after RSA keys generated)
7. NAT: from inside host ping 8.8.8.8 via HQ-CORE
8. `show logging` / confirm messages on Syslog host
9. `ntp status` on routers
