#!/bin/bash
# Run on DNS container (10.20.30.10)
ip addr add 10.20.30.10/24 dev eth0 2>/dev/null || true
ip route add default via 10.20.30.1 2>/dev/null || true
apt-get update && apt-get install -y dnsmasq
cat >/etc/dnsmasq.conf <<'CFG'
interface=eth0
listen-address=10.20.30.10
no-resolv
server=8.8.8.8
address=/auto.corp.local/10.10.99.10
address=/dns.corp.local/10.20.30.10
address=/ntp.corp.local/10.20.30.11
address=/syslog.corp.local/10.20.30.12
CFG
service dnsmasq restart || dnsmasq
