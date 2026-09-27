# Router configurations — moved

The five IOS startup configurations live one level up, in [`configs/`](../):

| Device | File |
|--------|------|
| `FW-EDGE` | [`configs/FW-EDGE.cfg`](../FW-EDGE.cfg) |
| `HQ-CORE` | [`configs/HQ-CORE.cfg`](../HQ-CORE.cfg) |
| `HQ-DIST` | [`configs/HQ-DIST.cfg`](../HQ-DIST.cfg) |
| `DC-EDGE` | [`configs/DC-EDGE.cfg`](../DC-EDGE.cfg) |
| `BR-EDGE` | [`configs/BR-EDGE.cfg`](../BR-EDGE.cfg) |

This directory previously held a byte-identical second copy of all five files.
Two copies of a configuration is a defect waiting to happen: `scripts/apply_on_mac.py`
uploads from `configs/<NAME>.cfg`, so an edit made only in this directory would be
documented in the report and never reach a router — and the report and the lab would
disagree without anything reporting an error.

The single source of truth is `configs/<NAME>.cfg`. Validate any change with:

```bash
python3 scripts/validate_configs.py
```
