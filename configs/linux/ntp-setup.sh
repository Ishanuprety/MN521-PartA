#!/bin/bash
# =============================================================================
# NTP  -  10.20.30.11/24  -  VLAN 30 (DC_SERVERS)  -  gateway 10.20.30.1
#
# Enterprise time source. Every router runs "ntp server 10.20.30.11 prefer" with
# "ntp source Loopback0", and the corporate DHCP pools hand this address out as
# option 42.
#
# Configured as "local stratum 10", which makes it authoritative WITHOUT needing
# Internet reachability - the lab must be demonstrable offline. Routers therefore
# synchronise at stratum 11, one level below. That is the correct expected value.
#
# Time matters here for a specific reason: without a common clock the syslog
# entries from five routers cannot be ordered, so NTP is a prerequisite for the
# centralised logging evidence rather than an independent requirement.
#
# Idempotent: safe to re-run after a container restart.
# =============================================================================
set -uo pipefail

IFACE=${IFACE:-eth0}
IP=10.20.30.11
MASK=24
GW=10.20.30.1
DNS=10.20.30.10

# ---------------------------------------------------------------- addressing --
ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
echo "ntp.corp.local" > /etc/hostname || true
hostname ntp.corp.local 2>/dev/null || true

# ------------------------------------------------------------------ packages --
# apt before the resolver switch - see dns-setup.sh for why.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq chrony || apt-get install -y -qq ntp || true

echo "nameserver $DNS" > /etc/resolv.conf
echo "search corp.local" >> /etc/resolv.conf

# -------------------------------------------------------------------- server --
if command -v chronyd >/dev/null 2>&1; then
  mkdir -p /var/lib/chrony
  cat >/etc/chrony/chrony.conf <<'EOF'
# Serve time even with no upstream reachable, so the lab works offline.
local stratum 10

# Clients: the whole enterprise. Routers source from Loopback0, so the allow
# statement must cover the loopback space as well as the site subnets.
allow 10.0.0.0/8
allow 1.0.0.0/8
allow 2.0.0.0/8
allow 3.0.0.0/8
allow 4.0.0.0/8

driftfile /var/lib/chrony/chrony.drift
makestep 1.0 3
rtcsync

# Optional upstream. Uncomment only if the NAT path to the Internet is up; with
# it commented out the server stays authoritative at stratum 10 regardless.
# pool 0.pool.ntp.org iburst
EOF
  service chrony restart 2>/dev/null || (pkill chronyd 2>/dev/null; chronyd) || true
  SERVICE=chrony
else
  cat >/etc/ntp.conf <<'EOF'
# Local clock as the reference, stratum 10 - authoritative without upstream.
server 127.127.1.0
fudge 127.127.1.0 stratum 10
restrict default kod nomodify notrap nopeer noquery
restrict 10.0.0.0 mask 255.0.0.0 nomodify notrap nopeer
restrict 127.0.0.1
EOF
  service ntp restart 2>/dev/null || (pkill ntpd 2>/dev/null; ntpd) || true
  SERVICE=ntp
fi

# ----------------------------------------------------------------- self-check --
echo "--- NTP self-check ($SERVICE) ---"
ip -4 addr show "$IFACE" | grep -w inet || echo "WARN no address on $IFACE"
ss -lunp 2>/dev/null | grep -w :123 || echo "WARN nothing listening on UDP 123"
if [ "$SERVICE" = chrony ]; then
  chronyc tracking 2>/dev/null | head -4 || echo "NOTE chronyc not ready yet"
  echo "clients (populates once routers poll):"
  chronyc clients 2>/dev/null | head -8 || true
fi
echo "NTP ready on $IP - local stratum 10, so routers report stratum 11"
echo "NOTE: synchronisation can take up to ~10 minutes on emulated hardware."
echo "      'show ntp status' reporting unsynchronised immediately after boot is"
echo "      expected and is not a fault."
