# VPCS endpoint configurations

Ten VPCS hosts. Every one takes its address, mask, gateway, DNS server and domain
name by **DHCP** from the router that owns its VLAN, so the DHCP requirement is
demonstrated end to end rather than asserted.

Each `PC*.txt` (and the identical `PC*.vpc`) contains exactly two commands:

```
set pcname PC1
dhcp
```

Load it as the node's startup script, or paste the two lines into the VPCS console.

## Endpoint map

| Host | VLAN | Subnet | Gateway | DHCP server | Switch / port | Represents |
|------|-----:|--------|---------|-------------|---------------|------------|
| `PC1` | 10 | `10.10.10.0/24` | `10.10.10.1` | `HQ-DIST` | `SW-HQ-1` Eth1 | HQ user |
| `PC5` | 10 | `10.10.10.0/24` | `10.10.10.1` | `HQ-DIST` | `SW-HQ-3` Eth1 | HQ user, second access switch |
| `PC2` | 20 | `10.10.20.0/24` | `10.10.20.1` | `HQ-DIST` | `SW-HQ-2` Eth1 | HQ corporate |
| `PC8` | 20 | `10.10.20.0/24` | `10.10.20.1` | `HQ-DIST` | `SW-HQ-4` Eth1 | HQ corporate, second access switch |
| `PC3` | 40 | `10.30.40.0/24` | `10.30.40.1` | `BR-EDGE` | `SW-BR-1` Eth1 | Branch staff |
| `PC7` | 40 | `10.30.40.0/24` | `10.30.40.1` | `BR-EDGE` | `SW-BR-1` Eth3 | Branch staff |
| `PC6` | 40 | `10.30.40.0/24` | `10.30.40.1` | `BR-EDGE` | `SW-BR-3` Eth1 | Branch staff, second access switch |
| `PC4` | 50 | `10.30.50.0/24` | `10.30.50.1` | `BR-EDGE` | `SW-BR-2` Eth1 | Branch **guest** — isolated |
| `PC9` | 50 | `10.30.50.0/24` | `10.30.50.1` | `BR-EDGE` | `SW-BR-4` Eth1 | Branch **guest** — isolated |
| `PC-DMZ` | 60 | `10.60.60.0/24` | `10.60.60.1` | `FW-EDGE` | `SW-DMZ-1` Eth3 | DMZ maintenance host |

## What to expect

Every subnet excludes `.1`–`.20`, so **leases start at `.21`**. Which host in a
VLAN gets `.21` and which gets `.22` depends on boot order, so the pass criterion
is a correct subnet, mask, gateway, DNS server and domain name — not a specific
host address.

Two hosts are expected to behave differently, and both differences are the design
working:

- **`PC4` and `PC9`** receive domain name `guest.corp.local` instead of
  `corp.local`, and a four-hour lease instead of two days. They are served by the
  dedicated guest scope on `BR-EDGE`. This is the client-side proof that scope
  separation works, visible in `show ip` without touching a router.
- **`PC-DMZ`** receives `dmz.corp.local` from `FW-EDGE`, not from a site router.

## Verifying from a VPCS console

```
show ip
ping 10.30.40.1
trace 10.20.30.13
```

`show ip` reports the address, mask, gateway, DNS server and domain name. It does
**not** show DHCP option 42 (the NTP server): VPCS neither requests nor displays
that option. Option 42 is configured in the IOS pools and is verified on the
router with `show ip dhcp pool` and in a packet capture on the access link — see
`verification/CHECKS.md` §4.

## Guest isolation is selective, not total

From `PC4` or `PC9`, expect name resolution against `10.20.30.10` to **succeed**
while `ping 10.20.30.10` **fails**. Both results are correct: `ACL_GUEST_IN` on
`BR-EDGE Fa3/0.50` permits UDP and TCP port 53 to that host above its deny
entries. That pair of results together is the evidence that the guest network is
restricted rather than simply broken.
