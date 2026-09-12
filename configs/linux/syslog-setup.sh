#!/bin/bash
# Syslog — rsyslog UDP/TCP 514
# Idempotent setup for GNS3 docker / Ubuntu guest
set -euo pipefail
IFACE=${IFACE:-eth0}
IP=10.20.30.12
GW=10.20.30.1
MASK=24
DNS=10.20.30.10

ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
grep -q "$DNS" /etc/resolv.conf 2>/dev/null || echo "nameserver $DNS" > /etc/resolv.conf
echo "syslog.corp.local" > /etc/hostname || true

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq rsyslog || true
cat >/etc/rsyslog.d/50-remote.conf <<'EOF'
module(load="imudp")
input(type="imudp" port="514")
module(load="imtcp")
input(type="imtcp" port="514")
$template RemoteLogs,"/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log"
*.* ?RemoteLogs
& stop
EOF
mkdir -p /var/log/remote
service rsyslog restart || rsyslogd || true
echo "Syslog ready on $IP:514"
