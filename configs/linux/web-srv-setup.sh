#!/bin/bash
# WEB-SRV — nginx web
# Idempotent setup for GNS3 docker / Ubuntu guest
set -euo pipefail
IFACE=${IFACE:-eth0}
IP=10.60.60.10
GW=10.60.60.1
MASK=24
DNS=10.20.30.10

ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
grep -q "$DNS" /etc/resolv.conf 2>/dev/null || echo "nameserver $DNS" > /etc/resolv.conf
echo "web-srv.corp.local" > /etc/hostname || true

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq nginx || true
mkdir -p /var/www/html
cat >/var/www/html/index.html <<'EOF'
<html><body><h1>MN521 WEB-SRV</h1><p>DMZ web tier 10.60.60.10</p></body></html>
EOF
service nginx restart || nginx || true
# fallback
if ! curl -s -o /dev/null http://127.0.0.1/; then
  nohup python3 -m http.server 80 --directory /var/www/html >/var/log/web.log 2>&1 &
fi
echo "WEB-SRV ready"
