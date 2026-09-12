#!/bin/bash
ip addr add 10.20.30.11/24 dev eth0 2>/dev/null || true
ip route add default via 10.20.30.1 2>/dev/null || true
apt-get update && apt-get install -y chrony
cat >/etc/chrony/chrony.conf <<'CFG'
server 0.pool.ntp.org iburst
allow 10.0.0.0/8
local stratum 10
CFG
service chrony restart || chronyd
