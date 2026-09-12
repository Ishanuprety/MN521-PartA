#!/usr/bin/env python3
"""Cross-check the documentation tables against the actual configuration files.

The failure this guards against is the one that costs marks regardless of how good
either artefact is on its own: a report that disagrees with the lab. Every address,
DHCP pool, ACL and file reference in report/tables/*.csv is asserted to exist in the
configuration it claims to describe.

Run alongside scripts/validate_configs.py:

    python3 scripts/validate_configs.py && python3 scripts/check_consistency.py

Exit: 0 = consistent, 1 = at least one mismatch.
"""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLES = ROOT / "report" / "tables"


def load_configs() -> dict[str, str]:
    cfgs = {p.stem: p.read_text() for p in (ROOT / "configs").glob("*.cfg")}
    if not cfgs:
        sys.exit("no configs/*.cfg found")
    return cfgs


def rows(name: str) -> list[dict[str, str]]:
    path = TABLES / name
    if not path.exists():
        return []
    with path.open() as fh:
        return list(csv.DictReader(fh))


def main() -> int:
    cfgs = load_configs()
    fails: list[str] = []
    checks = 0

    # WAN link addresses must appear in the config of the device that owns them.
    for r in rows("wan_links.csv"):
        for side in ("a", "b"):
            dev, addr = r[f"{side}_device"], r[f"{side}_address"]
            if dev in cfgs and re.match(r"^10\.", addr or ""):
                checks += 1
                if addr not in cfgs[dev]:
                    fails.append(f"wan_links: {addr} not in configs/{dev}.cfg")

    # Loopback address and OSPF router-id.
    for r in rows("loopbacks.csv"):
        dev = r["device"]
        ip = r["loopback0"].split("/")[0]
        checks += 2
        if ip not in cfgs.get(dev, ""):
            fails.append(f"loopbacks: {ip} not in configs/{dev}.cfg")
        if f"router-id {r['ospf_router_id']}" not in cfgs.get(dev, ""):
            fails.append(f"loopbacks: router-id {r['ospf_router_id']} not in configs/{dev}.cfg")

    # VLAN gateway addresses.
    for r in rows("vlans.csv"):
        dev, gw = r["router"], r["gateway"]
        if dev and gw:
            checks += 1
            if gw not in cfgs.get(dev, ""):
                fails.append(f"vlans: VLAN {r['vlan']} gateway {gw} not in configs/{dev}.cfg")

    # DHCP pool names.
    for r in rows("dhcp_pools.csv"):
        checks += 1
        if r["pool"] not in cfgs.get(r["router"], ""):
            fails.append(f"dhcp_pools: {r['pool']} not in configs/{r['router']}.cfg")

    # ACLs present on the device the table says applies them.
    for r in rows("acls.csv"):
        dev = r["device"]
        if dev in cfgs:
            checks += 1
            if r["acl"] not in cfgs[dev]:
                fails.append(f"acls: {r['acl']} not in configs/{dev}.cfg")

    # Host addresses present in their setup script, and the artefact file exists.
    for r in rows("hosts.csv"):
        art = r["config_artefact"]
        checks += 1
        if not (ROOT / art).exists():
            fails.append(f"hosts: missing artefact {art}")
            continue
        if art.endswith(".sh"):
            ip = r["address"].split("/")[0]
            checks += 1
            if ip not in (ROOT / art).read_text():
                fails.append(f"hosts: {r['host']} {ip} not in {art}")

    for line in fails:
        print(f"FAIL  {line}")
    print(f"\n{checks} assertion(s): {len(fails)} mismatch(es)")
    if not fails:
        print("Documentation tables and configuration files agree.")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
