# MN521 Part B - Enterprise Network Automation with Ansible

Ansible project that builds, enforces and verifies the configuration of the five
Cisco IOS routers of the MN521 Group 3 lab (Part A topology in GNS3):
HQ-CORE, HQ-DIST, DC-EDGE, BR-EDGE and FW-EDGE (Dynamips c7200, IOS 15.0).

The control node is **AUTO-SRV** (Ubuntu 22.04 container in management VLAN 99; 10.10.99.10 in the
Part A design, DHCP lease 10.10.99.22 from HQ-DIST during the recorded runs).
It reaches each router's Loopback0 over OSPF, and ACL_VTY permits SSH from 10.10.99.0/24.

## Layout
```
part-b-ansible/
├── ansible.cfg                 # inventory, roles path, paramiko + timeouts
├── inventory/hosts.yml         # routers -> hq / dc / branch / edge (site groups)
├── group_vars/
│   ├── all/main.yml            # enterprise-wide data: NTP, syslog, banner, SSH, mgmt subnets
│   ├── all/vault.yml           # ANSIBLE VAULT (AES256): SSH user/password + enable password
│   ├── routers.yml             # network_cli / cisco.ios.ios connection settings
│   └── hq.yml dc.yml branch.yml edge.yml   # per-site data (site name, ping targets)
├── host_vars/<ROUTER>.yml      # per-device data: VLAN gateways, OSPF networks/areas, expected neighbours, ACLs
├── roles/
│   ├── base/        hostname + global services (template base.j2) + MOTD banner (ios_banner)
│   ├── ssh/         SSHv2, timers, VTY lines (ssh.j2) + assert "SSH Enabled - version 2.0"
│   ├── ntp_syslog/  NTP (ntp.j2) and syslog (syslog.j2), separately tagged ntp / syslog
│   ├── vlans/       802.1Q VLAN gateway subinterfaces (vlans.j2)
│   ├── ospf/        multi-area OSPF (ospf.j2) + assert expected neighbours FULL
│   ├── acl/         ACL_VTY + ACL_MGMT (acl.j2) + assert ACL_VTY on line vty
│   ├── backup/      running-config -> backups/<host>_<date>.cfg + reports/backup_index.csv
│   └── monitoring/  interfaces, routing, VLANs, ACLs, CPU/memory, connectivity, inventory
├── templates/monitoring_report.md.j2   # consolidated Markdown report
├── site.yml         # configuration (roles + handlers)
├── backup.yml       # configuration backups
├── monitoring.yml   # backup + 7 verification checks + reports/MONITORING_REPORT.md
├── save.yml         # on-demand write memory (same task as the handler)
├── tools/csv_table.py   # prints the CSV reports as aligned tables
├── requirements.txt / requirements.yml
├── backups/         # generated at run time (git-ignored: contains secret hashes)
├── reports/         # generated at run time (git-ignored)
└── evidence/        # copy of the recorded 27 Sep 2026 run: reports/ + sanitised backups/
```

## Requirements (control node)
- Python 3.10, `ansible-core` 2.17, `paramiko` 3.5.1 (`requirements.txt`)
- Collections: `cisco.ios`, `ansible.netcommon`, `ansible.utils` (`requirements.yml`)
```
python3 -m venv /opt/ansible && /opt/ansible/bin/pip install -r requirements.txt
/opt/ansible/bin/ansible-galaxy collection install -r requirements.yml -p /opt/ansible/collections
export ANSIBLE_COLLECTIONS_PATH=/opt/ansible/collections
```
The IOS 15.0 SSH server only offers legacy algorithms (KEX diffie-hellman-group-exchange-sha1 /
group14-sha1 / group1-sha1, aes-cbc/3des-cbc ciphers, ssh-rsa host key), so the project uses
`ansible_network_cli_ssh_type: paramiko` pinned to paramiko 3.5.1: paramiko 5.0 refused the
routers with "Incompatible ssh peer (no acceptable kex algorithm)".

### How AUTO-SRV was provisioned
Package downloads through the lab NAT ran at ~7 kB/s and timed out, so the Ubuntu .deb files
and a pre-built `/opt/ansible` virtualenv (same `ubuntu:22.04` image) were prepared in a
throw-away container on the GNS3 VM and copied into AUTO-SRV with `docker cp`.

## Vault
`group_vars/all/vault.yml` is encrypted with `ansible-vault` (AES256) and holds
`vault_ssh_user`, `vault_ssh_password` and `vault_enable_password`. `group_vars/routers.yml`
maps them to `ansible_user`, `ansible_password` and `ansible_become_password`.
The vault password is **not** in the repository (`.vault_pass` is git-ignored). For the demo it
is kept in `~/.vault_pass` (mode 600) on AUTO-SRV and given to the marker separately.
```
ansible-vault view group_vars/all/vault.yml --vault-password-file ~/.vault_pass
ansible-vault edit group_vars/all/vault.yml --vault-password-file ~/.vault_pass
```

## Running
```
cd part-b-ansible
ansible-inventory --graph
ansible-playbook site.yml --vault-password-file ~/.vault_pass                  # enforce everything
ansible-playbook site.yml --vault-password-file ~/.vault_pass --check --diff   # dry run, show diffs
ansible-playbook site.yml --vault-password-file ~/.vault_pass --tags ntp,syslog
ansible-playbook site.yml --vault-password-file ~/.vault_pass --tags vlans --limit HQ-DIST
ansible-playbook backup.yml --vault-password-file ~/.vault_pass
ansible-playbook monitoring.yml --vault-password-file ~/.vault_pass                 # all checks
ansible-playbook monitoring.yml --vault-password-file ~/.vault_pass --tags routing,vlans
```

### Tags
| Tag | What runs |
|---|---|
| base / hostname / banner | base role / hostname+services / MOTD only |
| ssh, security | SSH role (security also includes acl) |
| ntp_syslog / ntp / syslog | NTP + syslog / NTP only / syslog only |
| vlans | VLAN gateway subinterfaces |
| ospf, routing | OSPF role |
| acl | ACL role |
| verify | the post-change assertions inside ssh/ospf/acl |
| backup | backup role (backup.yml / monitoring.yml) |
| interfaces, routing, vlans, acl, resources (cpu, memory), connectivity, inventory | individual checks in monitoring.yml |

### Handlers
Every configuration task notifies `save config`. The handler runs `write memory` **once per
router at the end of the play, and only if something changed**; a second listener appends a
line to `reports/change_log.csv`. On an idempotent re-run nothing changes, so no handler fires.

On the first live run the handler timed out (90 s) on HQ-CORE and HQ-DIST: their NVRAM had been
written by a different IOS image, so `write memory` stopped at
`Overwrite the previous NVRAM configuration?[confirm]`. The handler (and `save.yml`) now pass
that prompt with `prompt:`/`answer:` in `ios_command`, and `save.yml` was used to save those two
routers.

## Idempotence notes
Templates render lines exactly as IOS prints them in `show running-config` (for example
`logging 10.20.30.12`, not `logging host ...`, and `deny   ip any any` with three spaces), so
`ios_config` compares like with like and a second run reports `changed=0`.

## Scope and safety
The playbooks enforce the values Part A already deployed (hostnames, NTP 10.20.30.11,
syslog 10.20.30.12, banner, SSH, OSPF, VLAN gateways, ACL_VTY). The Part A data-plane ACLs
(ACL_OUTSIDE_IN, ACL_DMZ_IN, ACL_GUEST, ACL_DC_IN), NAT and DHCP are **verified** by the
monitoring role but not rewritten by it.

## Recorded results (27 Sep 2026, control node AUTO-SRV)
- `site.yml` first run: changed=2-5 per router (VLAN descriptions, SSH timers/VTY exec-timeout,
  ACL_MGMT, `service password-encryption` drift on FW-EDGE); handler saved DC-EDGE, BR-EDGE,
  FW-EDGE and timed out on HQ-CORE/HQ-DIST (see Handlers) - fixed, then saved with `save.yml`.
- `site.yml` re-run: changed=0 failed=0 on all five routers (idempotent, no handlers).
- Drift test: `no logging 10.20.30.12` pushed ad hoc to HQ-CORE; `site.yml --tags ntp,syslog`
  restored it (HQ-CORE changed=2: syslog task + handler log) and saved the config.
- `monitoring.yml`: failed=0; 5 backups, 3/1/2/1/1 FULL OSPF neighbours as expected, 7 VLAN
  gateways up/up, ACL_VTY on every VTY, CPU 5-min 3-6 %, memory 27-34 %, all pings 100 %.
  HQ-CORE Fa3/0 (backup WAN, no cable in the topology) is reported as addressed-but-down.

## Outputs
- `backups/<host>_<YYYY-MM-DD>.cfg`, `reports/backup_index.csv`
- `reports/<check>/<host>.txt` raw device output per check
- `reports/{interfaces,routing,vlans,acl,resources,connectivity}_summary.csv`, `reports/inventory_report.csv`
- `reports/MONITORING_REPORT.md` consolidated report; `reports/change_log.csv` handler log
