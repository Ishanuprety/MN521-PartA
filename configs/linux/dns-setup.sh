#!/bin/bash
# =============================================================================
# DNS  -  10.20.30.10/24  -  VLAN 30 (DC_SERVERS)  -  gateway 10.20.30.1
#
# Authoritative resolver for corp.local and forwarder for everything else.
# Consumed by: every router (ip name-server 10.20.30.10), every DHCP client
# (dns-server option in all pools), and the DMZ via an explicit ACL permit.
#
# Idempotent: safe to re-run after a container restart, which is required
# because a GNS3 Docker node does not persist changes outside its configured
# persistent directories.
# =============================================================================
set -uo pipefail

IFACE=${IFACE:-eth0}
IP=10.20.30.10
MASK=24
GW=10.20.30.1

# ---------------------------------------------------------------- addressing --
ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
echo "dns.corp.local" > /etc/hostname || true
hostname dns.corp.local 2>/dev/null || true

# ------------------------------------------------------------------ packages --
# Install BEFORE pointing the resolver at ourselves. dnsmasq is not running yet,
# so writing "nameserver 10.20.30.10" first would leave apt-get with a resolver
# that cannot answer, and the install would fail on mirror lookup.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq dnsmasq dnsutils || true

# ------------------------------------------------------------------ zone data --
# host-record creates the forward A record AND the matching PTR in one line, so
# reverse lookups resolve too. "address=" would only have done the forward half.
cat >/etc/dnsmasq.d/corp.conf <<'EOF'
# ---- server identity -------------------------------------------------------
domain=corp.local
expand-hosts
local=/corp.local/
listen-address=127.0.0.1,10.20.30.10
bind-interfaces

# ---- upstream forwarding ---------------------------------------------------
# no-resolv is essential. Without it dnsmasq reads /etc/resolv.conf for its
# upstream servers, and /etc/resolv.conf on this host points at 10.20.30.10 -
# itself. That is a forwarding loop: every external name fails with SERVFAIL
# after dnsmasq queries itself. Upstreams are therefore named explicitly.
no-resolv
server=8.8.8.8
server=1.1.1.1

# Do not forward names with no domain part, or reverse lookups for RFC1918
# space, to the public resolvers - they cannot answer and it leaks internal
# names to the Internet.
domain-needed
bogus-priv

# ---- routers (loopback = router ID = syslog source) -----------------------
host-record=fw-edge.corp.local,4.4.4.4
host-record=hq-core.corp.local,1.1.1.1
host-record=hq-dist.corp.local,1.1.1.4
host-record=dc-edge.corp.local,2.2.2.2
host-record=br-edge.corp.local,3.3.3.3

# ---- Data Centre server farm, VLAN 30 -------------------------------------
host-record=dns.corp.local,10.20.30.10
host-record=ntp.corp.local,10.20.30.11
host-record=syslog.corp.local,10.20.30.12
host-record=file.corp.local,10.20.30.13
host-record=mon.corp.local,10.20.30.14

# ---- DMZ, VLAN 60 ---------------------------------------------------------
host-record=web.corp.local,10.60.60.10
host-record=app.corp.local,10.60.60.11

# ---- HQ management, VLAN 99 ----------------------------------------------
host-record=auto.corp.local,10.10.99.10
host-record=jump.corp.local,10.10.99.11

# ---- gateways ------------------------------------------------------------
host-record=gw-hq-users.corp.local,10.10.10.1
host-record=gw-hq-corp.corp.local,10.10.20.1
host-record=gw-hq-mgmt.corp.local,10.10.99.1
host-record=gw-dc.corp.local,10.20.30.1
host-record=gw-br-staff.corp.local,10.30.40.1
host-record=gw-br-guest.corp.local,10.30.50.1
host-record=gw-dmz.corp.local,10.60.60.1

# ---- evidence ------------------------------------------------------------
# Query logging lets name resolution be evidenced from the server side, which
# matters because VPCS has no resolver of its own to screenshot.
log-queries
log-facility=/var/log/dnsmasq.log
EOF

# Now it is safe to use ourselves as the resolver.
echo "nameserver 10.20.30.10" > /etc/resolv.conf
echo "search corp.local" >> /etc/resolv.conf

service dnsmasq restart 2>/dev/null || pkill dnsmasq 2>/dev/null; dnsmasq --conf-dir=/etc/dnsmasq.d 2>/dev/null || true

# ----------------------------------------------------------------- self-check --
echo "--- DNS self-check ---"
ip -4 addr show "$IFACE" | grep -w inet || echo "WARN no address on $IFACE"
ss -lunp 2>/dev/null | grep -w :53 || echo "WARN nothing listening on UDP 53"
for n in web.corp.local auto.corp.local hq-core.corp.local; do
  printf '%-24s ' "$n"
  nslookup "$n" 127.0.0.1 2>/dev/null | awk '/^Address: /{print $2; f=1} END{if(!f) print "LOOKUP FAILED"}' | tail -1
done
printf '%-24s ' "reverse 10.60.60.10"
nslookup 10.60.60.10 127.0.0.1 2>/dev/null | awk -F'= ' '/name = /{print $2; f=1} END{if(!f) print "PTR FAILED"}'
echo "DNS ready on $IP (authoritative for corp.local, forwarding to 8.8.8.8 / 1.1.1.1)"
