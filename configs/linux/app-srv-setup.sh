#!/bin/bash
# =============================================================================
# APP-SRV  -  10.60.60.11/24  -  VLAN 60 (DMZ)  -  gateway 10.60.60.1
#
# Application tier behind the DMZ web tier. Published to the Internet by
# FW-EDGE with:
#   ip nat inside source static tcp 10.60.60.11 8080 interface FastEthernet0/0 8080
# and ACL_OUTSIDE_IN permits inbound TCP 8080 to the outside global address.
#
# It sits in the DMZ rather than the Data Centre because it is Internet-facing.
# ACL_DMZ_IN then stops it initiating a session into any trusted zone, so the
# two-tier DMZ (web + app) is contained as a unit rather than becoming a bridge
# into the server farm.
#
# Idempotent: safe to re-run after a container restart.
# =============================================================================
set -uo pipefail

IFACE=${IFACE:-eth0}
IP=10.60.60.11
MASK=24
GW=10.60.60.1
DNS=10.20.30.10

# ---------------------------------------------------------------- addressing --
ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
echo "app-srv.corp.local" > /etc/hostname || true
hostname app-srv.corp.local 2>/dev/null || true
echo "nameserver $DNS" > /etc/resolv.conf
echo "search corp.local" >> /etc/resolv.conf

# ------------------------------------------------------------------ service ----
mkdir -p /opt/app
cat >/opt/app/app.py <<'EOF'
#!/usr/bin/env python3
"""Minimal JSON application endpoint for MN521 Part A DMZ verification."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

PAYLOAD = json.dumps({
    "app": "MN521-APP",
    "tier": "application",
    "zone": "dmz",
    "vlan": 60,
    "ip": "10.60.60.11",
    "published_via": "FW-EDGE static PAT tcp/8080",
}).encode()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(PAYLOAD)))
        self.end_headers()
        self.wfile.write(PAYLOAD)

    def log_message(self, fmt, *args):
        # Keep the container console clean; requests are evidenced by curl output.
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
EOF

# Restart cleanly rather than stacking a second listener on each re-run.
pkill -f /opt/app/app.py 2>/dev/null || true
nohup python3 /opt/app/app.py >/var/log/app.log 2>&1 &
sleep 1

# ----------------------------------------------------------------- self-check --
echo "--- APP-SRV self-check ---"
ip -4 addr show "$IFACE" | grep -w inet || echo "WARN no address on $IFACE"
ip route | grep -w default || echo "WARN no default route"
ss -ltnp 2>/dev/null | grep -w :8080 || echo "WARN nothing listening on TCP 8080"
python3 - <<'PY' 2>/dev/null || echo "WARN local fetch failed"
import urllib.request
print("local response:", urllib.request.urlopen("http://127.0.0.1:8080/", timeout=3).read().decode())
PY
echo "APP-SRV ready on $IP:8080 (published via FW-EDGE static NAT)"
