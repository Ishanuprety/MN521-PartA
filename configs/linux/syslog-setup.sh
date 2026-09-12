#!/bin/bash
ip addr add 10.20.30.12/24 dev eth0 2>/dev/null || true
ip route add default via 10.20.30.1 2>/dev/null || true
apt-get update && apt-get install -y rsyslog
cat >/etc/rsyslog.d/10-remote.conf <<'CFG'
module(load="imudp")
input(type="imudp" port="514")
module(load="imtcp")
input(type="imtcp" port="514")
CFG
service rsyslog restart
