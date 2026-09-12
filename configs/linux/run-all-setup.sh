#!/bin/bash
# =============================================================================
# Helper for the nine Docker service nodes.
#
# Each container runs exactly ONE of the *-setup.sh scripts - the one matching
# its node name. There is no script that configures every node, because each
# node has a different address, gateway and service.
#
#   ./run-all-setup.sh             list the nodes and their scripts
#   ./run-all-setup.sh dns         run dns-setup.sh (inside the DNS container)
#   ./run-all-setup.sh --auto      guess from the hostname and run it
#
# Recommended bring-up order, because later nodes depend on earlier ones:
#   1. dns, ntp, syslog   (every router and host points at these)
#   2. file-srv, mon-srv  (Data Centre)
#   3. web-srv, app-srv   (DMZ)
#   4. auto-srv, jump-srv (management - needs DNS for its own resolution)
# =============================================================================
set -uo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)

list() {
    printf '%-10s %-16s %-6s %-24s %s\n' NODE ADDRESS VLAN SERVICE SCRIPT
    printf '%-10s %-16s %-6s %-24s %s\n' dns      10.20.30.10 30 "dnsmasq (corp.local)"    dns-setup.sh
    printf '%-10s %-16s %-6s %-24s %s\n' ntp      10.20.30.11 30 "chrony local stratum 10" ntp-setup.sh
    printf '%-10s %-16s %-6s %-24s %s\n' syslog   10.20.30.12 30 "rsyslog 514 collector"   syslog-setup.sh
    printf '%-10s %-16s %-6s %-24s %s\n' file-srv 10.20.30.13 30 "HTTP file share"         file-srv-setup.sh
    printf '%-10s %-16s %-6s %-24s %s\n' mon-srv  10.20.30.14 30 "monitoring + sweep 9090" mon-srv-setup.sh
    printf '%-10s %-16s %-6s %-24s %s\n' web-srv  10.60.60.10 60 "nginx 80 (published)"    web-srv-setup.sh
    printf '%-10s %-16s %-6s %-24s %s\n' app-srv  10.60.60.11 60 "app 8080 (published)"    app-srv-setup.sh
    printf '%-10s %-16s %-6s %-24s %s\n' auto-srv 10.10.99.10 99 "Ansible / Netmiko"       auto-srv-setup.sh
    printf '%-10s %-16s %-6s %-24s %s\n' jump-srv 10.10.99.11 99 "SSH bastion"             jump-srv-setup.sh
}

target="${1:-}"

if [ -z "$target" ]; then
    list
    echo
    echo "Run one of: $(cd "$DIR" && ls -1 ./*-setup.sh | sed 's|\./||;s|-setup\.sh||' | tr '\n' ' ')"
    exit 0
fi

if [ "$target" = "--auto" ]; then
    target=$(hostname -s 2>/dev/null || hostname)
    target=${target%%.*}
    echo "hostname suggests node: $target"
fi

script="$DIR/${target}-setup.sh"
if [ ! -f "$script" ]; then
    echo "No script for '$target'." >&2
    list >&2
    exit 1
fi

echo "Running $script"
bash "$script"
