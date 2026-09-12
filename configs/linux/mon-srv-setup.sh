#!/bin/bash
# MON-SRV — monitoring stub
# Idempotent setup for GNS3 docker / Ubuntu guest
set -euo pipefail
IFACE=${IFACE:-eth0}
IP=10.20.30.14
GW=10.20.30.1
MASK=24
DNS=10.20.30.10

ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
grep -q "$DNS" /etc/resolv.conf 2>/dev/null || echo "nameserver $DNS" > /etc/resolv.conf
echo "mon-srv.corp.local" > /etc/hostname || true

mkdir -p /opt/mon
cat >/opt/mon/stub.py <<'EOF'
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'{"status":"ok","service":"MON-SRV","targets":["routers","docker"]}'
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
HTTPServer(("0.0.0.0", 9090), H).serve_forever()
EOF
nohup python3 /opt/mon/stub.py >/var/log/mon.log 2>&1 &
echo "MON-SRV stub :9090 ready"
