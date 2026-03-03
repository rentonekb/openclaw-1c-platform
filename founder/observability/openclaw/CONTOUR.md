# Контур наблюдаемости 1С + OpenClaw + ClickHouse (founder, 2026-03-03)

## Базовая инфраструктура

- Хост: founder (Linux, root).
- ClickHouse в Docker:
  - HTTP endpoint: http://192.168.88.36:8123
  - Пользователь: openclaw
  - Пароль: openclaw2026
  - База: openclaw

- Vector: читает техжурнал 1С и пишет данные в таблицу openclaw.techlog_1c.

## ClickHouse

- Таблица openclaw.techlog_1c (DESCRIBE):

  - received_at   DateTime        DEFAULT now()
  - host          LowCardinality(String)
  - log_file      String
  - ts            DateTime64(6)
  - level         LowCardinality(String)
  - event         LowCardinality(String)
  - process       LowCardinality(String)
  - p_id          UInt32
  - t_id          UInt64
  - session       UInt64
  - usr           String
  - db            LowCardinality(String)
  - duration      UInt64
  - memory        UInt64
  - memory_peak   UInt64
  - sql           String
  - context       String
  - descr         String
  - raw           String

- Фактическое состояние на 2026‑03‑03:
  - новые записи появляются;
  - ts и duration заполнены;
  - db, usr, event, descr чаще всего пустые — пайплайн техжурнала требует донастройки парсинга.

## OpenClaw

- Версия: 2026.2.26 (bc50708).
- Локальный конфиг: /root/.openclaw/openclaw.json
- В этом репозитории хранится копия: founder/observability/openclaw/openclaw.json.
- Модель агентов:
  - провайдер: gigachat
  - модель: gigachat/GigaChat
  - contextWindow: 131072
  - maxTokens: 4096

- Telegram:
  - botToken прописан в openclaw.json.
  - Используется для алертов оркестратором и аналитическими агентами.

## Агенты OpenClaw

Существуют рабочие директории:

- orchestrator-main
- pipeline-integrator
- 1c-performance-analytics
- 1c-lock-analytics
- 1c-error-analytics
- infra-host-analytics
- github-committer
- github-reviewer
- config-tester
- scenario-tester
- root-cause-advisor

В этом репозитории копии их workspace лежат под:
- founder/observability/openclaw/agents/<id>/

## Skills (на 2026-03-03)

- 1c-lock-analytics:
  - skills/locks/SKILL.md
  - Описывает анализ блокировок 1С по openclaw.techlog_1c, генерирует SQL и curl-команды и структуру отчёта.

- 1c-performance-analytics:
  - skills/perf/SKILL.md
  - Описывает анализ производительности 1С по событиям DBMSSQL/CALL, генерирует SQL и curl-команды и структуру отчёта.

## Правила изменения контура

- Любые изменения схем ClickHouse, конфигов Vector, openclaw.json, AGENT.md и SKILL.md сначала вносятся в этот репозиторий.
- После коммита изменения применяются на хосте (ClickHouse DDL, перезапуск Vector, обновление ~/.openclaw/*).
- Агенты github-committer и github-reviewer будут использовать этот каталог founder/observability как единственный источник истины для контура founder.
