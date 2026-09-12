#!/bin/bash
ip addr add 10.10.99.10/24 dev eth0 2>/dev/null || true
ip route add default via 10.10.99.1 2>/dev/null || true
echo "nameserver 10.20.30.10" >/etc/resolv.conf
apt-get update && apt-get install -y python3 python3-pip sshpass openssh-client
# Ansible for Part B
pip3 install ansible netmiko || apt-get install -y ansible
