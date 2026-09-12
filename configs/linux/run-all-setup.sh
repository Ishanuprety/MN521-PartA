#!/bin/bash
# Run inside each container (or via apply_on_mac.py docker helper)
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
echo "Scripts in $DIR:"
ls -1 "$DIR"/*-setup.sh
