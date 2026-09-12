#!/bin/bash
# APP-SRV — simple app :8080
# Idempotent setup for GNS3 docker / Ubuntu guest
set -euo pipefail
IFACE=${IFACE:-eth0}
IP=10.60.60.11
GW=10.60.60.1
MASK=24
DNS=10.20.30.10

ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
grep -q "$DNS" /etc/resolv.conf 2>/dev/null || echo "nameserver $DNS" > /etc/resolv.conf
echo "app-srv.corp.local" > /etc/hostname || true

mkdir -p /opt/app
cat >/opt/app/app.py <<'EOF'
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'{"app":"MN521-APP","tier":"dmz","ip":"10.60.60.11"}'
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
HTTPServer(("0.0.0.0", 8080), H).serve_forever()
EOF
nohup python3 /opt/app/app.py >/var/log/app.log 2>&1 &
echo "APP-SRV :8080 ready"
