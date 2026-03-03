#!/bin/bash
set -euo pipefail

REPO_URL="${OPENCLAW_REPO_URL:-https://github.com/rentonekb/openclaw-1c-platform.git}"
REPO_DIR="/opt/openclaw/repo"

echo "[repository-manager] starting sync"

if [ -d "$REPO_DIR/.git" ]; then
  echo "[repository-manager] repo already exists at $REPO_DIR"
  CURRENT_URL="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"

  echo "[repository-manager] fetching latest changes..."
  git -C "$REPO_DIR" fetch --all --prune
else
  echo "[repository-manager] cloning fresh repo from $REPO_URL"
  git clone "$REPO_URL" "$REPO_DIR"
fi

echo "[repository-manager] sync completed"
