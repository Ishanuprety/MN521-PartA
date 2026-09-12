# MN521 Part A — Enterprise Network Design (GNS3)

MIT **MN521 Network Automation** — Part A deliverables for a three-site enterprise network (Headquarters,
Data Centre, Branch Office) built and verified in GNS3: topology, IP plan, device configurations,
infrastructure services, security policy, verification evidence and design justification.

The same four configuration files are the intended source of truth for Part B, where `AUTO-SRV` pushes them
with Ansible/Netmiko.

---

## 1. Repository layout

| Path | Contents |
|------|----------|
| [`docs/TOPOLOGY.md`](docs/TOPOLOGY.md) | Node inventory, mermaid diagram, routed/trunk/access link tables, GNS3 switch port matrix, traffic-flow summary |
| [`docs/IP_ADDRESSING.md`](docs/IP_ADDRESSING.md) | Authoritative addressing plan — sites, VLANs, WAN /30s, per-interface addresses, loopbacks |
| [`docs/DESIGN_JUSTIFICATION.md`](docs/DESIGN_JUSTIFICATION.md) | Why the design looks like this: architecture, platform choices on Apple silicon, routing, security, scalability analysis |
| [`docs/GNS3_BUILD_NOTES.md`](docs/GNS3_BUILD_NOTES.md) | For scripted/automated builds: how to drive the routers over console, the NAT and service gotchas, adapter/port mapping, and correct behaviour that looks like a fault |
| [`configs/*.cfg`](configs/) | Startup configurations for `HQ-CORE`, `HQ-DIST`, `DC-EDGE`, `BR-EDGE` |
| [`configs/linux/`](configs/linux/) | Idempotent setup scripts for the Docker nodes: `auto-srv`, `dns`, `ntp`, `syslog` |
| [`configs/vpcs/`](configs/vpcs/) | VPCS startup files for `PC1`–`PC4` |
| [`verification/CHECKS.md`](verification/CHECKS.md) | Step-by-step test plan with exact commands, expected output and a sign-off checklist |

## 2. What is deployed

- **4 routers** — Cisco c7200 (Dynamips): `HQ-CORE` (Internet edge, NAT/PAT), `HQ-DIST` (HQ inter-VLAN
  routing + DHCP), `DC-EDGE` (Data Centre gateway + WAN transit), `BR-EDGE` (Branch gateway + guest
  isolation)
- **6 switches** — GNS3 built-in Ethernet switches: `SW-HQ-1/2/3`, `SW-DC-1`, `SW-BR-1/2`
- **4 Docker service nodes** — `AUTO-SRV` (Ansible/Netmiko, `10.10.99.10`), `DNS` (`10.20.30.10`),
  `NTP` (`10.20.30.11`), `SYSLOG` (`10.20.30.12`)
- **4 VPCS hosts** — `PC1` (VLAN 10), `PC2` (VLAN 20), `PC3` (VLAN 40), `PC4` (VLAN 50 guest)
- **1 NAT cloud** — simulated Internet and upstream DHCP server for `HQ-CORE Fa0/0`
- **OSPF** process 1, area 0 backbone with areas 10 / 20 / 30 per site; **DHCP** from six IOS pools;
  **PAT** on `HQ-CORE`; **ACLs** for VTY control, guest isolation, management-VLAN isolation and edge
  anti-spoofing; **DNS / NTP / Syslog** in the Data Centre; domain `corp.local`

## 3. Prerequisites

| Item | Requirement |
|------|-------------|
| GNS3 | 2.2.x desktop client plus the GNS3 VM (allocate **4 GB RAM / 2 vCPU** minimum) |
| Host | Apple M3 or any 64-bit host; on Apple silicon the GNS3 VM runs under VMware Fusion or UTM |
| IOS image | `c7200-adventerprisek9-mz.15x-x.x.image` (Advanced Enterprise, IOS 15.x) |
| Docker image | `ubuntu:22.04` (arm64 on Apple silicon), pulled inside the GNS3 VM |
| Internet | required by the NAT cloud tests (§6 of `CHECKS.md`) and by the Linux setup scripts |

> **No Cisco IOS binary images are included in this repository.** Cisco IOS images are proprietary and
> cannot be redistributed. Obtain the c7200 image from your own licensed source or the unit's provided lab
> resources, and import it via **Edit → Preferences → Dynamips → IOS routers → New**.

## 4. Building the lab in GNS3

### 4.1 Create the router template

1. **Edit → Preferences → Dynamips → IOS routers → New**, select your c7200 image, and let GNS3 run
   **Idle-PC finder** — this is not optional. Without a calibrated idle-PC value each router will consume a
   full host core while idle and four routers will make the topology unusable.
2. Set **Name** to `c7200-MN521`, **RAM** to `256 MB`, and **NPE** to `npe-400`.
3. On the **Slots** tab, populate:
   - **slot 0** → `C7200-IO-FE` → provides `FastEthernet0/0`
   - **slot 1** → `PA-FE-TX` → provides `FastEthernet1/0`
   - **slot 2** → `PA-FE-TX` → provides `FastEthernet2/0`

   This slot layout is what makes the interface names in `configs/*.cfg` valid. The configurations use
   **FastEthernet only** — if you populate a Gigabit adapter instead, the interfaces in the configs will not
   exist and the files will appear to apply while doing nothing.

### 4.2 Place the nodes

Drag in 4 × `c7200-MN521`, 6 × **Ethernet switch**, 4 × **Docker `ubuntu:22.04`**, 4 × **VPCS**, and
1 × **NAT** cloud. Rename every node to match [`docs/TOPOLOGY.md`](docs/TOPOLOGY.md) §1 exactly — the
configurations, the link table and the verification steps all reference these names.

### 4.3 Configure the switch ports

For each Ethernet switch, open **Configure → Ports** and apply the VLAN/type matrix in
[`docs/TOPOLOGY.md`](docs/TOPOLOGY.md) §4. Trunk ports are type `dot1q`; host ports are type `access` on
their VLAN. Every data VLAN is carried **tagged** and VLAN 1 is left unused, so a port left at the default
`1 / access` is the single most likely cause of a host failing to get a DHCP lease.

### 4.4 Cable the topology

Create the links listed in [`docs/TOPOLOGY.md`](docs/TOPOLOGY.md) §3 (L1–L18). Do not add any extra
switch-to-switch link: the built-in Ethernet switch has no STP, so the topology is intentionally loop-free
and a redundant Layer 2 path would cause a broadcast storm.

### 4.5 Load the router configurations

Two ways, both valid.

**Option A — import as the startup config (recommended, survives a project reload):**

1. Right-click the router → **Configure** → **General settings** tab.
2. Next to **Startup-config**, click **Browse…** and select the matching file from `configs/`
   (`HQ-CORE.cfg` → `HQ-CORE`, and so on).
3. **Apply**, then **OK**. Repeat for all four routers, then start the nodes.

**Option B — paste into the console:**

1. Start the router, open its console, and press **Enter** past any setup dialog (answer `no` if prompted to
   enter the initial configuration dialog).
2. Enter `enable`, then `configure terminal`.
3. Paste the file contents. The files are ordered so that ACLs are defined before the interfaces and NAT
   statements that reference them, so a single top-to-bottom paste applies cleanly.
4. Exit to privileged mode and save: `end` then `write memory`.

Notes on the configuration files:

- They are **ASCII only** and contain no `GigabitEthernet` or non-existent slot references, so they replay
  without errors on Dynamips c7200.
- Each interface and each `line` range appears **exactly once** — there are no duplicate blocks to resolve.
- They contain **no `crypto key generate rsa`**, because that is an exec-mode command and cannot live in a
  startup config. SSH is otherwise fully configured; complete it with §5 below.

### 4.6 Configure the Docker service nodes

Start each container, open its console, and run the matching script from `configs/linux/`:

| Node | Script | Result |
|------|--------|--------|
| `AUTO-SRV` | `auto-srv-setup.sh` | `10.10.99.10/24`, Ansible + Netmiko + SSH client |
| `DNS` | `dns-setup.sh` | `10.20.30.10/24`, `dnsmasq` authoritative for `corp.local`, forwarding to `8.8.8.8` |
| `NTP` | `ntp-setup.sh` | `10.20.30.11/24`, `chrony` serving `10.0.0.0/8` as a `local stratum 10` source |
| `SYSLOG` | `syslog-setup.sh` | `10.20.30.12/24`, `rsyslog` listening on UDP and TCP 514 |

The scripts are idempotent, so re-running one after a container restart is safe. To copy a script in, paste
it into the container console with a heredoc, or mount the repository into the GNS3 VM and reference it from
the container's additional directories.

### 4.7 Configure the VPCS hosts

Each VPCS node reads its startup file from `configs/vpcs/`. Either point the node's **startup script** at
the matching file, or type the two lines into the VPCS console:

```
set pcname PC1
ip dhcp -r
```

All four hosts obtain their address, gateway, DNS server and NTP server (DHCP option 42) from the local
router — see `verification/CHECKS.md` §3.2 for the expected values.

### 4.8 Recommended boot order

Booting in dependency order avoids chasing symptoms that are really just startup races:

1. NAT cloud and all six Ethernet switches (instant, no boot time).
2. `HQ-CORE`, then `DC-EDGE`, `HQ-DIST`, `BR-EDGE`. Wait for each to reach the `Router>`/hostname prompt
   before starting the next — four simultaneous Dynamips boots will saturate the GNS3 VM's CPU.
3. `DNS`, `NTP`, `SYSLOG` (routers reference these, so they should be up before you check services).
4. `AUTO-SRV`, then `PC1`–`PC4`.

Allow **up to ~10 minutes** after boot for NTP synchronisation on emulated hardware before running
`CHECKS.md` §7.2.

---

## 5. Post-boot SSH enablement

The startup configurations set `ip domain-name corp.local`, `ip ssh version 2`, the SSH timeout and retry
limits, the local user database and `transport input ssh` with `access-class ACL_VTY in` on every VTY line.
The **only** remaining step is generating the RSA host key, which must be done from exec mode on each
router after it has booted — an RSA key pair cannot be created from a configuration file, and each device
must have its own unique key.

Run once per router, on the console:

```
enable
configure terminal
crypto key generate rsa modulus 2048 label SSH-KEY
end
write memory
```

If the router prompts `How many bits in the modulus [512]:`, enter `2048`. Key generation takes several
seconds on emulated MIPS hardware — this is expected.

Verify:

```
show crypto key mypubkey rsa
show ip ssh
```

`show ip ssh` must report `SSH Enabled - version 2.0` with `Authentication timeout: 60 secs` and
`Authentication retries: 2`. If it reports `SSH Disabled`, the key was not generated.

Then test from `AUTO-SRV` (the management VLAN is one of the two subnets `ACL_VTY` permits):

```
ssh -o StrictHostKeyChecking=no admin@10.255.0.9      # HQ-CORE
ssh -o StrictHostKeyChecking=no admin@1.1.1.4         # HQ-DIST loopback
```

An SSH attempt from any other subnet — for example `PC2` on VLAN 20 — is expected to be refused by
`ACL_VTY`, and the denial is logged to `10.20.30.12`. See `verification/CHECKS.md` §5.4.

> **If you rebuild the lab from the startup configs, the RSA keys are not restored.** Key material is not
> part of the configuration file, so §5 must be repeated on every fresh boot from `configs/*.cfg`. Saving the
> project after generating the keys preserves them in the router's NVRAM for subsequent project loads.

---

## 6. Credentials

| Purpose | Username | Password |
|---------|----------|----------|
| Console, SSH, and `enable` on all four routers | `admin` | `Cisco123!` |

> **Lab credentials only — not production values.** A single shared local account with a well-known password
> is used deliberately so that the configuration files are self-contained, reproducible by a marker, and
> reusable as Part B's Ansible inventory credentials. In a production deployment this account would be
> replaced by centralised AAA (TACACS+/RADIUS) with per-administrator accounts, the password would meet a
> length and complexity policy, and SSH public-key authentication would replace password authentication
> entirely. See [`docs/DESIGN_JUSTIFICATION.md`](docs/DESIGN_JUSTIFICATION.md) §5.1 for the management-plane
> controls that *are* implemented — source-restricted VTY access, session timeouts, disabled aux/HTTP
> management paths, and login/configuration audit logging exported off-box.
>
> `enable secret` and the `username … secret` are stored as IOS hashes, and `service password-encryption`
> covers the remaining type-7 strings, so no cleartext password appears in `show running-config` output.

---

## 7. Verifying the build

Work through [`verification/CHECKS.md`](verification/CHECKS.md) in order — interfaces, then OSPF, then DHCP,
then reachability, then security enforcement, then NAT, then services. Each check states the exact command,
where to run it, and the expected output; steps marked **[EVIDENCE]** are the ones worth capturing as
screenshots for submission. Section 8 of that document is a symptom-to-cause troubleshooting table, and
section 9 is an 18-item sign-off checklist covering every Part A requirement.
