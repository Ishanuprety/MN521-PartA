#!/bin/bash
# NTP — chrony/ntpd stratum 10
# Idempotent setup for GNS3 docker / Ubuntu guest
set -euo pipefail
IFACE=${IFACE:-eth0}
IP=10.20.30.11
GW=10.20.30.1
MASK=24
DNS=10.20.30.10

ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
grep -q "$DNS" /etc/resolv.conf 2>/dev/null || echo "nameserver $DNS" > /etc/resolv.conf
echo "ntp.corp.local" > /etc/hostname || true

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq chrony || apt-get install -y -qq ntp || true
if command -v chronyd >/dev/null; then
  cat >/etc/chrony/chrony.conf <<'EOF'
local stratum 10
allow 10.0.0.0/8
driftfile /var/lib/chrony/chrony.drift
makestep 1.0 3
rtcsync
EOF
  service chrony restart || chronyd || true
else
  cat >/etc/ntp.conf <<'EOF'
server 127.127.1.0
fudge 127.127.1.0 stratum 10
restrict default kod nomodify notrap nopeer noquery
restrict 10.0.0.0 mask 255.0.0.0
restrict 127.0.0.1
EOF
  service ntp restart || ntpd || true
fi
echo "NTP ready on $IP"
