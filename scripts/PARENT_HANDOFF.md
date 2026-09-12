# Parent handoff — MN521-PartA config pack

## Executor status
- Full config pack written on box: `/workspace/mn521-parta/`
- **Cannot** call GNS3 API from box (192.168.158.1 unreachable).
- **Cannot** use Shell `machineId` from this executor (param ignored).

## Parent must run on Mac (machineId 4b0be088-7ca4-4473-9aab-6eb7e3ec3484)

```bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
# After CopyFromBox of tree or tarball:
mkdir -p /tmp/mn521-parta-clean
# extract or rsync pack to /tmp/mn521-parta-clean/mn521-parta
cd /tmp/mn521-parta-clean/mn521-parta
python3 scripts/apply_on_mac.py
```

Or point at project configs already synced:
`GNS3_PROJECT_PATH=/Users/reckless/GNS3/projects/9c25a374-f40d-4407-a6c8-4cd996d061d0`

## Key outputs
- `ROLE_MATRIX.md` — every node role
- `configs/{FW-EDGE,HQ-CORE,HQ-DIST,DC-EDGE,BR-EDGE}.cfg`
- `configs/switches/ports_mapping.json`
- `configs/linux/*-setup.sh` + `configs/netplan/*.yaml`
- `configs/vpcs/PC*.txt` + `PC-DMZ.txt`
- `docs/LINK_MAP.md`, `docs/APPLY_STEPS.md`, `docs/IP_ADDRESSING.md`
