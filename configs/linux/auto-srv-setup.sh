#!/bin/bash
# =============================================================================
# AUTO-SRV  -  10.10.99.10/24  -  VLAN 99 (HQ_MGMT)  -  gateway 10.10.99.1
#
# Ansible / Netmiko control node. This is the "Linux automation server" the
# Part A brief requires, and it becomes the control node for Part B.
#
# It sits on the management VLAN deliberately: ACL_VTY on all five routers
# permits SSH from host 10.10.99.10 only (plus JUMP-SRV and the DC server VLAN),
# so automation is subject to the same access control as a human administrator.
# That is what makes ACL_VTY a real control rather than a decoration.
#
# Idempotent: safe to re-run after a container restart.
# =============================================================================
set -uo pipefail

IFACE=${IFACE:-eth0}
IP=10.10.99.10
MASK=24
GW=10.10.99.1
DNS=10.20.30.10

# ---------------------------------------------------------------- addressing --
ip link set "$IFACE" up || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP/$MASK" dev "$IFACE" || true
ip route replace default via "$GW" || true
echo "auto-srv.corp.local" > /etc/hostname || true
hostname auto-srv.corp.local 2>/dev/null || true

# ------------------------------------------------------------------ packages --
# Install BEFORE repointing the resolver: on first bring-up the DNS container may
# not be running yet, and apt-get would fail to resolve the Ubuntu mirrors. The
# failure surfaces much later as "ansible is not installed" with no obvious cause.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq openssh-client openssh-server sshpass python3 python3-pip iputils-ping dnsutils || true
apt-get install -y -qq ansible || true
# Netmiko is used for the screen-scraping tasks that ios_* modules cannot do.
pip3 install --quiet netmiko 2>/dev/null || pip3 install --quiet --break-system-packages netmiko 2>/dev/null || true

echo "nameserver $DNS" > /etc/resolv.conf
echo "search corp.local" >> /etc/resolv.conf

# ------------------------------------------------------------------ inventory --
# Targets are the LOOPBACKS, not the WAN interface addresses. A loopback is
# advertised into OSPF from every area, never goes down with a physical
# interface, and is the address the syslog collector already keys on - so one
# identity per device is used consistently across automation, routing and logs.
mkdir -p /etc/ansible/group_vars
cat >/etc/ansible/hosts <<'EOF'
# MN521 Part A inventory - addressed by Loopback0 (= OSPF router-id = log source)
[edge]
fw-edge  ansible_host=4.4.4.4

[core]
hq-core  ansible_host=1.1.1.1

[distribution]
hq-dist  ansible_host=1.1.1.4

[site_gateways]
dc-edge  ansible_host=2.2.2.2
br-edge  ansible_host=3.3.3.3

[routers:children]
edge
core
distribution
site_gateways
EOF

cat >/etc/ansible/group_vars/routers.yml <<'EOF'
---
ansible_connection: network_cli
ansible_network_os: ios
ansible_user: admin
# Lab credential only. In Part B this is replaced by an Ansible Vault variable.
ansible_password: Cisco123!
ansible_become: true
ansible_become_method: enable
ansible_become_password: Cisco123!
EOF

cat >/etc/ansible/ansible.cfg <<'EOF'
[defaults]
inventory = /etc/ansible/hosts
host_key_checking = False
interpreter_python = auto_silent
stdout_callback = yaml

[persistent_connection]
command_timeout = 60
connect_timeout = 60
EOF

service ssh start 2>/dev/null || true

# ----------------------------------------------------------------- self-check --
echo "--- AUTO-SRV self-check ---"
ip -4 addr show "$IFACE" | grep -w inet || echo "WARN no address on $IFACE"
ip route | grep -w default || echo "WARN no default route"
command -v ansible >/dev/null && ansible --version | head -1 || echo "WARN ansible not installed"
python3 -c "import netmiko; print('netmiko', netmiko.__version__)" 2>/dev/null || echo "WARN netmiko not installed"
ansible-inventory --list >/dev/null 2>&1 && echo "inventory parses OK" || echo "WARN inventory does not parse"
echo "AUTO-SRV ready on $IP - 5 routers in inventory group 'routers'"
echo "NOTE: SSH to the routers only works after the RSA host key is generated"
echo "      on each router (docs/APPLY_STEPS.md step 2)."
