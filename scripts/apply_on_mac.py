#!/usr/bin/env python3
"""MN521-PartA — apply config pack on Mac against live GNS3 API.

Run on machineId Mac:
  export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
  python3 scripts/apply_on_mac.py

Does NOT delete other projects. Starts routers one-at-a-time (4GB VM).
"""
from __future__ import annotations
import base64, json, os, re, shutil, sys, time, urllib.error, urllib.request
from pathlib import Path

PID = os.environ.get("GNS3_PROJECT_ID", "9c25a374-f40d-4407-a6c8-4cd996d061d0")
API = os.environ.get("GNS3_API", "http://127.0.0.1:3080/v2")
# Prefer 192.168.158.1 if local fails
API_FALLBACK = os.environ.get("GNS3_API_FALLBACK", "http://192.168.158.1:3080/v2")
USER = os.environ.get("GNS3_USER", "admin")
ROOT = Path(__file__).resolve().parents[1]
PROJ_PATH = Path(os.environ.get(
    "GNS3_PROJECT_PATH",
    "/Users/reckless/GNS3/projects/9c25a374-f40d-4407-a6c8-4cd996d061d0",
))
MIRROR = Path("/tmp/mn521-parta-clean/mn521-parta")

ROUTER_SLOTS = {
    "slot0": "C7200-IO-FE",
    "slot1": "PA-FE-TX",
    "slot2": "PA-FE-TX",
    "slot3": "PA-FE-TX",
}
ROUTER_RAM = int(os.environ.get("ROUTER_RAM", "256"))  # lean for 4GB VM
CONFIG_MAP = {
    "FW-EDGE": "FW-EDGE.cfg",
    "HQ-CORE": "HQ-CORE.cfg",
    "HQ-DIST": "HQ-DIST.cfg",
    "DC-EDGE": "DC-EDGE.cfg",
    "BR-EDGE": "BR-EDGE.cfg",
}
START_ORDER = ["FW-EDGE", "HQ-CORE", "DC-EDGE", "HQ-DIST", "BR-EDGE"]


def read_password() -> str:
    if os.environ.get("GNS3_PASS"):
        return os.environ["GNS3_PASS"]
    conf = Path.home() / ".config/GNS3/2.2/gns3_server.conf"
    text = conf.read_text()
    m = re.search(r"^password\s*=\s*(.+)$", text, re.M)
    if not m:
        raise SystemExit(f"No password in {conf}")
    return m.group(1).strip().strip('"').strip("'")


class Client:
    def __init__(self, base, user, password):
        self.base = base.rstrip("/")
        tok = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.headers = {
            "Authorization": f"Basic {tok}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    def request(self, method, path, data=None, raw=False, timeout=90):
        url = self.base + path
        body = None
        headers = dict(self.headers)
        if data is not None:
            if raw:
                body = data if isinstance(data, (bytes, bytearray)) else data.encode()
                headers["Content-Type"] = "application/octet-stream"
            else:
                body = json.dumps(data).encode()
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw_body = resp.read()
                if not raw_body:
                    return None
                try:
                    return json.loads(raw_body.decode())
                except Exception:
                    return raw_body
        except urllib.error.HTTPError as e:
            err = e.read().decode(errors="replace")
            raise RuntimeError(f"{method} {path} -> {e.code}: {err}") from e

    def get(self, path):
        return self.request("GET", path)

    def post(self, path, data=None, raw=False):
        return self.request("POST", path, data=data, raw=raw)

    def put(self, path, data=None):
        return self.request("PUT", path, data=data)


def connect(password: str) -> Client:
    for base in (API, API_FALLBACK):
        c = Client(base, USER, password)
        try:
            v = c.get("/version")
            print(f"Connected {base} version={v}")
            return c
        except Exception as e:
            print(f"API {base} failed: {e}")
    raise SystemExit("Cannot reach GNS3 API")


def dump_link_map(c: Client, pid: str, out: Path):
    nodes = {n["node_id"]: n for n in c.get(f"/projects/{pid}/nodes")}
    links = c.get(f"/projects/{pid}/links")
    rows = []
    for L in links:
        ends = []
        for e in L.get("nodes") or []:
            n = nodes[e["node_id"]]
            name = n["name"]
            nt = n.get("node_type")
            a, p = e["adapter_number"], e["port_number"]
            if nt == "dynamips":
                iface = f"Fa{a}/{p}"
            elif nt in ("ethernet_switch", "ethernet_hub"):
                iface = f"Eth{p}"
            elif nt == "nat":
                iface = f"nat{p}"
            elif nt == "cloud":
                iface = f"cloud{p}"
            elif nt == "docker":
                iface = f"eth{a}"
            elif nt == "vpcs":
                iface = f"e{a}"
            else:
                iface = f"a{a}/p{p}"
            ends.append({"name": name, "node_type": nt, "adapter": a, "port": p, "iface": iface})
        rows.append(ends)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"project_id": pid, "links": rows, "node_count": len(nodes), "link_count": len(links)}, indent=2))
    # markdown
    md = ["# Live LINK_MAP (API dump)", "", f"Nodes: {len(nodes)}  Links: {len(links)}", "",
          "| Node A | Iface | Node B | Iface |",
          "|--------|-------|--------|-------|"]
    for ends in rows:
        if len(ends) >= 2:
            md.append(f"| {ends[0]['name']} | {ends[0]['iface']} | {ends[1]['name']} | {ends[1]['iface']} |")
    (out.parent / "LINK_MAP_LIVE.md").write_text("\n".join(md))
    print(f"Wrote live link map {out} ({len(links)} links)")
    return nodes, links, rows


def sync_files():
    dst = PROJ_PATH / "configs"
    docs = PROJ_PATH / "docs"
    dst.mkdir(parents=True, exist_ok=True)
    docs.mkdir(parents=True, exist_ok=True)
    # copy tree
    for sub in ["", "routers", "switches", "linux", "vpcs", "netplan"]:
        sdir = ROOT / "configs" / sub if sub else ROOT / "configs"
        ddir = dst / sub if sub else dst
        ddir.mkdir(parents=True, exist_ok=True)
        if not sdir.exists():
            continue
        for f in sdir.iterdir():
            if f.is_file():
                shutil.copy2(f, ddir / f.name)
    for f in (ROOT / "docs").glob("*"):
        if f.is_file():
            shutil.copy2(f, docs / f.name)
    if (ROOT / "ROLE_MATRIX.md").exists():
        shutil.copy2(ROOT / "ROLE_MATRIX.md", PROJ_PATH / "ROLE_MATRIX.md")
        shutil.copy2(ROOT / "ROLE_MATRIX.md", docs / "ROLE_MATRIX.md")
    # mirror
    MIRROR.parent.mkdir(parents=True, exist_ok=True)
    if MIRROR.exists():
        # merge copy
        pass
    shutil.copytree(ROOT, MIRROR, dirs_exist_ok=True)
    print(f"Synced configs -> {dst} and mirror {MIRROR}")


def ensure_router_slots(c, pid, nodes_by_name):
    errors = []
    for name in CONFIG_MAP:
        n = nodes_by_name.get(name)
        if not n:
            errors.append(f"missing router {name}")
            continue
        props = dict(n.get("properties") or {})
        props.update(ROUTER_SLOTS)
        props["ram"] = ROUTER_RAM
        props["name"] = name
        try:
            c.put(f"/projects/{pid}/nodes/{n['node_id']}", {"name": name, "properties": props})
            print(f"slots/ram set for {name}")
        except Exception as e:
            errors.append(f"slots {name}: {e}")
    return errors


def apply_ports_mapping(c, pid, nodes_by_name):
    pm_path = ROOT / "configs" / "switches" / "ports_mapping.json"
    mapping = json.loads(pm_path.read_text())
    errors = []
    for sw_name, ports in mapping.items():
        n = nodes_by_name.get(sw_name)
        if not n:
            errors.append(f"missing switch {sw_name}")
            continue
        # Must stop? GNS3 often allows update while started for ethernet_switch
        try:
            c.put(f"/projects/{pid}/nodes/{n['node_id']}", {
                "properties": {"ports_mapping": ports}
            })
            print(f"ports_mapping OK {sw_name}")
        except Exception as e:
            # try stop-update-start
            try:
                c.post(f"/projects/{pid}/nodes/{n['node_id']}/stop")
                time.sleep(0.5)
                c.put(f"/projects/{pid}/nodes/{n['node_id']}", {
                    "properties": {"ports_mapping": ports}
                })
                c.post(f"/projects/{pid}/nodes/{n['node_id']}/start")
                print(f"ports_mapping OK (restarted) {sw_name}")
            except Exception as e2:
                errors.append(f"ports_mapping {sw_name}: {e2}")
    return errors


def upload_startup_configs(c, pid, nodes_by_name):
    errors = []
    for name, fname in CONFIG_MAP.items():
        n = nodes_by_name.get(name)
        src = ROOT / "configs" / fname
        if not n or not src.exists():
            errors.append(f"startup missing {name}")
            continue
        content = src.read_bytes()
        uploaded = False
        for rel in (
            "configs/ios_startup-config.cfg",
            "configs/startup-config.cfg",
            "startup-config.cfg",
            f"{name}_i1_startup-config.cfg",
        ):
            try:
                c.request("POST", f"/projects/{pid}/nodes/{n['node_id']}/files/{rel}", data=content, raw=True)
                print(f"uploaded {name} -> {rel}")
                uploaded = True
                break
            except Exception:
                continue
        if not uploaded:
            # property path on disk
            try:
                disk = str(PROJ_PATH / "configs" / fname)
                props = dict(n.get("properties") or {})
                props["startup_config"] = disk
                c.put(f"/projects/{pid}/nodes/{n['node_id']}", {"properties": props})
                print(f"set startup_config property {name} -> {disk}")
            except Exception as e:
                errors.append(f"startup {name}: {e}")
    return errors


def start_routers(c, pid, nodes_by_name):
    errors = []
    for name in START_ORDER:
        n = nodes_by_name.get(name)
        if not n:
            continue
        status = n.get("status")
        if status == "started":
            print(f"already started {name}")
            continue
        try:
            print(f"starting {name} ...")
            c.post(f"/projects/{pid}/nodes/{n['node_id']}/start")
            time.sleep(8)
        except Exception as e:
            errors.append(f"start {name}: {e}")
    return errors


def main():
    report = {"errors": [], "actions": []}
    password = read_password()
    sync_files()
    report["actions"].append("synced files to project + /tmp mirror")

    c = connect(password)
    try:
        c.post(f"/projects/{PID}/open")
    except Exception as e:
        report["errors"].append(f"open: {e}")

    nodes_list = c.get(f"/projects/{PID}/nodes")
    nodes_by_name = {n["name"]: n for n in nodes_list}
    print("Nodes:", sorted(nodes_by_name))

    live_dir = PROJ_PATH / "configs"
    _, _, _ = dump_link_map(c, PID, live_dir / "LINK_MAP_LIVE.json")
    # also to pack docs
    shutil.copy2(live_dir / "LINK_MAP_LIVE.json", ROOT / "docs" / "LINK_MAP_LIVE.json")
    if (live_dir / "LINK_MAP_LIVE.md").exists():
        shutil.copy2(live_dir / "LINK_MAP_LIVE.md", ROOT / "docs" / "LINK_MAP_LIVE.md")

    report["errors"] += ensure_router_slots(c, PID, nodes_by_name)
    # refresh
    nodes_by_name = {n["name"]: n for n in c.get(f"/projects/{PID}/nodes")}
    report["errors"] += apply_ports_mapping(c, PID, nodes_by_name)
    report["errors"] += upload_startup_configs(c, PID, nodes_by_name)

    if os.environ.get("START_ROUTERS", "1") == "1":
        report["errors"] += start_routers(c, PID, nodes_by_name)
    else:
        report["actions"].append("START_ROUTERS=0 skipped boot")

    report["node_count"] = len(nodes_by_name)
    report["link_count"] = len(c.get(f"/projects/{PID}/links"))
    report["routers"] = START_ORDER
    report["config_files"] = list(CONFIG_MAP.values())
    report["apply_blockers"] = [
        "crypto key generate rsa must be run once per router on console after first boot (not in startup-config)",
        "Console has login local — use admin/Cisco123!",
        "SSH VTY ACL only from 10.10.99.0/24 and 10.20.30.0/24 — push via GNS3 console/telnet to console port",
        "Do not start all docker nodes at once on 4GB VM",
        "L2 loops possible if SW-HQ-1↔SW-HQ-2 cross-link kept while both uplink to SW-HQ-DIST — consider deleting cross-links",
        "ISP-Cloud/WAN-Cloud: if still bypassed in live links, rewire Internet-NAT—ISP—FW and HQ Fa3/0—WAN—BR Fa2/0",
        "Docker IP/scripts not persistent across container restart — re-run configs/linux/*-setup.sh",
    ]
    out = PROJ_PATH / "configs" / "APPLY_REPORT.json"
    out.write_text(json.dumps(report, indent=2))
    (ROOT / "docs" / "APPLY_REPORT.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    return 0 if not report["errors"] else 1


if __name__ == "__main__":
    sys.exit(main())
