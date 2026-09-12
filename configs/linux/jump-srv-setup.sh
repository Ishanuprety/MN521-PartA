#!/bin/bash
# =============================================================================
# JUMP-SRV  -  10.10.99.11/24  -  VLAN 99 (HQ_MGMT)  -  gateway 10.10.99.1
#
# Management bastion. One of only two hosts named individually in ACL_VTY on all
# five routers, so administrative SSH has exactly two authorised origins:
#   10.10.99.10  AUTO-SRV  (automated changes)
#   10.10.99.11  JUMP-SRV  (interactive human access)
#
# The separation is the point. Automation and interactive administration are
# different trust paths with different audit trails, and neither can be performed
# from an ordinary user VLAN - ACL_HQ_USERS_IN blocks VLAN 10 from reaching this
# subnet at all, and ACL_VTY refuses any other source address.
#
# Reached over VLAN 99, which is carried untagged between SW-HQ-1 Eth5 and
# MGMT-SW Eth0 (both access ports on VLAN 99).
#
# Idempotent: safe to re-run after a container restart.
# =============================================================================
set -uo pipefail

IFACE=${IFACE:-eth0}
IP=10.10.99.11
MASK=24
GW=10.10.99.1
DNS=10.20.30.10

# ---------------------------------------------------------------- addressing --
ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
echo "jump-srv.corp.local" > /etc/hostname || true
hostname jump-srv.corp.local 2>/dev/null || true

# ------------------------------------------------------------------ packages --
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq openssh-server openssh-client iputils-ping dnsutils traceroute || true

echo "nameserver $DNS" > /etc/resolv.conf
echo "search corp.local" >> /etc/resolv.conf

mkdir -p /root/.ssh && chmod 700 /root/.ssh
# Keep an SSH config so an administrator does not have to remember loopbacks.
cat >/root/.ssh/config <<'EOF'
Host fw-edge
    HostName 4.4.4.4
Host hq-core
    HostName 1.1.1.1
Host hq-dist
    HostName 1.1.1.4
Host dc-edge
    HostName 2.2.2.2
Host br-edge
    HostName 3.3.3.3

Host fw-edge hq-core hq-dist dc-edge br-edge
    User admin
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    # Dynamips routers negotiate older algorithms than modern OpenSSH defaults.
    HostKeyAlgorithms +ssh-rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
    KexAlgorithms +diffie-hellman-group14-sha1,diffie-hellman-group1-sha1
EOF
chmod 600 /root/.ssh/config

service ssh start 2>/dev/null || true

# ----------------------------------------------------------------- self-check --
echo "--- JUMP-SRV self-check ---"
ip -4 addr show "$IFACE" | grep -w inet || echo "WARN no address on $IFACE"
ip route | grep -w default || echo "WARN no default route"
ss -ltnp 2>/dev/null | grep -w :22 || echo "WARN sshd not listening on TCP 22"
echo "JUMP-SRV ready on $IP - 'ssh hq-core' style aliases configured for all 5 routers"
echo "NOTE: router SSH only answers after the RSA host key is generated on each"
echo "      device (docs/APPLY_STEPS.md step 2). Until then expect 'connection"
echo "      refused', which is the key being absent - not an ACL problem."
