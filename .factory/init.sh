#!/usr/bin/env bash
set -euo pipefail

# Verify Python 3 is available
python3 --version > /dev/null 2>&1 || { echo "ERROR: python3 not found"; exit 1; }

# Create venv if needed and install pytest
VENV_DIR=".factory/.venv"
if [ ! -d "$VENV_DIR" ]; then
  python3 -m venv "$VENV_DIR"
fi

# Install pytest in venv if not present
"$VENV_DIR/bin/python" -c "import pytest" 2>/dev/null || "$VENV_DIR/bin/python" -m pip install pytest --quiet

echo "Environment ready: Python 3 + pytest available (venv: $VENV_DIR)"
