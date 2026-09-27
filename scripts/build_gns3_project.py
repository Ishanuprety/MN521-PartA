#!/usr/bin/env python3
"""Create MN521-PartA GNS3 project via REST API. Safe to re-run: skips if project exists."""
import json, os, sys, time, urllib.error, urllib.request
from pathlib import Path

API = os.environ.get("GNS3_API", "http://127.0.0.1:3080/v2")
USER = os.environ.get("GNS3_USER", "admin")
PASS = os.environ.get("GNS3_PASS", "toNIXEzH8jberYQeAK4BugPGW0GtHCTgfCvEJ99zzsFrt9piSEDIk38OXUNmDKsC")
COMPUTE = "vm"

TEMPLATES = {
    "c7200": "cfec15c9-2323-4311-b629-281e7e452b7b",
    "ethernet_switch": "1966b864-93e7-32d5-965f-001384eec461",
    "vpcs": "19021f99-e36f-394d-b4a1-8aaa902ab9cc",
    "nat": "df8f4ea9-33b7-3e96-86a2-c39bc9bb649c",
    "auto_srv": "5ca1ad8b-36dc-40d4-a2a1-ae506443c00e",
    "dns": "8864ad96-1480-4d83-8ef3-c061a59a7033",
    "ntp": "20419aaa-2952-4dc9-803f-5f5a3a3698a0",
    "syslog": "48c9dd2a-442d-44e4-9bde-9cc6f0c3e8ac",
}

ROUTER_SLOTS = {
    "slot0": "C7200-IO-FE",
    "slot1": "PA-FE-TX",
    "slot2": "PA-FE-TX",
}
ROUTER_RAM = 384

# name, template_key, x, y, needs_router_props, slots_override
NODES = [
    # HQ left
    ("HQ-CORE", "c7200", -550, -80, True, None),
    ("HQ-DIST", "c7200", -350, 120, True, None),
    ("SW-HQ-1", "ethernet_switch", -450, 320, False, None),
    ("SW-HQ-2", "ethernet_switch", -250, 320, False, None),
    ("PC1", "vpcs", -520, 480, False, None),
    ("PC2", "vpcs", -180, 480, False, None),
    ("AUTO-SRV", "auto_srv", -450, 480, False, None),
    ("Internet-NAT", "nat", -700, -200, False, None),
    # DC center
    ("DC-EDGE", "c7200", 80, -40, True, None),
    ("SW-DC-1", "ethernet_switch", 50, 220, False, None),
    ("SW-DC-2", "ethernet_switch", 220, 220, False, None),
    ("DNS", "dns", -20, 400, False, None),
    ("NTP", "ntp", 100, 400, False, None),
    ("Syslog", "syslog", 220, 400, False, None),
    # BR right — BR-EDGE slots 0-1 only
    ("BR-EDGE", "c7200", 600, -20, True, {"slot0": "C7200-IO-FE", "slot1": "PA-FE-TX"}),
    ("SW-BR-1", "ethernet_switch", 550, 220, False, None),
    ("SW-BR-2", "ethernet_switch", 720, 220, False, None),
    ("PC3", "vpcs", 520, 400, False, None),
    ("PC4", "vpcs", 750, 400, False, None),
]

# Switch port mappings: name -> list of port dicts to merge/set
SWITCH_PORTS = {
    "SW-HQ-1": [
        {"name": "Ethernet0", "port_number": 0, "type": "dot1q", "vlan": 1},
        {"name": "Ethernet1", "port_number": 1, "type": "access", "vlan": 10},
        {"name": "Ethernet2", "port_number": 2, "type": "access", "vlan": 99},
        {"name": "Ethernet7", "port_number": 7, "type": "dot1q", "vlan": 1},
    ],
    "SW-HQ-2": [
        {"name": "Ethernet0", "port_number": 0, "type": "dot1q", "vlan": 1},
        {"name": "Ethernet1", "port_number": 1, "type": "access", "vlan": 20},
    ],
    "SW-DC-1": [
        {"name": "Ethernet0", "port_number": 0, "type": "dot1q", "vlan": 1},
        {"name": "Ethernet1", "port_number": 1, "type": "access", "vlan": 30},
        {"name": "Ethernet2", "port_number": 2, "type": "access", "vlan": 30},
        {"name": "Ethernet3", "port_number": 3, "type": "access", "vlan": 30},
        {"name": "Ethernet7", "port_number": 7, "type": "dot1q", "vlan": 1},
    ],
    "SW-DC-2": [
        {"name": "Ethernet0", "port_number": 0, "type": "dot1q", "vlan": 1},
    ],
    "SW-BR-1": [
        {"name": "Ethernet0", "port_number": 0, "type": "dot1q", "vlan": 1},
        {"name": "Ethernet1", "port_number": 1, "type": "access", "vlan": 40},
        {"name": "Ethernet7", "port_number": 7, "type": "dot1q", "vlan": 1},
    ],
    "SW-BR-2": [
        {"name": "Ethernet0", "port_number": 0, "type": "dot1q", "vlan": 1},
        {"name": "Ethernet1", "port_number": 1, "type": "access", "vlan": 50},
    ],
}

# links: (node_a, adapter_a, port_a, node_b, adapter_b, port_b)
# For dynamips FE: adapter = slot, port = 0 typically for single-port adapters
# C7200-IO-FE is slot0 port 0 = Fa0/0; PA-FE-TX slot1 = Fa1/0, slot2 = Fa2/0
LINKS = [
    ("HQ-CORE", 0, 0, "Internet-NAT", 0, 0),
    ("HQ-CORE", 1, 0, "DC-EDGE", 0, 0),
    ("HQ-CORE", 2, 0, "HQ-DIST", 0, 0),
    ("DC-EDGE", 1, 0, "BR-EDGE", 0, 0),
    ("HQ-DIST", 1, 0, "SW-HQ-1", 0, 0),
    ("SW-HQ-1", 0, 7, "SW-HQ-2", 0, 0),
    ("SW-HQ-1", 0, 1, "PC1", 0, 0),
    ("SW-HQ-2", 0, 1, "PC2", 0, 0),
    ("SW-HQ-1", 0, 2, "AUTO-SRV", 0, 0),
    ("DC-EDGE", 2, 0, "SW-DC-1", 0, 0),
    ("SW-DC-1", 0, 7, "SW-DC-2", 0, 0),
    ("SW-DC-1", 0, 1, "DNS", 0, 0),
    ("SW-DC-1", 0, 2, "NTP", 0, 0),
    ("SW-DC-1", 0, 3, "Syslog", 0, 0),
    ("BR-EDGE", 1, 0, "SW-BR-1", 0, 0),
    ("SW-BR-1", 0, 7, "SW-BR-2", 0, 0),
    ("SW-BR-1", 0, 1, "PC3", 0, 0),
    ("SW-BR-2", 0, 1, "PC4", 0, 0),
]

DRAWINGS = [
    # HQ blue zone
    {"svg": '<svg width="550" height="780"><rect width="550" height="780" fill="#4A90D9" fill-opacity="0.15" stroke="#4A90D9" stroke-width="3" rx="12"/></svg>', "x": -780, "y": -280, "z": -1},
    {"svg": '<svg width="200" height="40"><text x="10" y="28" font-family="Arial" font-size="22" font-weight="bold" fill="#1a5276">Headquarters (HQ)</text></svg>', "x": -760, "y": -270, "z": 1},
    # DC yellow
    {"svg": '<svg width="480" height="720"><rect width="480" height="720" fill="#F4D03F" fill-opacity="0.18" stroke="#B7950B" stroke-width="3" rx="12"/></svg>', "x": -120, "y": -220, "z": -1},
    {"svg": '<svg width="220" height="40"><text x="10" y="28" font-family="Arial" font-size="22" font-weight="bold" fill="#7D6608">Data Centre (DC)</text></svg>', "x": -100, "y": -210, "z": 1},
    # BR green
    {"svg": '<svg width="480" height="700"><rect width="480" height="700" fill="#58D68D" fill-opacity="0.15" stroke="#1E8449" stroke-width="3" rx="12"/></svg>', "x": 420, "y": -200, "z": -1},
    {"svg": '<svg width="240" height="40"><text x="10" y="28" font-family="Arial" font-size="22" font-weight="bold" fill="#145A32">Branch Office (BR)</text></svg>', "x": 440, "y": -190, "z": 1},
]

CONFIG_MAP = {
    "HQ-CORE": "HQ-CORE.cfg",
    "HQ-DIST": "HQ-DIST.cfg",
    "DC-EDGE": "DC-EDGE.cfg",
    "BR-EDGE": "BR-EDGE.cfg",
}

class Client:
    def __init__(self, base, user, password):
        self.base = base.rstrip("/")
        import base64
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.headers = {
            "Authorization": f"Basic {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    def request(self, method, path, data=None, raw=False):
        url = self.base + path
        body = None if data is None else (data if raw else json.dumps(data).encode())
        headers = dict(self.headers)
        if raw and data is not None:
            headers["Content-Type"] = "application/octet-stream"
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
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

    def patch(self, path, data=None):
        return self.request("PUT", path, data=data)  # GNS3 often uses PUT for updates


def main():
    errors = []
    c = Client(API, USER, PASS)
    print("GNS3 version:", c.get("/version"))
    projects = c.get("/projects")
    existing = [p for p in projects if p.get("name") == "MN521-PartA"]
    if existing:
        project = existing[0]
        print("Project already exists:", project["project_id"])
        # open it
        try:
            c.post(f"/projects/{project['project_id']}/open")
        except Exception as e:
            errors.append(f"open existing: {e}")
    else:
        # also guard against accidentally using 'group'
        if any(p.get("name") == "group" for p in projects):
            print("Note: existing 'group' project left untouched.")
        project = c.post("/projects", {"name": "MN521-PartA", "scene_width": 2400, "scene_height": 1400})
        print("Created project:", project["project_id"])

    pid = project["project_id"]
    try:
        c.post(f"/projects/{pid}/open")
    except Exception as e:
        errors.append(f"open: {e}")

    # Existing nodes
    nodes = {n["name"]: n for n in c.get(f"/projects/{pid}/nodes")}
    print("Existing nodes:", list(nodes))

    for name, tkey, x, y, is_router, slots_ov in NODES:
        if name in nodes:
            print(f"skip node {name}")
            continue
        payload = {
            "name": name,
            "template_id": TEMPLATES[tkey],
            "compute_id": COMPUTE,
            "x": x,
            "y": y,
        }
        # NAT may prefer local compute — try vm first, fall back
        try:
            node = c.post(f"/projects/{pid}/nodes", payload)
        except Exception as e:
            if tkey == "nat":
                payload["compute_id"] = "local"
                try:
                    node = c.post(f"/projects/{pid}/nodes", payload)
                except Exception as e2:
                    errors.append(f"create {name}: {e2}")
                    continue
            else:
                errors.append(f"create {name}: {e}")
                continue
        nodes[name] = node
        print(f"created {name} {node['node_id']}")

        if is_router:
            props = dict(node.get("properties") or {})
            slots = slots_ov or ROUTER_SLOTS
            props.update(slots)
            props["ram"] = ROUTER_RAM
            props["name"] = name
            try:
                updated = c.put(f"/projects/{pid}/nodes/{node['node_id']}", {
                    "name": name,
                    "properties": props,
                })
                nodes[name] = updated or c.get(f"/projects/{pid}/nodes/{node['node_id']}")
                print(f"  patched slots/ram for {name}")
            except Exception as e:
                errors.append(f"patch router {name}: {e}")

    # Refresh nodes
    nodes = {n["name"]: n for n in c.get(f"/projects/{pid}/nodes")}

    # Switch ports_mapping
    for sw_name, port_updates in SWITCH_PORTS.items():
        node = nodes.get(sw_name)
        if not node:
            errors.append(f"missing switch {sw_name}")
            continue
        props = dict(node.get("properties") or {})
        existing_pm = list(props.get("ports_mapping") or [])
        by_num = {p.get("port_number"): dict(p) for p in existing_pm}
        for pu in port_updates:
            cur = by_num.get(pu["port_number"], {})
            cur.update(pu)
            if "name" not in cur:
                cur["name"] = f"Ethernet{pu['port_number']}"
            by_num[pu["port_number"]] = cur
        # keep other ports
        for p in existing_pm:
            pn = p.get("port_number")
            if pn not in by_num:
                by_num[pn] = p
        new_pm = [by_num[k] for k in sorted(by_num)]
        try:
            c.put(f"/projects/{pid}/nodes/{node['node_id']}", {
                "properties": {"ports_mapping": new_pm}
            })
            print(f"ports_mapping set for {sw_name}")
        except Exception as e:
            errors.append(f"ports_mapping {sw_name}: {e}")

    # Links
    existing_links = c.get(f"/projects/{pid}/links")
    def link_key(link):
        nodes_l = link.get("nodes") or []
        parts = []
        for n in nodes_l:
            parts.append((n.get("node_id"), n.get("adapter_number"), n.get("port_number")))
        return tuple(sorted(parts))

    existing_keys = {link_key(l) for l in existing_links}
    created_links = 0
    for a, aa, ap, b, ba, bp in LINKS:
        na, nb = nodes.get(a), nodes.get(b)
        if not na or not nb:
            errors.append(f"link missing nodes {a}-{b}")
            continue
        key = tuple(sorted([(na["node_id"], aa, ap), (nb["node_id"], ba, bp)]))
        if key in existing_keys:
            print(f"skip link {a}-{b}")
            continue
        payload = {
            "nodes": [
                {"node_id": na["node_id"], "adapter_number": aa, "port_number": ap},
                {"node_id": nb["node_id"], "adapter_number": ba, "port_number": bp},
            ]
        }
        try:
            c.post(f"/projects/{pid}/links", payload)
            created_links += 1
            print(f"linked {a} ({aa}/{ap}) - {b} ({ba}/{bp})")
        except Exception as e:
            errors.append(f"link {a}-{b}: {e}")

    # Drawings
    existing_drawings = c.get(f"/projects/{pid}/drawings") or []
    if len(existing_drawings) < 3:
        for d in DRAWINGS:
            try:
                c.post(f"/projects/{pid}/drawings", d)
            except Exception as e:
                errors.append(f"drawing: {e}")
        print("drawings created")
    else:
        print("drawings already present:", len(existing_drawings))

    # Copy configs into project folder on disk + try API startup-config
    home = Path.home()
    # GNS3 project path discovery
    proj_paths = [
        home / "GNS3" / "projects" / "MN521-PartA",
        home / "GNS3" / "projects" / project.get("path", ""),
    ]
    # Also ask API
    try:
        full = c.get(f"/projects/{pid}")
        if full.get("path"):
            proj_paths.insert(0, Path(full["path"]))
            if not Path(full["path"]).is_absolute():
                proj_paths.insert(0, home / "GNS3" / "projects" / full["path"])
    except Exception as e:
        errors.append(f"get project path: {e}")

    proj_dir = None
    for p in proj_paths:
        if p and str(p) and p.exists():
            proj_dir = p
            break
    if proj_dir is None:
        # create under standard location
        proj_dir = home / "GNS3" / "projects" / "MN521-PartA"
        proj_dir.mkdir(parents=True, exist_ok=True)

    cfg_src = Path(os.environ.get("MN521_CONFIGS", str(Path(__file__).resolve().parents[1] / "configs")))
    docs_src = Path(os.environ.get("MN521_DOCS", str(Path(__file__).resolve().parents[1] / "docs")))
    cfg_dst = proj_dir / "configs"
    docs_dst = proj_dir / "docs"
    cfg_dst.mkdir(parents=True, exist_ok=True)
    docs_dst.mkdir(parents=True, exist_ok=True)

    import shutil
    for name, fname in CONFIG_MAP.items():
        src = cfg_src / fname
        if src.exists():
            shutil.copy2(src, cfg_dst / fname)
            print(f"copied {fname} -> {cfg_dst}")
        else:
            errors.append(f"missing config {src}")

    if docs_src.exists():
        for f in docs_src.iterdir():
            if f.is_file():
                shutil.copy2(f, docs_dst / f.name)
                print(f"copied doc {f.name}")

    # Try to upload startup configs via files API
    for name, fname in CONFIG_MAP.items():
        node = nodes.get(name)
        src = cfg_dst / fname
        if not node or not src.exists():
            continue
        content = src.read_bytes()
        # common dynamips paths
        candidates = [
            "configs/ios_startup-config.cfg",
            "startup-config.cfg",
            f"{name}_startup-config.cfg",
            "configs/startup-config.cfg",
        ]
        # discover via GET files if possible
        uploaded = False
        for rel in candidates:
            try:
                # POST /projects/{pid}/nodes/{nid}/files/{path}
                url_path = f"/projects/{pid}/nodes/{node['node_id']}/files/{rel}"
                c.request("POST", url_path, data=content, raw=True)
                print(f"uploaded startup config to {name}:{rel}")
                uploaded = True
                break
            except Exception:
                continue
        if not uploaded:
            # try setting property
            try:
                props = dict(node.get("properties") or {})
                props["startup_config"] = str(cfg_dst / fname)
                c.put(f"/projects/{pid}/nodes/{node['node_id']}", {"properties": props})
                print(f"set startup_config property for {name}")
            except Exception as e:
                errors.append(f"startup config {name}: {e}")

    # Final open
    try:
        c.post(f"/projects/{pid}/open")
    except Exception as e:
        errors.append(f"final open: {e}")

    final_nodes = c.get(f"/projects/{pid}/nodes")
    final_links = c.get(f"/projects/{pid}/links")
    summary = {
        "project_id": pid,
        "project_path": str(proj_dir),
        "node_count": len(final_nodes),
        "nodes": sorted([n["name"] for n in final_nodes]),
        "link_count": len(final_links),
        "errors": errors,
    }
    print(json.dumps(summary, indent=2))
    out = Path(__file__).resolve().parent / "build_report.json"
    out.write_text(json.dumps(summary, indent=2))
    return 0 if not errors else 1

if __name__ == "__main__":
    sys.exit(main())
