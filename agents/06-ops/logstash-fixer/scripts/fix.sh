#!/usr/bin/env bash
# =============================================================================
# Agent: logstash-fixer (Phase 6)
# Description: Diagnose and fix Logstash beats input (port 5044)
# =============================================================================
set -euo pipefail

LOG_DIR="/var/log/openclaw"
LOGSTASH_PIPELINE_DIR="/etc/logstash/conf.d"
LOGSTASH_BEATS_CONF="${LOGSTASH_PIPELINE_DIR}/beats-input.conf"
MAX_WAIT=120

mkdir -p "${LOG_DIR}"
LOGFILE="${LOG_DIR}/logstash-fixer.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [logstash-fixer] $*" | tee -a "${LOGFILE}"; }
fail() { log "ERROR: $*"; exit 1; }

log "=== Phase 6: logstash-fixer START ==="

# --- Step 1: Check if logstash is installed ---
if ! command -v logstash &>/dev/null && ! systemctl list-units --type=service 2>/dev/null | grep -q logstash; then
  log "Logstash not found via PATH. Checking /usr/share/logstash..."
  if [ ! -d /usr/share/logstash ]; then
    fail "Logstash is not installed. Run infra-installer agent first."
  fi
fi

# --- Step 2: Diagnose current state ---
log "--- Diagnosing Logstash service state ---"
systemctl is-active logstash && log "Logstash: ACTIVE" || log "Logstash: NOT ACTIVE"
systemctl is-enabled logstash && log "Logstash: ENABLED" || log "Logstash: NOT ENABLED"

# --- Step 3: Check/create pipeline conf.d directory ---
log "--- Checking pipeline directory: ${LOGSTASH_PIPELINE_DIR} ---"
mkdir -p "${LOGSTASH_PIPELINE_DIR}"

# --- Step 4: Check/fix beats input pipeline config ---
log "--- Checking Beats input pipeline config ---"
if [ ! -f "${LOGSTASH_BEATS_CONF}" ]; then
  log "beats-input.conf NOT FOUND. Creating..."
  cat > "${LOGSTASH_BEATS_CONF}" << 'EOF'
input {
  beats {
    port => 5044
    host => "0.0.0.0"
  }
}

filter {
  if [fields][log_type] == "1c_tech" {
    grok {
      match => { "message" => "%{TIMESTAMP_ISO8601:timestamp},%{DATA:duration},%{DATA:process},%{DATA:thread},%{DATA:module},%{DATA:method},%{INT:line},%{GREEDYDATA:description}" }
    }
  }
}

output {
  if [@metadata][beat] {
    elasticsearch {
      hosts => ["http://localhost:9200"]
      index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
    }
  } else {
    elasticsearch {
      hosts => ["http://localhost:9200"]
      index => "openclaw-logs-%{+YYYY.MM.dd}"
    }
  }
  stdout { codec => rubydebug }
}
EOF
  log "Created: ${LOGSTASH_BEATS_CONF}"
else
  log "beats-input.conf EXISTS. Checking for port 5044..."
  if ! grep -q '5044' "${LOGSTASH_BEATS_CONF}"; then
    log "WARNING: port 5044 not found in config. Appending beats input block..."
    cat >> "${LOGSTASH_BEATS_CONF}" << 'EOF'
# Appended by logstash-fixer agent
input {
  beats {
    port => 5044
    host => "0.0.0.0"
  }
}
EOF
    log "Appended beats input to existing config."
  else
    log "Port 5044 found in existing config. Config OK."
  fi
fi

# --- Step 5: Check logstash.yml for pipeline config ---
LOGSTASH_YML="/etc/logstash/logstash.yml"
if [ -f "${LOGSTASH_YML}" ]; then
  log "--- Checking logstash.yml ---"
  grep -q 'path.config' "${LOGSTASH_YML}" || {
    log "Adding path.config to logstash.yml"
    echo "path.config: ${LOGSTASH_PIPELINE_DIR}" >> "${LOGSTASH_YML}"
  }
  log "logstash.yml OK."
fi

# --- Step 6: Fix permissions ---
log "--- Fixing permissions ---"
chown -R logstash:logstash "${LOGSTASH_PIPELINE_DIR}" 2>/dev/null || true
chmod 644 "${LOGSTASH_BEATS_CONF}"

# --- Step 7: Validate config ---
log "--- Validating Logstash config ---"
if command -v logstash &>/dev/null; then
  logstash --path.settings /etc/logstash -t 2>&1 | tee -a "${LOGFILE}" && log "Config validation: OK" || log "WARNING: Config validation errors (may still start)"
elif [ -f /usr/share/logstash/bin/logstash ]; then
  /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t 2>&1 | tee -a "${LOGFILE}" && log "Config validation: OK" || log "WARNING: Config validation errors (may still start)"
fi

# --- Step 8: Enable and restart Logstash ---
log "--- Enabling and restarting Logstash service ---"
systemctl enable logstash
systemctl stop logstash 2>/dev/null || true
sleep 5
systemctl start logstash

# --- Step 9: Wait for port 5044 to be listening ---
log "--- Waiting for Logstash port 5044 (up to ${MAX_WAIT}s) ---"
ELAPSED=0
while [ "${ELAPSED}" -lt "${MAX_WAIT}" ]; do
  if ss -tnlp 2>/dev/null | grep -q ':5044'; then
    log "SUCCESS: Logstash is listening on port 5044 (after ${ELAPSED}s)"
    break
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  log "Waiting... ${ELAPSED}s / ${MAX_WAIT}s"
done

# --- Step 10: Final verification ---
log "--- Final Verification ---"
if ss -tnlp 2>/dev/null | grep -q ':5044'; then
  log "[OK] Port 5044 is LISTENING"
else
  log "[FAIL] Port 5044 still not listening after ${MAX_WAIT}s"
  log "--- Logstash journal (last 50 lines) ---"
  journalctl -u logstash -n 50 --no-pager 2>&1 | tee -a "${LOGFILE}" || true
  log "--- Logstash logs ---"
  tail -n 50 /var/log/logstash/logstash-plain.log 2>/dev/null | tee -a "${LOGFILE}" || true
  fail "Logstash port 5044 is not listening. Check logs above."
fi

log "--- Service status ---"
systemctl status logstash --no-pager 2>&1 | tee -a "${LOGFILE}" || true

ss -tnlp | grep 5044 | tee -a "${LOGFILE}"

log "=== Phase 6: logstash-fixer COMPLETE ==="
echo "RESULT: OK — Logstash beats input active on port 5044"
