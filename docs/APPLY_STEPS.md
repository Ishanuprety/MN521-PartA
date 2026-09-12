# Apply steps (Mac / GNS3)

## 1. Sync pack onto Mac
Copy `/workspace/mn521-parta` (or `mn521-parta-deploy.tgz`) to the Mac, then:

```bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
cd /path/to/mn521-parta   # or /tmp/mn521-parta-clean/mn521-parta after extract
python3 scripts/apply_on_mac.py
```

Script will:
- Read password from `~/.config/GNS3/2.2/gns3_server.conf`
- Sync configs/docs into project `.../9c25a374-.../configs/`
- Mirror to `/tmp/mn521-parta-clean/mn521-parta/`
- Dump live `LINK_MAP_LIVE.md`
- Set c7200 slots 0–3 + RAM
- Apply ethernet_switch `ports_mapping`
- Upload/set Dynamips startup-configs
- Start FW-EDGE → HQ-CORE → DC-EDGE → HQ-DIST → BR-EDGE (sequential)

Set `START_ROUTERS=0` to skip boot.

## 2. After routers boot (console)
On each router console (`admin` / `Cisco123!`):

```
enable
configure terminal
crypto key generate rsa modulus 2048 label SSH-KEY
end
write memory
```

## 3. Docker hosts
Start DC servers first (DNS/NTP/Syslog), then FILE/MON, then DMZ WEB/APP, then JUMP/AUTO.
Run matching `configs/linux/*-setup.sh` inside each container.

## 4. VPCS
Start PC nodes; in console: `set pcname PCx` then `dhcp` (or load `configs/vpcs/*.txt`).

## Blockers known
- Box agent cannot reach `192.168.158.1:3080` — API apply must run on Mac.
- Shell `machineId` not available to executor subagent (commands stay on box).
- No invented ping/OSPF verification in this pack.
