# Notes for automated GNS3 builds

For an agent or script building this topology on a GNS3 host rather than clicking it together by hand.
Everything here is a consequence of how `configs/*.cfg` are written — none of it is guesswork about GNS3
itself. Authoritative tables live in [TOPOLOGY.md](TOPOLOGY.md); test expectations in
[../verification/CHECKS.md](../verification/CHECKS.md).

## 1. How to drive these routers programmatically

Four properties of the configs will break a naive automation script. All four are deliberate.

| Property | Consequence for a script | Where |
|----------|--------------------------|-------|
| `line console 0` has `login local` | The **console prompts for `Username:`** on a fresh boot from these configs. A script that expects to land straight at `Router>` will hang. Answer `admin` / `Cisco123!`. | all four `.cfg` |
| `banner login` is printed before the username prompt | Prompt-matching must tolerate two banners (login + MOTD) before the first prompt. | all four `.cfg` |
| `transport input ssh` on every VTY line | **Telnet to a router's VTY is refused.** Drive the devices over the GNS3 console port (telnet to the console TCP port the API returns for the node), not over VTY telnet. | all four `.cfg` |
| `ACL_VTY` permits only `10.10.99.0/24` and `10.20.30.0/24` | **SSH from the GNS3 host or the Mac is denied.** Only `AUTO-SRV` (`10.10.99.10`) and the DC server VLAN can SSH in. This is the intended control, not a bug — see `CHECKS.md` §5.4. | all four `.cfg` |

There is also a hard ordering constraint: the configs contain **no `crypto key generate rsa`**, because that
is an exec-mode command that cannot live in a startup config. Until it is run once per router, `show ip ssh`
reports `SSH Disabled` and every SSH attempt fails regardless of ACLs. Run it over the console after boot:

```
enable
configure terminal
crypto key generate rsa modulus 2048 label SSH-KEY
end
write memory
```

`logging synchronous` on the console is set precisely so that syslog output does not interleave with a
command a script is typing.

## 2. NAT bring-up

The single most likely failure, and it looks like a broken NAT cloud rather than an ACL problem:

> `ACL_INTERNET_IN` is applied inbound on `HQ-CORE Fa0/0` and its first entry is
> `deny ip 10.0.0.0 0.255.255.255 any log`. If this GNS3 installation's NAT cloud hands out addresses from
> inside `10.0.0.0/8` instead of the default `192.168.122.0/24`, that entry drops the **DHCP offer** and all
> PAT return traffic, so `Fa0/0` never gets an address. Fix by narrowing the rule to the three site blocks
> (`deny ip 10.10.0.0 0.0.255.255 any log` plus equivalents for `10.20.0.0/16` and `10.30.0.0/16`) rather
> than deleting it.

Check `show dhcp lease` on `HQ-CORE` first — if `Fa0/0` has no address, nothing else about NAT can pass.

Two more NAT-specific things worth asserting programmatically:

- `show ip nat statistics` must list **both** `FastEthernet1/0` and `FastEthernet2/0` under
  `Inside interfaces`. If only one is present, exactly one site will have Internet access — the classic
  half-working NAT symptom.
- `show ip nat translations` should show several inside-local addresses sharing **one** inside-global
  address. That is the proof of overload/PAT rather than one-to-one NAT.
- `ACL_NAT_INSIDE` deliberately excludes `10.255.0.0/24`, so WAN transit addresses are never translated.

## 3. DNS / NTP / Syslog bring-up

| Service | Expectation that surprises people | Detail |
|---------|-----------------------------------|--------|
| NTP | Routers report **stratum 11**, not 10 | `chrony` is configured as `local stratum 10`, so its clients are one level below. Synchronisation can take **up to ~10 minutes** on emulated hardware — polling `show ntp status` immediately after boot will show unsynchronised and that is not a failure. |
| Syslog | Message source addresses are the **loopbacks** (`1.1.1.1`, `1.1.1.4`, `2.2.2.2`, `3.3.3.3`), not the routers' LAN addresses | `logging source-interface Loopback0` is set on all four. A collector filter keyed on LAN subnets will see nothing. |
| DNS | Guest VLAN 50 **can** resolve but **cannot** ping the DNS server | `ACL_GUEST_IN` permits UDP/TCP 53 to `10.20.30.10` above its deny rules. So from `PC4`, `nslookup dns.corp.local 10.20.30.10` succeeds while `ping 10.20.30.10` fails. Both results are correct; see `CHECKS.md` §7.1. |
| all three | The `configs/linux/*.sh` scripts use `ip addr add … \|\| true` | They are idempotent and safe to re-run, but addresses are **not persistent across a container restart**. Re-run the script after restarting a Docker node. |

Every router already points at `10.20.30.10` (DNS), `10.20.30.11` (NTP) and `10.20.30.12` (syslog), so the
containers should be up before service checks run.

## 4. Correct behaviour that looks like a fault

Do not "fix" these — each is asserted as the expected result in `CHECKS.md`:

- **`HQ-DIST Fa2/0` is administratively down.** It is a documented reserved growth port, not a missed
  `no shutdown`.
- **VLAN 1 is unused and every data VLAN is tagged.** A GNS3 switch port left at the default `1 / access`
  is the usual cause of a host not getting a DHCP lease.
- **`PC1` cannot reach `10.10.99.x`.** `ACL_HQ_USERS_IN` isolates HQ users from the management VLAN.
- **`1.1.1.1/32` appears as `O` (intra-area) but `1.1.1.4/32` as `O IA`.** `HQ-CORE` puts its loopback in
  area 0; `HQ-DIST` puts its in area 10.
- **Only 3 OSPF adjacencies exist in total**, one per WAN /30. All LAN interfaces are passive by design.
- **DHCP leases start at `.21`** on every subnet, because `.1`–`.20` are excluded.

## 5. Interface to GNS3 adapter/port mapping

Needed to create links via the API. The c7200 slot layout is what makes the FastEthernet names in the
configs valid: **slot 0 = `C7200-IO-FE`, slot 1 = `PA-FE-TX`, slot 2 = `PA-FE-TX`**, NPE `npe-400`, and a
calibrated `idlepc`.

| Node type | IOS / device interface | `adapter_number` | `port_number` |
|-----------|------------------------|------------------|---------------|
| `dynamips` c7200 | `FastEthernet0/0` | 0 | 0 |
| `dynamips` c7200 | `FastEthernet1/0` | 1 | 0 |
| `dynamips` c7200 | `FastEthernet2/0` | 2 | 0 |
| `ethernet_switch` | port *n* | 0 | *n* |
| `docker` | `eth0` | 0 | 0 |
| `vpcs` | `e0` | 0 | 0 |
| `nat` | `nat0` | 0 | 0 |

Two GNS3 API details relevant to a builder script, both confirmed against the gns3-server 2.2 schemas:

- **Ethernet switch VLANs** are set through the node's `ports_mapping` array, where each entry needs `name`,
  `port_number` and `type` (`access`, `dot1q` or `qinq`), plus `vlan`. Trunk ports in this design are
  `dot1q`; host ports are `access` on their VLAN. The full matrix is `TOPOLOGY.md` §4.
- **Dynamips startup configs** can be supplied as a `startup_config_content` string on node create/update,
  so `configs/*.cfg` can be pushed without touching the GNS3 host filesystem.

Link list to build: `TOPOLOGY.md` §3 — L1–L4 routed, L5–L10 trunks, L11–L18 access. **Do not add any extra
switch-to-switch link**: the built-in Ethernet switch has no STP, so the design is intentionally loop-free
and a redundant Layer 2 path would cause a broadcast storm with nothing to block it.

## 6. Suggested bring-up order

Dependency order, so failures are attributable rather than startup races (expanded in the README):

1. NAT cloud and the six Ethernet switches — instant, no boot time.
2. `HQ-CORE`, then `DC-EDGE`, `HQ-DIST`, `BR-EDGE`, **one at a time**, waiting for each prompt. Four
   simultaneous Dynamips boots will saturate a 4 GB GNS3 VM.
3. `crypto key generate rsa` on each router (§1), then `write memory`.
4. `DNS`, `NTP`, `SYSLOG` containers and their setup scripts.
5. `AUTO-SRV`, then `PC1`–`PC4`.
6. Verify in the order given by `CHECKS.md`: interfaces → OSPF → DHCP → reachability → security → NAT →
   services. An OSPF fault invalidates every later reachability result, and a DHCP fault invalidates every
   host test.
