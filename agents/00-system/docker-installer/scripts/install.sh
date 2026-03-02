#!/bin/bash
set -euo pipefail
curl -fsSL https://get.docker.com | sh
docker --version
docker compose version
