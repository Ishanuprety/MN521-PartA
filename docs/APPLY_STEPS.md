# Apply steps — GNS3 on the Mac

Everything in this repository is applied from the Mac running GNS3. A cloud agent
cannot reach the GNS3 API, so the API steps run locally.

> **Two remediation actions are mandatory before verification.** Step 2 (re-apply all
> five router configurations in one pass) and step 3 (delete three loop-closing links).
> Without them the lab does not match this repository, and one of the two defects can
> make the whole project unresponsive. See
> [`REVIEW_FINDINGS.md`](REVIEW_FINDINGS.md) R-01 and R-02.

---

## 0. Pre-flight, in the repository

```bash
python3 scripts/validate_configs.py     # IOS config structure and security baseline
python3 scripts/check_consistency.py    # docs tables agree with the configs
```

Both must exit `0`. Do not apply configurations that fail validation.

---

## 1. Sync the pack onto the Mac

```bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
cd /path/to/MN521-PartA
git checkout cursor/full-config-pack-marks
git pull
```

---

## 2. Re-apply all five router configurations — in one pass

```bash
python3 scripts/apply_on_mac.py
```

The script reads the API password from `~/.config/GNS3/2.2/gns3_server.conf`, syncs
`configs/` and `docs/` into the project directory, dumps a fresh `LINK_MAP_LIVE.md`,
sets c7200 slots 0–3 and RAM, applies the switch `ports_mapping`, uploads the
startup-configs, and starts the routers in order. `START_ROUTERS=0` skips the boot.

### Why this must be one pass, not device by device

Two changes in this revision are estate-wide:

1. **`HQ-CORE Fa0/0` is no longer a NAT/DHCP interface.** It is a routed
   `10.255.0.18/30` to `FW-EDGE`. A router still holding the superseded revision
   requests DHCP from a device that runs no DHCP server on that link, so the interface
   never binds and `HQ-CORE` is partitioned from the Internet edge — while four other
   adjacencies still look healthy. Confirm with:

   ```
   HQ-CORE# show running-config interface FastEthernet0/0
   ```

   It must show `10.255.0.18` and contain **no** `ip nat` command.

2. **OSPF area 0 now uses MD5 authentication.** Authentication must match on both ends
   of every backbone link, so applying it to some routers and not others drops those
   adjacencies until the rest catch up. Applying all five together keeps the outage to
   the reconvergence window.

If a backbone adjacency does not return, check both ends report message digest
authentication enabled:

```
show ip ospf interface FastEthernet<n> | include authentication
```

Rollback, if it is ever needed, is per router:

```
configure terminal
router ospf 1
 no area 0 authentication message-digest
end
```

---

## 3. Delete the three loop-closing links — in the GNS3 GUI

The GNS3 built-in Ethernet switch has **no spanning tree**. Three links in the current
topology each close a triangle with a site aggregation switch, and a Layer 2 loop here
presents as GNS3 becoming unresponsive rather than as an error.

| Delete this link | Loop it closes |
|------------------|----------------|
| `SW-HQ-1 Eth7` ↔ `SW-HQ-2 Eth0` | `SW-HQ-1` – `SW-HQ-2` – `SW-HQ-DIST` – `SW-HQ-1` |
| `SW-DC-1 Eth7` ↔ `SW-DC-2 Eth0` | `SW-DC-1` – `SW-DC-2` – `SW-DC-CORE` – `SW-DC-1` |
| `SW-BR-1 Eth7` ↔ `SW-BR-2 Eth0` | `SW-BR-1` – `SW-BR-2` – `SW-BR-DIST` – `SW-BR-1` |

Right-click each link → **Delete**. **Nothing is disconnected:** `SW-HQ-2` keeps its
uplink on `Eth2`, `SW-DC-2` on `Eth6` and `SW-BR-2` on `Eth6`, all to their aggregation
switch. The resulting tree is drawn in [`TOPOLOGY.md`](TOPOLOGY.md) §5.

Do **not** also remove the three shut router ports (`HQ-DIST Fa1/0`, `DC-EDGE Fa2/0`,
`BR-EDGE Fa1/0`). Those are pre-cabled standby paths, held administratively down, and
they address a different loop.

---

## 4. Generate the SSH host keys

`crypto key generate rsa` is an exec-mode command and cannot live in a startup
configuration, so it runs once per router after boot. Until it does, `show ip ssh`
reports `SSH Disabled` and every SSH attempt fails regardless of the ACLs.

On each of the five router consoles (`admin` / `Cisco123!`):

```
enable
configure terminal
crypto key generate rsa modulus 2048 label SSH-KEY
end
write memory
```

Key generation takes several seconds on emulated MIPS hardware — that is expected.
Verify with `show ip ssh`: `SSH Enabled - version 2.0`.

**Re-applying a startup config does not restore the keys**, because key material is not
part of the configuration. Repeat this step after any rebuild from `configs/*.cfg`.

### Driving the routers from a script

Four deliberate properties of these configurations will break a naive automation
script:

| Property | Consequence |
|----------|-------------|
| `login local` on `line console 0` | The console prompts for `Username:` on a fresh boot. A script expecting `Router>` will hang. Answer `admin` / `Cisco123!` |
| `banner login` plus `banner motd` | Prompt matching must tolerate two banners before the first prompt |
| `transport input ssh` on every VTY | Telnet to a VTY is refused. Drive the devices over the GNS3 console port, not over VTY telnet |
| `ACL_VTY` permits only two hosts plus `10.20.30.0/24` | SSH from the Mac or the GNS3 host is denied. Only `AUTO-SRV`, `JUMP-SRV` and the DC server VLAN can connect. This is the intended control, not a fault |

`logging synchronous` is set on the console specifically so syslog output does not
interleave with a command a script is typing.

---

## 5. Boot order

Dependency order, so a failure is attributable rather than a startup race:

1. **Switches, hubs and the NAT cloud** — instant, no boot time.
2. **Routers, one at a time**, waiting for each prompt: `FW-EDGE`, `HQ-CORE`,
   `DC-EDGE`, `HQ-DIST`, `BR-EDGE`. Five simultaneous Dynamips boots will saturate a
   4 GB GNS3 VM.
3. **`DNS`, `NTP`, `SYSLOG`** — every router points at these, so bring them up before
   checking services.
4. **`FILE-SRV`, `MON-SRV`**, then **`WEB-SRV`, `APP-SRV`**, then **`AUTO-SRV`,
   `JUMP-SRV`**.
5. **`PC1`–`PC9`, `PC-DMZ`**.

Allow **up to ~10 minutes** after boot for NTP synchronisation on emulated hardware
before running the time checks. Unsynchronised immediately after boot is expected.

---

## 6. Configure the nine Docker servers

In each container's console, run the one matching script. To see the mapping:

```bash
bash configs/linux/run-all-setup.sh          # lists node, address, VLAN, service, script
bash configs/linux/run-all-setup.sh dns      # runs dns-setup.sh
bash configs/linux/run-all-setup.sh --auto   # guesses from the container hostname
```

Every script is idempotent and ends with a self-check printing its address, its
listening socket and a live service probe — so a partial run is visibly different from
a successful one. Read that output rather than assuming success.

Addresses are **not** persistent across a container restart, because a GNS3 Docker node
does not keep filesystem changes outside its configured persistent directories.
Re-run the script after restarting a node. `configs/netplan/*.yaml` holds the
equivalent declarative configuration if you are using a persistent image instead.

---

## 7. Configure the ten VPCS endpoints

Point each node's startup script at `configs/vpcs/PC<n>.txt`, or type the two lines
into the console:

```
set pcname PC1
dhcp
```

All ten use DHCP. Expected results, including the deliberately different guest and DMZ
scopes, are in [`../configs/vpcs/README.md`](../configs/vpcs/README.md).

---

## 8. Verify

Work through [`../verification/CHECKS.md`](../verification/CHECKS.md) in order:
pre-flight → interfaces → VLANs → OSPF → DHCP → reachability → security → NAT →
services → resilience. An OSPF fault invalidates every later reachability result, and
a DHCP fault invalidates every host test.

Save screenshots as `report/figures/SS-nn-<slug>.png` using the names in `CHECKS.md`
§12, so the report picks them up without renaming.

---

## 9. Known constraints

- **No Cisco IOS image is in this repository.** IOS images are proprietary and cannot
  be redistributed. Supply your own c7200 image and run GNS3's Idle-PC calibration —
  without it each router consumes a full host core while idle and five routers make the
  project unusable.
- **Slots must be 0 = `C7200-IO-FE`, 1–3 = `PA-FE-TX`.** This is what makes the
  `FastEthernet0/0`–`Fa3/0` names in the configurations valid. A `GigabitEthernet`
  reference applies without error and does nothing.
- **A cloud agent cannot reach the GNS3 API.** Verified from the cloud VM: no route to
  `192.168.158.1:3080` or any other GNS3 endpoint. All API work runs on the Mac, either
  through `scripts/apply_on_mac.py` or a locally-run agent.
