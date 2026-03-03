#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/openclaw-1c-platform/openclaw-1c-platform.git"
REPO_DIR="/opt/openclaw/repo"

echo "[repository-manager] starting sync"

if [ -d "$REPO_DIR/.git" ]; then
  echo "[repository-manager] repo already exists at $REPO_DIR"
  CURRENT_URL="$(git -C "$REPO_DIR" remote get-url origin || true)"
  echo "[repository-manager] current origin: $CURRENT_URL"

  if [ "$CURRENT_URL" != "$REPO_URL" ]; then
    echo "[repository-manager] origin URL differs, skipping auto-sync"
    exit 0
  fi

  echo "[repository-manager] fetching latest changes (no rebase)"
  git -C "$REPO_DIR" fetch --all --prune
  # На бою можно добавить reset --hard по флагу окружения, сейчас — только fetch
else
  echo "[repository-manager] cloning fresh repo from $REPO_URL"
  git clone "$REPO_URL" "$REPO_DIR"
fi

echo "[repository-manager] sync completed"
