#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Hooks and Linux 4.4 backports are tracked in this tree. Initialize the
# submodule at the recorded gitlink; do not run upstream setup.sh or repatch.
git submodule update --init KernelSU-Next
python3 scripts/verify-kernelsu-next.py
