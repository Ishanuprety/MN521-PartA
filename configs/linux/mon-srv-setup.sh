#!/bin/bash
# =============================================================================
# MON-SRV  -  10.20.30.14/24  -  VLAN 30 (DC_SERVERS)  -  gateway 10.20.30.1
#
# Network monitoring host. It completes the management plane: NTP gives the
# estate a common clock, SYSLOG collects what happened, and MON-SRV answers
# whether the estate is up right now.
#
# It is on VLAN 30 rather than the management VLAN 99 on purpose. ACL_VTY permits
# SSH from the 10.20.30.0/24 subnet, so MON-SRV is a deliberate break-glass path:
# if HQ-DIST or the HQ management VLAN is unreachable, an administrator can still
# reach every router from the Data Centre. With only host entries on VLAN 99, one
# router failure could lock administrators out of the whole estate.
#
# The reachability prober is what makes this node functional rather than
# decorative - it exercises exactly the paths the verification plan asserts.
#
# Idempotent: safe to re-run after a container restart.
# =============================================================================
set -uo pipefail

IFACE=${IFACE:-eth0}
IP=10.20.30.14
MASK=24
GW=10.20.30.1
DNS=10.20.30.10

# ---------------------------------------------------------------- addressing --
ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
echo "mon-srv.corp.local" > /etc/hostname || true
hostname mon-srv.corp.local 2>/dev/null || true

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq iputils-ping curl dnsutils traceroute || true

echo "nameserver $DNS" > /etc/resolv.conf
echo "search corp.local" >> /etc/resolv.conf

# ------------------------------------------------------- monitoring endpoint ---
mkdir -p /opt/mon
cat >/opt/mon/targets.txt <<'EOF'
# name              address        expectation
fw-edge             4.4.4.4        up
hq-core             1.1.1.1        up
hq-dist             1.1.1.4        up
dc-edge             2.2.2.2        up
br-edge             3.3.3.3        up
dns                 10.20.30.10    up
ntp                 10.20.30.11    up
syslog              10.20.30.12    up
file-srv            10.20.30.13    up
auto-srv            10.10.99.10    up
jump-srv            10.10.99.11    up
gw-hq-users         10.10.10.1     up
gw-br-staff         10.30.40.1     up
gw-dmz              10.60.60.1     up
EOF

cat >/opt/mon/probe.sh <<'EOF'
#!/bin/bash
# Reachability sweep across the estate. Run on demand, or from cron, and capture
# the output as verification evidence.
printf '%-20s %-16s %s\n' NAME ADDRESS RESULT
while read -r name addr _; do
    case "$name" in ''|\#*) continue ;; esac
    if ping -c 2 -W 2 "$addr" >/dev/null 2>&1; then
        printf '%-20s %-16s %s\n' "$name" "$addr" UP
    else
        printf '%-20s %-16s %s\n' "$name" "$addr" UNREACHABLE
    fi
done < /opt/mon/targets.txt
EOF
chmod +x /opt/mon/probe.sh

cat >/opt/mon/stub.py <<'EOF'
#!/usr/bin/env python3
"""Monitoring endpoint for MN521 Part A.

GET /        service metadata
GET /health  live reachability sweep across the estate
"""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import subprocess

META = json.dumps({
    "service": "MON-SRV",
    "zone": "data-centre",
    "vlan": 30,
    "ip": "10.20.30.14",
    "endpoints": ["/", "/health"],
}).encode()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.rstrip("/") == "/health":
            try:
                out = subprocess.run(
                    ["/opt/mon/probe.sh"], capture_output=True, text=True, timeout=120
                ).stdout
            except Exception as exc:  # probe must never take the endpoint down
                out = f"probe failed: {exc}"
            body = out.encode()
            ctype = "text/plain"
        else:
            body, ctype = META, "application/json"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 9090), Handler).serve_forever()
EOF

pkill -f /opt/mon/stub.py 2>/dev/null || true
nohup python3 /opt/mon/stub.py >/var/log/mon.log 2>&1 &
sleep 1

# ----------------------------------------------------------------- self-check --
echo "--- MON-SRV self-check ---"
ip -4 addr show "$IFACE" | grep -w inet || echo "WARN no address on $IFACE"
ip route | grep -w default || echo "WARN no default route"
ss -ltnp 2>/dev/null | grep -w :9090 || echo "WARN nothing listening on TCP 9090"
echo "MON-SRV ready on $IP:9090"
echo "  metadata : curl http://$IP:9090/"
echo "  sweep    : curl http://$IP:9090/health   (or run /opt/mon/probe.sh)"
echo "The sweep is the evidence artefact - capture its output for the report"
echo "rather than transcribing individual pings by hand."
