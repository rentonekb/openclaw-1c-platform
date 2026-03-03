--- 
name: "Анализ блокировок 1С по техжурналу"
description: >
  Анализирует блокировки и взаимоблокировки 1С по таблице
  openclaw.techlog_1c в ClickHouse через MCP-инструмент и формирует
  русскоязычный отчёт.
---

# Источник данных

- ClickHouse (HTTP, в Docker), подключение настроено через MCP-инструмент
  с именем `clickhouse`.
- Основная таблица: openclaw.techlog_1c

# Инструменты

- Для выполнения запросов к ClickHouse используй MCP-инструмент `clickhouse`.
- Вызывай метод, отвечающий за выполнение произвольных SQL-запросов
  (обычно `query`), передавая строку SQL в поле `sql` или `query`.
- Инструмент уже знает:
  - хост: 192.168.88.36
  - порт: 8123
  - пользователя: openclaw
  - пароль: openclaw2026
  - базу: openclaw

# Что считать блокировками

- События техжурнала с полем event в:
  - 'TLOCK'
  - 'TTIMEOUT'
  - 'DEADLOCK'
- Также учитывать связанные с ними EXCP (event = 'EXCP'),
  если в descr или context явно упомянуты блокировки или deadlock.

# Основные запросы

1. Количество блокировок за последние 60 минут по типам:

   SELECT
     event,
     count() AS cnt
   FROM openclaw.techlog_1c
   WHERE ts >= now() - INTERVAL 60 MINUTE
     AND event IN ('TLOCK','TTIMEOUT','DEADLOCK')
   GROUP BY event
   ORDER BY cnt DESC;

2. Топ инфобаз по блокировкам за последние 60 минут:

   SELECT
     db,
     event,
     count() AS cnt
   FROM openclaw.techlog_1c
   WHERE ts >= now() - INTERVAL 60 MINUTE
     AND event IN ('TLOCK','TTIMEOUT','DEADLOCK')
   GROUP BY db, event
   ORDER BY cnt DESC
   LIMIT 10;

3. Топ пользователей и сессий:

   SELECT
     db,
     usr,
     session,
     count() AS cnt
   FROM openclaw.techlog_1c
   WHERE ts >= now() - INTERVAL 60 MINUTE
     AND event IN ('TLOCK','TTIMEOUT','DEADLOCK')
   GROUP BY db, usr, session
   ORDER BY cnt DESC
   LIMIT 10;

4. Примеры описаний DEADLOCK:

   SELECT
     ts,
     db,
     usr,
     substr(descr, 1, 200) AS descr_short
   FROM openclaw.techlog_1c
   WHERE ts >= now() - INTERVAL 60 MINUTE
     AND event = 'DEADLOCK'
   ORDER BY ts DESC
   LIMIT 5;

# Поведение навыка

- Для анализа за последние 60 минут:
  - последовательно вызывай MCP-инструмент `clickhouse` с указанными
    выше запросами;
  - получай табличные результаты и интерпретируй их.

- Формируй краткий отчёт на русском языке, включающий:
  - общее количество блокировок по типам;
  - топ-3 инфобазы по количеству блокировок;
  - топ-3 записей db / usr / session / количество;
  - до 5 примеров DEADLOCK с ts, db, usr и укороченным descr.

# Формат отчёта

- Заголовок: "Анализ блокировок 1С за последние 60 минут".
- Раздел "Сводка":
  - общее количество событий TLOCK, TTIMEOUT, DEADLOCK с разбивкой по типам.
- Раздел "Инфобазы":
  - топ-3 базы по количеству блокировок.
- Раздел "Пользователи и сессии":
  - топ-3 записей вида db / usr / session / количество.
- Раздел "Примеры DEADLOCK":
  - до 5 строк ts — db — usr — descr_short.
