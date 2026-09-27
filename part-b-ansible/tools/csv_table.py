#!/usr/bin/env python3
"""Print one or more CSV reports as aligned text tables: csv_table.py reports/x.csv [...]"""
import csv, sys
for path in sys.argv[1:]:
    rows = list(csv.reader(open(path)))
    if not rows:
        continue
    w = [max(len(r[i]) if i < len(r) else 0 for r in rows) for i in range(len(rows[0]))]
    print(f"== {path}")
    for n, r in enumerate(rows):
        print("  ".join(c.ljust(w[i]) for i, c in enumerate(r)).rstrip())
        if n == 0:
            print("  ".join("-" * x for x in w))
    print()
