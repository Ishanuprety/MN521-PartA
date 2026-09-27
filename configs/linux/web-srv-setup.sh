#!/bin/bash
# =============================================================================
# WEB-SRV  -  10.60.60.10/24  -  VLAN 60 (DMZ)  -  gateway 10.60.60.1
#
# The enterprise's only Internet-reachable service. FW-EDGE publishes it with:
#   ip nat inside source static tcp 10.60.60.10 80 interface FastEthernet0/0 80
# and ACL_OUTSIDE_IN permits inbound TCP 80 to the outside global address.
#
# This is the ONLY inbound-initiated flow in the design, and it terminates in the
# DMZ - never in a trusted zone. ACL_DMZ_IN then prevents this host from opening
# a session into HQ, the Data Centre or the Branch, so compromising the one
# exposed service does not yield a foothold inside.
#
# Idempotent: safe to re-run after a container restart.
# =============================================================================
set -uo pipefail

IFACE=${IFACE:-eth0}
IP=10.60.60.10
MASK=24
GW=10.60.60.1
DNS=10.20.30.10

# ---------------------------------------------------------------- addressing --
ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
echo "web-srv.corp.local" > /etc/hostname || true
hostname web-srv.corp.local 2>/dev/null || true

# ------------------------------------------------------------------ packages --
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq nginx curl || true

echo "nameserver $DNS" > /etc/resolv.conf
echo "search corp.local" >> /etc/resolv.conf

# ------------------------------------------------------------------ content ----
mkdir -p /var/www/html
cat >/var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head><title>MN521 WEB-SRV</title></head>
<body style="font-family:Calibri,Arial,sans-serif">
<h1>MN521 Enterprise - WEB-SRV</h1>
<p>DMZ web tier, VLAN 60, 10.60.60.10</p>
<p>Published to the Internet by static port translation on FW-EDGE (TCP 80).</p>
<hr>
<p>If you are reading this from outside the enterprise, the following all worked:
   the perimeter ACL permitted TCP 80, the static NAT entry translated the
   destination, and OSPF returned the reply through FW-EDGE.</p>
</body>
</html>
EOF

service nginx restart 2>/dev/null || nginx 2>/dev/null || true

# nginx is unavailable in some minimal images; fall back so the published port is
# never left with nothing behind it (a published port with no listener would make
# the NAT verification step fail for the wrong reason).
sleep 1
if ! (curl -s -o /dev/null --max-time 3 http://127.0.0.1/ 2>/dev/null); then
  echo "NOTE nginx not serving - starting python fallback on :80"
  nohup python3 -m http.server 80 --directory /var/www/html >/var/log/web.log 2>&1 &
  sleep 1
fi

# ----------------------------------------------------------------- self-check --
echo "--- WEB-SRV self-check ---"
ip -4 addr show "$IFACE" | grep -w inet || echo "WARN no address on $IFACE"
ip route | grep -w default || echo "WARN no default route"
ss -ltnp 2>/dev/null | grep -w :80 || echo "WARN nothing listening on TCP 80"
curl -s -o /dev/null -w "local HTTP status: %{http_code}\n" --max-time 3 http://127.0.0.1/ 2>/dev/null || echo "WARN local fetch failed"
echo "WEB-SRV ready on $IP:80 (published via FW-EDGE static NAT)"
