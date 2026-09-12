#!/usr/bin/env python3
"""Static checks for the MN521 Part A IOS startup configurations.

These configurations are pasted into Dynamips c7200 routers or uploaded as
startup-config files, so a defect is not reported by a compiler - it either
silently does nothing or breaks the lab after boot. This script asserts the
properties that history shows actually go wrong, and is safe to run in CI.

Usage:  python3 scripts/validate_configs.py [configs/*.cfg]
Exit:   0 = all checks pass, 1 = at least one FAIL
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROUTERS = ["FW-EDGE", "HQ-CORE", "HQ-DIST", "DC-EDGE", "BR-EDGE"]

# Interfaces that legitimately exist on a c7200 with slots 0-3 populated as
# C7200-IO-FE + 3 x PA-FE-TX. Anything else is a config that will apply cleanly
# and then do nothing, which is the worst failure mode available.
VALID_IF = re.compile(r"^(FastEthernet[0-3]/0(\.\d+)?|Loopback\d+)$")

# Commands that cannot live in a startup configuration because they are
# exec-mode operations, not configuration.
EXEC_ONLY = ["crypto key generate", "write memory", "copy run", "reload"]


class Report:
    def __init__(self) -> None:
        self.fails: list[str] = []
        self.warns: list[str] = []

    def fail(self, dev: str, msg: str) -> None:
        self.fails.append(f"FAIL  {dev}: {msg}")

    def warn(self, dev: str, msg: str) -> None:
        self.warns.append(f"WARN  {dev}: {msg}")


def check(path: Path, rep: Report) -> None:
    dev = path.stem
    raw = path.read_bytes()

    # 1. ASCII only. A smart quote or en dash pasted into a console is silently
    #    mistranslated or rejected depending on the terminal.
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError as e:
        rep.fail(dev, f"non-ASCII byte at offset {e.start}: {raw[e.start:e.start+12]!r}")
        text = raw.decode("utf-8", "replace")

    lines = text.splitlines()
    body = [ln for ln in lines if not ln.lstrip().startswith("!")]

    # 2. Interface names must exist on this platform.
    interfaces: list[str] = []
    for ln in body:
        m = re.match(r"^interface (\S+)", ln)
        if m:
            name = m.group(1)
            interfaces.append(name)
            if not VALID_IF.match(name):
                rep.fail(dev, f"interface {name} does not exist on a c7200 slots 0-3")

    # 3. One block per interface. Duplicates apply in sequence and merge, which
    #    works by accident but makes the file impossible to template in Part B.
    for name in sorted(set(interfaces)):
        if interfaces.count(name) > 1:
            rep.fail(dev, f"interface {name} declared {interfaces.count(name)} times")

    # 4. One block per line range, for the same reason.
    lineblocks = re.findall(r"^line (.+)$", "\n".join(body), re.M)
    for lb in sorted(set(lineblocks)):
        if lineblocks.count(lb) > 1:
            rep.fail(dev, f"'line {lb}' declared {lineblocks.count(lb)} times")

    # 5. No exec-mode commands.
    for ln in body:
        for bad in EXEC_ONLY:
            if ln.strip().startswith(bad):
                rep.fail(dev, f"exec-mode command in startup config: {ln.strip()!r}")

    # 6. Every ACL referenced must be defined, and defined BEFORE its first use.
    #    A forward reference applies as an empty ACL, which on an interface means
    #    an implicit deny-all: total loss of traffic on that interface.
    defined: dict[str, int] = {}
    for i, ln in enumerate(body):
        m = re.match(r"^ip access-list (?:standard|extended) (\S+)", ln)
        if m:
            defined.setdefault(m.group(1), i)
    for i, ln in enumerate(body):
        m = re.search(r"(?:ip access-group|access-class|ip nat inside source list) (\S+)", ln)
        if not m:
            continue
        acl = m.group(1)
        if acl not in defined:
            rep.fail(dev, f"ACL {acl} referenced but never defined")
        elif defined[acl] > i:
            rep.fail(dev, f"ACL {acl} used on line {i} but defined later at {defined[acl]}")

    # 7. Every named ACL must end in an explicit entry, so the implicit deny is
    #    never what makes the policy decision and drops are always counted.
    for acl in defined:
        block = re.search(
            rf"^ip access-list (?:standard|extended) {re.escape(acl)}$(.*?)^\S",
            "\n".join(body) + "\n_",
            re.M | re.S,
        )
        if block and not re.search(r"^\s+(permit|deny)\s", block.group(1).rstrip().split("\n")[-1]):
            rep.warn(dev, f"ACL {acl} does not end in a permit/deny entry")

    # 8. Banner delimiters must be balanced or everything after the banner is
    #    swallowed into it.
    if text.count("^") % 2 != 0:
        rep.fail(dev, f"odd number of '^' banner delimiters ({text.count('^')})")

    # 9. Interfaces carrying an IP must be explicitly enabled or explicitly shut,
    #    never left to the platform default.
    cur, has_ip, decided = None, False, True
    for ln in body + ["interface SENTINEL0/0"]:
        m = re.match(r"^interface (\S+)", ln)
        if m:
            if cur and has_ip and not decided:
                rep.warn(dev, f"{cur} has an address but no explicit no shutdown/shutdown")
            cur, has_ip, decided = m.group(1), False, False
            # Loopbacks are up by default, and an 802.1Q subinterface follows the
            # admin state of its parent trunk - neither takes its own shutdown.
            if cur.startswith("Loopback") or "." in cur:
                decided = True
        elif cur:
            s = ln.strip()
            if s.startswith("ip address"):
                has_ip = True
            if s in ("no shutdown", "shutdown"):
                decided = True

    # 10. Consistency: the file's hostname must match its filename.
    hm = re.search(r"^hostname (\S+)$", text, re.M)
    if not hm:
        rep.fail(dev, "no hostname command")
    elif hm.group(1) != dev:
        rep.fail(dev, f"hostname {hm.group(1)} does not match filename {dev}")

    # 11. Security baseline the report claims for every device.
    required = {
        "ip ssh version 2": "SSHv2 not enforced",
        "transport input ssh": "VTY still accepts Telnet",
        "service password-encryption": "type-7 encryption not enabled",
        "logging host 10.20.30.12": "not exporting to the syslog collector",
        "ntp server 10.20.30.11": "no NTP client",
        "ip name-server 10.20.30.10": "no DNS resolver",
        "logging source-interface Loopback0": "syslog not sourced from Loopback0",
        "ip domain-lookup": "DNS resolution disabled - name lookups will fail",
    }
    for needle, why in required.items():
        if needle == "ip domain-lookup":
            # must be present AND not negated
            if re.search(r"^no ip domain-lookup$", text, re.M):
                rep.fail(dev, why)
                continue
        if needle not in text:
            rep.fail(dev, why)

    # 12. Both VTY ranges must be protected. Creating vty 5-15 and leaving it
    #     unguarded is the classic gap: the ACL looks applied and is bypassable.
    for rng in ("line vty 0 4", "line vty 5 15"):
        blk = re.search(rf"^{rng}$(.*?)(?=^\S|\Z)", text, re.M | re.S)
        if not blk:
            rep.fail(dev, f"{rng} not configured")
        elif "access-class ACL_VTY in" not in blk.group(1):
            rep.fail(dev, f"{rng} has no 'access-class ACL_VTY in'")


def main() -> int:
    args = sys.argv[1:]
    paths = [Path(a) for a in args] if args else [ROOT / "configs" / f"{r}.cfg" for r in ROUTERS]

    rep = Report()
    for p in paths:
        if not p.exists():
            rep.fail(p.stem, f"missing file {p}")
            continue
        check(p, rep)

    for line in rep.fails + rep.warns:
        print(line)

    checked = len([p for p in paths if p.exists()])
    print(f"\n{checked} config(s) checked: {len(rep.fails)} fail, {len(rep.warns)} warn")
    return 1 if rep.fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
