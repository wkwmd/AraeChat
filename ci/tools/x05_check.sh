#!/usr/bin/env bash
set -euo pipefail

# Run generator
python3 ci/tools/gen_from_ssot.py

# Must be up-to-date
git diff --exit-code
