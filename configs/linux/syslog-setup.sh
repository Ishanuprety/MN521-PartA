#!/bin/bash
# =============================================================================
# SYSLOG  -  10.20.30.12/24  -  VLAN 30 (DC_SERVERS)  -  gateway 10.20.30.1
#
# Central log collector for all five routers. Every router is configured with:
#   logging host 10.20.30.12
#   logging trap informational
#   logging origin-id hostname
#   logging source-interface Loopback0
#
# so each message arrives from a stable per-device address (4.4.4.4, 1.1.1.1,
# 1.1.1.4, 2.2.2.2, 3.3.3.3) rather than from whichever interface the packet
# happened to leave by. A collector filter keyed on LAN subnets would see nothing.
#
# Idempotent: safe to re-run after a container restart.
# =============================================================================
set -uo pipefail

IFACE=${IFACE:-eth0}
IP=10.20.30.12
MASK=24
GW=10.20.30.1
DNS=10.20.30.10

# ---------------------------------------------------------------- addressing --
ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
echo "syslog.corp.local" > /etc/hostname || true
hostname syslog.corp.local 2>/dev/null || true

# ------------------------------------------------------------------ packages --
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq rsyslog || true

echo "nameserver $DNS" > /etc/resolv.conf
echo "search corp.local" >> /etc/resolv.conf

# -------------------------------------------------------------- collector cfg --
mkdir -p /var/log/network
cat >/etc/rsyslog.d/50-remote.conf <<'EOF'
# ---- listeners -------------------------------------------------------------
module(load="imudp")
input(type="imudp" port="514")
module(load="imtcp")
input(type="imtcp" port="514")

# Keep the sender's own name/address rather than rewriting it to a short form.
global(preserveFQDN="on")

# ---- per-device files ------------------------------------------------------
# One file per sender makes evidence collection a "cat" instead of a "grep", and
# makes a device that is NOT logging obvious by an absent file.
#
# With "logging origin-id hostname" on the routers, %HOSTNAME% resolves to the
# device name (hq-core, fw-edge, ...). Without it IOS sends no RFC3164 hostname
# field and rsyslog falls back to the source IP, so files appear as the loopback
# addresses instead. Either outcome is per-device and usable - check which you
# have with "ls /var/log/network/".
template(name="PerDevice" type="string" string="/var/log/network/%HOSTNAME%.log")

# ---- combined file ---------------------------------------------------------
# Also kept in one merged, time-ordered file, because correlating an ACL denial
# on BR-EDGE with the OSPF adjacency change on DC-EDGE that caused it is far
# easier in a single stream. This is why NTP is a prerequisite for the logging
# evidence: without a common clock these lines cannot be ordered.
template(name="Combined" type="string" string="/var/log/network/all-devices.log")

if ($fromhost-ip != "127.0.0.1") then {
    action(type="omfile" dynaFile="PerDevice")
    action(type="omfile" dynaFile="Combined")
    stop
}
EOF

service rsyslog restart 2>/dev/null || (pkill rsyslogd 2>/dev/null; rsyslogd) || true

# ----------------------------------------------------------------- self-check --
echo "--- SYSLOG self-check ---"
ip -4 addr show "$IFACE" | grep -w inet || echo "WARN no address on $IFACE"
ss -lunp 2>/dev/null | grep -w :514 || echo "WARN nothing listening on UDP 514"
ss -ltnp 2>/dev/null | grep -w :514 || echo "NOTE nothing listening on TCP 514"
echo "Collector directory:"
ls -l /var/log/network/ 2>/dev/null || echo "  (empty until the first router message arrives)"
echo "SYSLOG ready on $IP:514 - per-device files in /var/log/network/"
echo "Expect five senders once all routers are up: fw-edge, hq-core, hq-dist, dc-edge, br-edge"
echo "(or 4.4.4.4, 1.1.1.1, 1.1.1.4, 2.2.2.2, 3.3.3.3 if origin-id is not applied)."
