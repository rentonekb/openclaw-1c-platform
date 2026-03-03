#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(dirname "$SCRIPT_DIR")"

echo "[log-architect] starting..."

# ── 1. ClickHouse схема ───────────────────────────────────────────────────────
setup_clickhouse() {
  echo "[log-architect] creating ClickHouse schema..."

  execute_ch() {
    curl -sf "http://localhost:8123/?user=openclaw&password=openclaw2026" \
      --data "$1" \
      -o /dev/null
  }

  execute_ch "CREATE DATABASE IF NOT EXISTS openclaw"

  execute_ch "
  CREATE TABLE IF NOT EXISTS openclaw.techlog_1c
  (
    received_at  DateTime DEFAULT now(),
    host         LowCardinality(String),
    log_file     String,
    ts           DateTime64(6),
    level        LowCardinality(String),
    event        LowCardinality(String),
    process      LowCardinality(String),
    p_id         UInt32,
    t_id         UInt64,
    session      UInt64,
    usr          String,
    db           LowCardinality(String),
    duration     UInt64,
    memory       UInt64,
    memory_peak  UInt64,
    sql          String,
    context      String,
    descr        String,
    raw          String
  )
  ENGINE = MergeTree()
  PARTITION BY toYYYYMM(ts)
  ORDER BY (event, ts)
  TTL toDateTime(ts) + INTERVAL 90 DAY
  SETTINGS index_granularity = 8192"

  echo "[log-architect] ClickHouse schema OK"
}

# ── 2. Vector ─────────────────────────────────────────────────────────────────
setup_vector() {
  echo "[log-architect] deploying Vector..."

  VECTOR_CONFIG_DIR="/opt/openclaw/infra/vector"
  mkdir -p "$VECTOR_CONFIG_DIR"

  cat > "$VECTOR_CONFIG_DIR/vector.toml" << 'TOML'
[sources.filebeat_in]
type = "logstash"
address = "0.0.0.0:5044"

[transforms.parse_1c]
type = "remap"
inputs = ["filebeat_in"]
source = '''
parsed, err = parse_json(.message)
if err != null {
  .event   = "UNKNOWN"
  .level   = "TRACE"
  .ts      = now()
  .raw     = string(.message) ?? ""
} else {
  .ts          = to_timestamp(parsed.time ?? now()) ?? now()
  .level       = upcase(string(parsed.level   ?? "TRACE"))
  .event       = upcase(string(parsed.name    ?? "UNKNOWN"))
  .process     = string(parsed.process  ?? "")
  .p_id        = to_int(parsed.p_id     ?? 0) ?? 0
  .t_id        = to_int(parsed.t_id     ?? 0) ?? 0
  .session     = to_int(parsed.Session  ?? 0) ?? 0
  .usr         = string(parsed.Usr      ?? "")
  .db          = string(parsed.IB       ?? "")
  .duration    = to_int(parsed.Duration ?? 0) ?? 0
  .memory      = to_int(parsed.Memory   ?? 0) ?? 0
  .memory_peak = to_int(parsed.MemoryPeak ?? 0) ?? 0
  .sql         = string(parsed.Sql      ?? "")
  .context     = string(parsed.Context  ?? "")
  .descr       = string(parsed.Descr    ?? "")
  .raw         = string(.message) ?? ""
}
.host     = string(.host.name ?? "unknown")
.log_file = string(.log.file.path ?? "")
'''

[sinks.clickhouse_out]
type     = "clickhouse"
inputs   = ["parse_1c"]
endpoint = "http://clickhouse:8123"
database = "openclaw"
table    = "techlog_1c"
compression = "gzip"

[sinks.clickhouse_out.batch]
max_bytes    = 10485760
timeout_secs = 5

[sinks.clickhouse_out.buffer]
type      = "disk"
max_size  = 268435456
when_full = "block"
TOML

  # docker-compose для Vector
  cat > "/opt/openclaw/infra/docker-compose.vector.yml" << 'YAML'
services:
  vector:
    image: timberio/vector:0.42.0-distroless-libc
    container_name: vector
    restart: unless-stopped
    volumes:
      - /opt/openclaw/infra/vector/vector.toml:/etc/vector/vector.toml:ro
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

  # Запуск
  if docker ps --filter name=vector --format '{{.Names}}' | grep -q vector; then
    echo "[log-architect] Vector already running, recreating..."
    docker compose -f /opt/openclaw/infra/docker-compose.vector.yml up -d --force-recreate
  else
    echo "[log-architect] starting Vector..."
    docker compose -f /opt/openclaw/infra/docker-compose.vector.yml up -d
  fi

  # Ждём запуска
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

# ── 3. Grafana datasource + dashboard ────────────────────────────────────────
setup_grafana() {
  echo "[log-architect] provisioning Grafana..."

  GRAFANA_URL="http://localhost:3000"
  AUTH="admin:admin"

  # Datasource ClickHouse
  DS_PAYLOAD='{
    "name": "ClickHouse-OpenClaw",
    "type": "grafana-clickhouse-datasource",
    "url": "http://clickhouse:8123",
    "access": "proxy",
    "isDefault": false,
    "jsonData": {
      "defaultDatabase": "openclaw",
      "server": "clickhouse",
      "port": 8123,
      "username": "default",
      "tlsSkipVerify": true
    }
  }'

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X GET "$GRAFANA_URL/api/datasources/name/ClickHouse-OpenClaw" \
    -u "$AUTH")

  if [ "$HTTP_CODE" = "200" ]; then
    echo "[log-architect] Grafana datasource already exists"
  else
    curl -sf -X POST "$GRAFANA_URL/api/datasources" \
      -H "Content-Type: application/json" \
      -u "$AUTH" \
      -d "$DS_PAYLOAD" > /dev/null
    echo "[log-architect] Grafana datasource created"
  fi

  echo "[log-architect] Grafana provisioning OK"
}

# ── Генерация filebeat.yml для Windows ───────────────────────────────────────
generate_filebeat_config() {
  echo "[log-architect] generating Windows configs..."
  mkdir -p /opt/openclaw/output/windows-configs

  VECTOR_HOST="${VECTOR_HOST:-192.168.88.36}"

  cat > /opt/openclaw/output/windows-configs/filebeat.yml << FILEBEAT
filebeat.inputs:
  - type: filestream
    id: 1c-tj-json
    enabled: true
    paths:
      - 'D:\\1c_logs\\err_json\\*.log'
    parsers:
      - ndjson:
          target: ""
          add_error_key: true
    fields:
      server_ip: "192.168.88.90"
      app: "1c-enterprise"
      log_type: "tech-journal"
    fields_under_root: true

monitoring.enabled: false

output.logstash:
  hosts: ["${VECTOR_HOST}:5044"]

logging.level: info
logging.to_files: true
logging.files:
  path: C:\\ProgramData\\filebeat\\logs
  name: filebeat
  keepfiles: 7
FILEBEAT

  cat > /opt/openclaw/output/windows-configs/logcfg.xml << 'LOGCFG'
<?xml version="1.0" encoding="UTF-8"?>
g xmlns="http://v8.1c.ru/v8/tech-log">
  og location="D:\1c_logs\err_json"
       history="24"
       format="json"
       placement="flat"
       rotation="size"
       rotationsize="100M">
    <event>
      <ne property="name" value=""/>
    </event>
    <property name="all"/>
  </log>
</config>
LOGCFG

  echo "[log-architect] Windows configs generated:"
  echo "  /opt/openclaw/output/windows-configs/filebeat.yml"
  echo "  /opt/openclaw/output/windows-configs/logcfg.xml"
}

# ── Main ──────────────────────────────────────────────────────────────────────
setup_clickhouse
setup_vector
setup_grafana
generate_filebeat_config

echo "[log-architect] done"
echo ""
echo "══════════════════════════════════════════════════"
echo " ДЕЙСТВИЯ НА WINDOWS 1С-СЕРВЕРЕ:"
echo " 1. Скопировать filebeat.yml:"
echo "    /opt/openclaw/output/windows-configs/filebeat.yml"
echo "    → C:\\Program Files\\Elastic\\Beats\\9.3\\filebeat\\filebeat.yml"
echo " 2. Скопировать logcfg.xml:"
echo "    /opt/openclaw/output/windows-configs/logcfg.xml"
echo "    → C:\\Program Files\\1cv8\\conf\\logcfg.xml"
echo " 3. Restart-Service filebeat"
echo " 4. Перезапустить сервер 1С"
echo "══════════════════════════════════════════════════"
