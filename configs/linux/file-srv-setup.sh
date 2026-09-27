#!/bin/bash
# =============================================================================
# FILE-SRV  -  10.20.30.13/24  -  VLAN 30 (DC_SERVERS)  -  gateway 10.20.30.1
#
# Internal file service for HQ and Branch staff. Deliberately NOT in the DMZ and
# NOT published by any NAT entry: it is reachable from the trusted zones over the
# OSPF backbone and from nowhere else. Branch staff on VLAN 40 reach it across the
# WAN; Branch guests on VLAN 50 cannot, because ACL_GUEST_IN denies the whole
# 10.20.0.0/16 zone.
#
# That contrast is one of the clearer pieces of segmentation evidence available:
# PC3 (staff) reaches 10.20.30.13 and PC4 (guest) is refused, from two hosts on
# the same physical switch fabric a few ports apart.
#
# Idempotent: safe to re-run after a container restart.
# =============================================================================
set -uo pipefail

IFACE=${IFACE:-eth0}
IP=10.20.30.13
MASK=24
GW=10.20.30.1
DNS=10.20.30.10

# ---------------------------------------------------------------- addressing --
ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
echo "file-srv.corp.local" > /etc/hostname || true
hostname file-srv.corp.local 2>/dev/null || true
echo "nameserver $DNS" > /etc/resolv.conf
echo "search corp.local" >> /etc/resolv.conf

# ------------------------------------------------------------------ content ----
mkdir -p /srv/share
cat >/srv/share/README.txt <<'EOF'
MN521 Part A - FILE-SRV internal share
======================================
Zone      : Data Centre, VLAN 30 (DC_SERVERS)
Address   : 10.20.30.13/24, gateway 10.20.30.1
Reachable : HQ VLANs 10/20/99, Branch staff VLAN 40, DMZ is DENIED
Not published to the Internet - no NAT entry exists for this host.
EOF
printf 'MN521 sample payload\n' > /srv/share/sample.txt

pkill -f "http.server 80 --directory /srv/share" 2>/dev/null || true
nohup python3 -m http.server 80 --directory /srv/share >/var/log/filesrv.log 2>&1 &
sleep 1

# ----------------------------------------------------------------- self-check --
echo "--- FILE-SRV self-check ---"
ip -4 addr show "$IFACE" | grep -w inet || echo "WARN no address on $IFACE"
ip route | grep -w default || echo "WARN no default route"
ss -ltnp 2>/dev/null | grep -w :80 || echo "WARN nothing listening on TCP 80"
python3 - <<'PY' 2>/dev/null || echo "WARN local fetch failed"
import urllib.request
print("local HTTP OK, bytes:", len(urllib.request.urlopen("http://127.0.0.1/", timeout=3).read()))
PY
echo "FILE-SRV ready on http://$IP/ (internal only, not published)"
