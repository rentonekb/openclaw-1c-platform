#!/bin/bash
set -euo pipefail
REPO_URL="https://github.com/openclaw-1c-platform/openclaw-1c-platform.git"
REPO_DIR="/opt/openclaw/repo"
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --rebase
else
  git clone "$REPO_URL" "$REPO_DIR"
fi
