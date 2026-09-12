# Report tables

Machine-readable copies of the report's reference tables, for pasting into Word or
re-rendering without retyping.

| File | Rows | Contents |
|------|-----:|----------|
| `vlans.csv` | 8 | VLAN ID, name, subnet, gateway, gateway interface, router, zone, OSPF area, addressing method |
| `wan_links.csv` | 6 | Every WAN link with both interface addresses, transit segment, OSPF area and cost |
| `loopbacks.csv` | 5 | `Loopback0`, router ID, loopback area, OSPF role, and the five uses of the address |
| `dhcp_pools.csv` | 6 | All six pools with exclusions, gateway, DNS, domain, option 42 and lease |
| `acls.csv` | 8 | Every ACL, the device and interface it is applied to, direction and purpose |
| `hosts.csv` | 19 | All 9 servers and 10 endpoints: address, VLAN, gateway, switch port, service, config file |

## These are verified, not transcribed

`scripts/check_consistency.py` asserts that every address, pool name, ACL name and
file reference in these tables exists in the configuration it claims to describe:

```bash
python3 scripts/validate_configs.py && python3 scripts/check_consistency.py
```

Run both after editing either a table or a configuration. A report that disagrees with
the lab undermines all of its evidence, so the agreement is checked mechanically
rather than by eye.

## Pasting into Word

Word's **Data → Text to Columns** (or **Insert → Table → Convert Text to Table**) with
comma as the delimiter handles these directly. Set the resulting table to 9 pt so the
wider tables fit inside 2.54 cm margins — see [`../BUILD_DOCX.md`](../BUILD_DOCX.md) §2.

Two fields contain commas inside quotes (`acls.csv`, `purpose`), so use an import that
respects RFC 4180 quoting rather than a naive split on commas.

## Not included here

The 44-node inventory and the 50-link map are large and read better as prose tables
with their explanatory notes attached:

- [`../../docs/NODE_INVENTORY.md`](../../docs/NODE_INVENTORY.md) — every node's purpose, addressing and config artefact
- [`../../docs/TOPOLOGY.md`](../../docs/TOPOLOGY.md) §3 — the full link table, including the standby and loop-closing links
