#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export GNS3_API="${GNS3_API:-http://127.0.0.1:3080/v2}"
export GNS3_USER="${GNS3_USER:-admin}"
export GNS3_PASS="${GNS3_PASS:-toNIXEzH8jberYQeAK4BugPGW0GtHCTgfCvEJ99zzsFrt9piSEDIk38OXUNmDKsC}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MN521_CONFIGS="$ROOT/configs"
export MN521_DOCS="$ROOT/docs"
python3 "$ROOT/scripts/build_gns3_project.py"
