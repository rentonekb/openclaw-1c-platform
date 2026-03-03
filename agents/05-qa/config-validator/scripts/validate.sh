#!/bin/bash
set -euo pipefail

echo "[config-validator] starting validation..."

ERRORS=0
WARNINGS=0

pass() { echo "[config-validator] ✅ $1"; }
fail() { echo "[config-validator] ❌ $1"; ERRORS=$((ERRORS+1)); }
warn() { echo "[config-validator] ⚠️  $1"; WARNINGS=$((WARNINGS+1)); }

# ── 1. Проверка logcfg.xml ────────────────────────────────────────────────────
validate_logcfg() {
  echo "[config-validator] --- logcfg.xml ---"
  FILE="/opt/openclaw/output/windows-configs/logcfg.xml"

  [ -f "$FILE" ] && pass "logcfg.xml существует" || { fail "logcfg.xml не найден"; return; }

  # XML синтаксис
  python3 -c "
import xml.etree.ElementTree as ET, sys
try:
    ET.parse(sys.argv[1])
except ET.ParseError:
    sys.exit(1)
" "$FILE" 2>/dev/null \
    && pass "logcfg.xml â XML ÑÐ¸Ð½ÑÐ°ÐºÑÐ¸Ñ ÐºÐ¾ÑÑÐµÐºÑÐµÐ½" \
    || fail "logcfg.xml â XML ÑÐ¸Ð½ÑÐ°ÐºÑÐ¸Ñ ÐÐ¨ÐÐÐÐ"

  # Обязательные атрибуты
  grep -q "format=\"json\"" "$FILE"     && pass "logcfg.xml — format=json присутствует"     || fail "logcfg.xml — format=json отсутствует"

  grep -q "placement=\"flat\"" "$FILE"     && pass "logcfg.xml — placement=flat присутствует"     || warn "logcfg.xml — placement=flat отсутствует"

  # Фильтры событий
  for EVENT in EXCP TLOCK TTIMEOUT DEADLOCK DBMSSQL CALL; do
    grep -q "value=\"$EVENT\"" "$FILE"       && pass "logcfg.xml — событие $EVENT настроено"       || warn "logcfg.xml — событие $EVENT не настроено"
  done
}

# ── 2. Проверка filebeat.yml ──────────────────────────────────────────────────
validate_filebeat() {
  echo "[config-validator] --- filebeat.yml ---"
  FILE="/opt/openclaw/output/windows-configs/filebeat.yml"

  [ -f "$FILE" ] && pass "filebeat.yml существует" || { fail "filebeat.yml не найден"; return; }

  grep -q "type: filestream" "$FILE"     && pass "filebeat.yml — input type=filestream"     || fail "filebeat.yml — input type не filestream"

  grep -q "output.logstash" "$FILE"     && pass "filebeat.yml — output.logstash настроен"     || fail "filebeat.yml — output.logstash отсутствует"

  grep -q "5044" "$FILE"     && pass "filebeat.yml — порт 5044 указан"     || fail "filebeat.yml — порт 5044 не найден"

  grep -q "ndjson" "$FILE"     && pass "filebeat.yml — ndjson парсер настроен"     || fail "filebeat.yml — ndjson парсер отсутствует"
}

# ── 3. Проверка Vector ────────────────────────────────────────────────────────
validate_vector() {
  echo "[config-validator] --- Vector ---"

  docker ps --filter name=vector --format "{{.Names}}" | grep -q vector     && pass "Vector контейнер запущен"     || fail "Vector контейнер НЕ запущен"

  curl -sf --max-time 5 http://localhost:5044 > /dev/null 2>&1 || true
  nc -z localhost 5044 2>/dev/null     && pass "Vector порт 5044 доступен"     || fail "Vector порт 5044 недоступен"

  # Ошибки в логах Vector
  VECTOR_ERRORS=$(docker logs vector 2>&1 | grep -c "ERROR" || true)
  [ "$VECTOR_ERRORS" -eq 0 ]     && pass "Vector логи — ошибок нет"     || warn "Vector логи — найдено $VECTOR_ERRORS ошибок"
}

# ── 4. Проверка ClickHouse ────────────────────────────────────────────────────
validate_clickhouse() {
  echo "[config-validator] --- ClickHouse ---"

  CODE=$(curl -s -o /dev/null -w "%{http_code}"     "http://localhost:8123/?user=openclaw&password=openclaw2026"     --data "SELECT 1")
  [ "$CODE" = "200" ]     && pass "ClickHouse HTTP API доступен"     || fail "ClickHouse HTTP API недоступен (HTTP $CODE)"

  # Таблица существует
  RESULT=$(curl -s "http://localhost:8123/?user=openclaw&password=openclaw2026"     --data "EXISTS TABLE openclaw.techlog_1c")
  [ "$RESULT" = "1" ]     && pass "Таблица openclaw.techlog_1c существует"     || fail "Таблица openclaw.techlog_1c НЕ существует"

  # Количество записей
  COUNT=$(curl -s "http://localhost:8123/?user=openclaw&password=openclaw2026"     --data "SELECT count() FROM openclaw.techlog_1c")
  pass "ClickHouse — записей в techlog_1c: $COUNT"
}

# ── 5. Проверка Grafana ───────────────────────────────────────────────────────
validate_grafana() {
  echo "[config-validator] --- Grafana ---"

  CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health)
  [ "$CODE" = "200" ]     && pass "Grafana доступна"     || fail "Grafana недоступна (HTTP $CODE)"

  CODE=$(curl -s -o /dev/null -w "%{http_code}"     -u admin:admin     "http://localhost:3000/api/datasources/name/ClickHouse-OpenClaw")
  [ "$CODE" = "200" ]     && pass "Grafana datasource ClickHouse-OpenClaw существует"     || fail "Grafana datasource ClickHouse-OpenClaw НЕ найден"
}

# ── Запуск всех проверок ──────────────────────────────────────────────────────
validate_logcfg
validate_filebeat
validate_vector
validate_clickhouse
validate_grafana

# ── Итог ─────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════"
echo " Результат валидации:"
echo " ✅ Успешно:    $(grep -c "✅" <<< "$(echo $ERRORS)" || true)"
echo " ❌ Ошибок:    $ERRORS"
echo " ⚠️  Предупреждений: $WARNINGS"
echo "══════════════════════════════════════════════════"

[ "$ERRORS" -eq 0 ] && exit 0 || exit 1
