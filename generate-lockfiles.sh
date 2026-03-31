#!/usr/bin/env bash
# Create package-lock.json in bad-app/ and good-app/ for reproducible Docker builds (npm ci).
# Requires Node/npm locally, or Docker with the node:18 image.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_in_dir() {
  local dir="$1"
  if command -v npm >/dev/null 2>&1; then
    (cd "${ROOT}/${dir}" && npm install --package-lock-only)
  elif command -v docker >/dev/null 2>&1; then
    docker run --rm -v "${ROOT}/${dir}:/app" -w /app node:18 npm install --package-lock-only
  else
    echo "Install Node.js (npm) or Docker, then re-run this script."
    exit 1
  fi
}

run_in_dir bad-app
run_in_dir good-app
echo "Lockfiles updated under bad-app/ and good-app/."
