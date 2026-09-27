# Switch ports mapping — moved

The switch port/VLAN matrix is maintained next to the machine-readable file it
documents, so the two cannot drift apart:

- [`../configs/switches/PORTS_MAPPING.md`](../configs/switches/PORTS_MAPPING.md) — human-readable matrix
- [`../configs/switches/ports_mapping.json`](../configs/switches/ports_mapping.json) — applied to GNS3 via `scripts/apply_on_mac.py`

Switch roles in the wider topology are in [`TOPOLOGY.md`](TOPOLOGY.md) and
[`NODE_INVENTORY.md`](NODE_INVENTORY.md).
