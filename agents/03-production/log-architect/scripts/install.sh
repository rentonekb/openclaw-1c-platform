#!/usr/bin/env bash
set -euo pipefail

setup_vector() {
  echo "[log-architect] deploying Vector..."
  VECTOR_CONFIG_DIR="/opt/openclaw/infra/vector"
  mkdir -p "$VECTOR_CONFIG_DIR"

  cat > "$VECTOR_CONFIG_DIR/vector.yaml" << 'YAML'
sources:
  filebeat_in:
    type: logstash
    address: 0.0.0.0:5044

transforms:
  parse_1c:
    type: remap
    inputs: ["filebeat_in"]
    source: |
      msg = if exists(.message) && .message != null { string(.message) ?? "" } else { null }

      parsed, err = if msg != null { parse_json(msg) } else { {}, "no message" }

      if err != null || msg == null {
        .event   = "UNKNOWN"
        .level   = "TRACE"
        .ts      = now()
        .raw     = msg ?? ""
      } else {
        .ts          = to_timestamp(parsed.time ?? now()) ?? now()
        .level       = upcase(string(parsed.level   ?? "TRACE") ?? "TRACE")
        .event       = upcase(string(parsed.name    ?? "UNKNOWN") ?? "UNKNOWN")
        .process     = string(parsed.process  ?? "") ?? ""
        .p_id        = to_int(parsed.p_id     ?? 0) ?? 0
        .t_id        = to_int(parsed.t_id     ?? 0) ?? 0
        .session     = to_int(parsed.Session  ?? 0) ?? 0
        .usr         = string(parsed.Usr      ?? "") ?? ""
        .db          = string(parsed.IB       ?? "") ?? ""
        .duration    = to_int(parsed.Duration ?? 0) ?? 0
        .memory      = to_int(parsed.Memory   ?? 0) ?? 0
        .memory_peak = to_int(parsed.MemoryPeak ?? 0) ?? 0
        .sql         = string(parsed.Sql      ?? "") ?? ""
        .context     = string(parsed.Context  ?? "") ?? ""
        .descr       = string(parsed.Descr    ?? "") ?? ""
        .raw         = msg ?? ""
      }

      .host     = if exists(.host) && is_object(.host) { string(.host.name) ?? "unknown" } else { "unknown" }
      .log_file = if exists(.log) && is_object(.log) && is_object(.log.file) { string(.log.file.path) ?? "" } else { "" }

sinks:
  clickhouse_out:
    type: clickhouse
    inputs: ["parse_1c"]
    endpoint: "http://clickhouse:8123"
    database: "openclaw"
    table: "techlog_1c"
    compression: gzip
    batch:
      max_bytes: 10485760
      timeout_secs: 5
    buffer:
      type: disk
      max_size: 268435456
      when_full: block
YAML

  cat > "/opt/openclaw/infra/docker-compose.vector.yml" << 'YAML'
services:
  vector:
    image: timberio/vector:0.42.0-distroless-libc
    container_name: vector
    restart: unless-stopped
    volumes:
      - /opt/openclaw/infra/vector/vector.yaml:/etc/vector/vector.yaml:ro
      - vector_buffer:/var/lib/vector
    ports:
      - "5044:5044"
    environment:
      - VECTOR_LOG=info
    extra_hosts:
      - "clickhouse:192.168.88.36"

volumes:
  vector_buffer:
    driver: local
YAML

  if docker ps --filter name=vector --format '{{.Names}}' | grep -q vector; then
    echo "[log-architect] Vector already running, recreating..."
    docker compose -f /opt/openclaw/infra/docker-compose.vector.yml up -d --force-recreate
  else
    echo "[log-architect] starting Vector..."
    docker compose -f /opt/openclaw/infra/docker-compose.vector.yml up -d
  fi

  for i in {1..30}; do
    if docker ps --filter name=vector --format '{{.Names}}' | grep -q vector; then
      echo "[log-architect] Vector is up"
      return 0
    fi
    sleep 2
  done
  echo "[log-architect] Vector failed to start"
  return 1
}
