#!/bin/bash
set -euo pipefail

echo "[portainer-installer] installing Portainer CE..."

docker volume create portainer_data >/dev/null 2>&1 || true
docker rm -f portainer >/dev/null 2>&1 || true

docker run -d \
  --name portainer \
  --restart unless-stopped \
  -p 9000:9000 \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest

echo "[portainer-installer] waiting for Portainer on http://localhost:9000..."
for i in {1..30}; do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9000 || true)
  if [[ "$code" =~ ^2|3 ]]; then
    echo "[portainer-installer] Portainer is up (HTTP $code)"
    exit 0
  fi
  sleep 2
done

echo "[portainer-installer] Portainer did not become ready in time"
exit 1
