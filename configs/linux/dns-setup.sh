#!/bin/bash
# DNS — dnsmasq/bind stub DNS
# Idempotent setup for GNS3 docker / Ubuntu guest
set -euo pipefail
IFACE=${IFACE:-eth0}
IP=10.20.30.10
GW=10.20.30.1
MASK=24
DNS=10.20.30.10

ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
grep -q "$DNS" /etc/resolv.conf 2>/dev/null || echo "nameserver $DNS" > /etc/resolv.conf
echo "dns.corp.local" > /etc/hostname || true

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq dnsmasq || true
cat >/etc/dnsmasq.d/corp.conf <<'EOF'
domain=corp.local
expand-hosts
local=/corp.local/
address=/dns.corp.local/10.20.30.10
address=/ntp.corp.local/10.20.30.11
address=/syslog.corp.local/10.20.30.12
address=/file.corp.local/10.20.30.13
address=/mon.corp.local/10.20.30.14
address=/web.corp.local/10.60.60.10
address=/app.corp.local/10.60.60.11
address=/auto.corp.local/10.10.99.10
address=/jump.corp.local/10.10.99.11
listen-address=127.0.0.1,10.20.30.10
bind-interfaces
EOF
service dnsmasq restart || dnsmasq || true
echo "DNS ready on $IP"
