#!/usr/bin/env bash
set -euo pipefail

if ! command -v nargo >/dev/null 2>&1; then
  echo "nargo is not installed"
  exit 1
fi

if ! command -v bb >/dev/null 2>&1; then
  echo "bb is not installed"
  exit 1
fi

nargo --version
bb --version
