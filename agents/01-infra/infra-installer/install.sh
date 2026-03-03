#!/bin/bash
set -euo pipefail

echo "[infra-installer] deploying infrastructure services..."

network="openclaw-net"
if ! docker network inspect "$network" >/dev/null 2>&1; then
  docker network create "$network"
fi

deploy_clickhouse() {
  echo "[infra-installer] deploying ClickHouse..."
  docker rm -f clickhouse >/dev/null 2>&1 || true
  docker volume create clickhouse_data >/dev/null 2>&1 || true

  docker run -d \
    --name clickhouse \
    --restart unless-stopped \
    --network "$network" \
    -p 8123:8123 \
    -p 9009:9009 \
    -v clickhouse_data:/var/lib/clickhouse \
    clickhouse/clickhouse-server:latest

  echo "[infra-installer] waiting for ClickHouse on http://localhost:8123/ping..."
  for i in {1..60}; do
    code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8123/ping || true)
    if [[ "$code" =~ ^2|3 ]]; then
      echo "[infra-installer] ClickHouse is up (HTTP $code)"
      return 0
    fi
    sleep 2
  done
  echo "[infra-installer] ClickHouse did not become ready in time"
  return 1
}

deploy_grafana() {
  echo "[infra-installer] deploying Grafana..."
  docker rm -f grafana >/dev/null 2>&1 || true
  docker volume create grafana_data >/dev/null 2>&1 || true

  docker run -d \
    --name grafana \
    --restart unless-stopped \
    --network "$network" \
    -p 3000:3000 \
    -v grafana_data:/var/lib/grafana \
    grafana/grafana-oss:latest

  echo "[infra-installer] waiting for Grafana on http://localhost:3000/api/health..."
  for i in {1..60}; do
    code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health || true)
    if [[ "$code" =~ ^2|3 ]]; then
      echo "[infra-installer] Grafana is up (HTTP $code)"
      return 0
    fi
    sleep 2
  done
  echo "[infra-installer] Grafana did not become ready in time"
  return 1
}

deploy_postgres() {
  echo "[infra-installer] deploying PostgreSQL..."
  docker rm -f postgresql >/dev/null 2>&1 || true
  docker volume create postgres_data >/dev/null 2>&1 || true

  POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-openclaw}"
  docker run -d \
    --name postgresql \
    --restart unless-stopped \
    --network "$network" \
    -p 5432:5432 \
    -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    -v postgres_data:/var/lib/postgresql/data \
    postgres:16

  echo "[infra-installer] waiting for PostgreSQL (port 5432)..."
  for i in {1..60}; do
    if docker exec postgresql pg_isready -U postgres >/dev/null 2>&1; then
      echo "[infra-installer] PostgreSQL is up"
      return 0
    fi
    sleep 2
  done
  echo "[infra-installer] PostgreSQL did not become ready in time"
  return 1
}

deploy_gitlab() {
  echo "[infra-installer] deploying GitLab (CE)..."
  docker rm -f gitlab >/dev/null 2>&1 || true
  docker volume create gitlab_config >/dev/null 2>&1 || true
  docker volume create gitlab_logs >/dev/null 2>&1 || true
  docker volume create gitlab_data >/dev/null 2>&1 || true

  docker run -d \
    --name gitlab \
    --restart unless-stopped \
    --network "$network" \
    -p 8080:80 \
    -p 2222:22 \
    -v gitlab_config:/etc/gitlab \
    -v gitlab_logs:/var/log/gitlab \
    -v gitlab_data:/var/opt/gitlab \
    gitlab/gitlab-ce:latest

  echo "[infra-installer] GitLab is heavy, waiting on http://localhost:8080/..."
  for i in {1..120}; do
    code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ || true)
    if [[ "$code" =~ ^2|3 ]]; then
      echo "[infra-installer] GitLab is up (HTTP $code)"
      return 0
    fi
    sleep 5
  done
  echo "[infra-installer] GitLab did not become ready in time"
  return 1
}

deploy_sonarqube() {
  echo "[infra-installer] deploying SonarQube..."
  docker rm -f sonarqube >/dev/null 2>&1 || true
  docker volume create sonarqube_data >/dev/null 2>&1 || true
  docker volume create sonarqube_extensions >/dev/null 2>&1 || true

  docker run -d \
    --name sonarqube \
    --restart unless-stopped \
    --network "$network" \
    -p 9001:9000 \
    -v sonarqube_data:/opt/sonarqube/data \
    -v sonarqube_extensions:/opt/sonarqube/extensions \
    sonarqube:latest

  echo "[infra-installer] waiting for SonarQube on http://localhost:9001/..."
  for i in {1..90}; do
    code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9001/ || true)
    if [[ "$code" =~ ^2|3 ]]; then
      echo "[infra-installer] SonarQube is up (HTTP $code)"
      return 0
    fi
    sleep 5
  done
  echo "[infra-installer] SonarQube did not become ready in time"
  return 1
}

deploy_nexus() {
  echo "[infra-installer] deploying Nexus..."
  docker rm -f nexus >/dev/null 2>&1 || true
  docker volume create nexus_data >/dev/null 2>&1 || true

  docker run -d \
    --name nexus \
    --restart unless-stopped \
    --network "$network" \
    -p 8081:8081 \
    -v nexus_data:/nexus-data \
    sonatype/nexus3:latest

  echo "[infra-installer] waiting for Nexus on http://localhost:8081/..."
  for i in {1..90}; do
    code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/ || true)
    if [[ "$code" =~ ^2|3 ]]; then
      echo "[infra-installer] Nexus is up (HTTP $code)"
      return 0
    fi
    sleep 5
  done
  echo "[infra-installer] Nexus did not become ready in time"
  return 1
}

deploy_clickhouse
deploy_grafana
deploy_postgres
deploy_gitlab || true       # не блокируем всю фазу, GitLab может долго подниматься
deploy_sonarqube || true
deploy_nexus || true

echo "[infra-installer] infrastructure deployment finished"
