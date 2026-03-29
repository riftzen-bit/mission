#!/usr/bin/env bash
set -euo pipefail

# Verify Python 3 is available
python3 --version > /dev/null 2>&1 || { echo "ERROR: python3 not found"; exit 1; }

# Ensure pytest is available for engine tests
python3 -c "import pytest" 2>/dev/null || python3 -m pip install pytest --quiet

echo "Environment ready: Python 3 + pytest available"
