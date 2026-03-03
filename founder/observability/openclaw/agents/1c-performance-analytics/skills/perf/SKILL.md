---
name: "Анализ производительности 1С по техжурналу"
description: >
  Анализирует тормоза 1С по событиям DBMSSQL и CALL в таблице
  openclaw.techlog_1c в ClickHouse и формирует русскоязычный отчёт
  с примерами SQL и curl-команд для автоматизации.
---

# Источник данных

- ClickHouse по HTTP:
  - endpoint: http://192.168.88.36:8123
  - пользователь: openclaw
  - пароль: openclaw2026
  - основная таблица: openclaw.techlog_1c

- Ключевые поля:
  - ts      — время события
  - db      — имя инфобазы
  - usr     — пользователь
  - session — идентификатор сессии
  - host    — сервер
  - event   — тип события (DBMSSQL, CALL и др.)
  - duration — длительность операции (в микросекундах или миллисекундах, как принято в таблице)
  - descr   — описание/текст запроса или контекст
  - context — дополнительный контекст

# Что считать тормозами

- События с event IN ('DBMSSQL','CALL'), у которых duration
  заметно выше нормы.
- Для базового анализа используй пороги:
  - "медленная" операция: duration >= 1 секунды;
  - тяжёлая нагрузка: суммарный duration по базе/пользователю
    за последние 60 минут сильно больше обычного.

Порог 1 секунда — пример; при генерации отчёта объясни, что его можно
подстраивать под конкретную систему.

# Основные запросы (примерная логика)

1. Общая статистика по событиям DBMSSQL и CALL за последние 60 минут:

   SELECT
     event,
     count() AS cnt,
     sum(duration) AS total_duration,
     avg(duration) AS avg_duration
   FROM openclaw.techlog_1c
   WHERE ts >= now() - INTERVAL 60 MINUTE
     AND event IN ('DBMSSQL','CALL')
   GROUP BY event
   ORDER BY total_duration DESC;

2. Топ инфобаз по суммарному duration:

   SELECT
     db,
     event,
     count() AS cnt,
     sum(duration) AS total_duration,
     avg(duration) AS avg_duration
   FROM openclaw.techlog_1c
   WHERE ts >= now() - INTERVAL 60 MINUTE
     AND event IN ('DBMSSQL','CALL')
   GROUP BY db, event
   ORDER BY total_duration DESC
   LIMIT 10;

3. Топ пользователей по суммарному duration:

   SELECT
     db,
     usr,
     event,
     count() AS cnt,
     sum(duration) AS total_duration,
     avg(duration) AS avg_duration
   FROM openclaw.techlog_1c
   WHERE ts >= now() - INTERVAL 60 MINUTE
     AND event IN ('DBMSSQL','CALL')
   GROUP BY db, usr, event
   ORDER BY total_duration DESC
   LIMIT 10;

4. Топ "медленных" отдельных операций:

   SELECT
     ts,
     db,
     usr,
     event,
     duration,
     substr(descr, 1, 200) AS descr_short
   FROM openclaw.techlog_1c
   WHERE ts >= now() - INTERVAL 60 MINUTE
     AND event IN ('DBMSSQL','CALL')
     AND duration >= 1000000  -- ~1 секунда, если duration в мкс
   ORDER BY duration DESC
   LIMIT 20;

# Поведение навыка

- Понимай, что ты не можешь сам выполнять SQL-запросы к ClickHouse.
  Твоя задача:
  - сгенерировать корректные SQL-запросы для ClickHouse;
  - сгенерировать готовые curl-команды для их выполнения через HTTP;
  - описать, как по результатам этих запросов собрать отчёт.

- Для каждого из основных запросов выше:
  - покажи сам SQL;
  - сгенерируй curl-команду вида:

    curl 'http://192.168.88.36:8123/?user=openclaw&password=openclaw2026' --data-binary '<SQL_ЗАПРОС>'

  - предполагается, что ответ будет в текстовом табличном формате (TSV).

- На основе предполагаемых результатов опиши структуру отчёта
  на русском языке, включая:
  - сводку по суммарному и среднему duration для DBMSSQL/CALL;
  - топ-3 проблемных инфобаз;
  - топ-3 пользователей/сеансов;
  - примеры самых медленных операций с указанием db, usr, ts и descr_short.

# Формат отчёта

- Заголовок: "Анализ производительности 1С за последние 60 минут".
- Раздел "Сводка":
  - суммарный и средний duration по DBMSSQL и CALL.
- Раздел "Инфобазы":
  - топ-3 базы по суммарному duration.
- Раздел "Пользователи":
  - топ-3 пользователя (по db/usr) по суммарному duration.
- Раздел "Самые медленные операции":
  - несколько строк с ts, db, usr, event, duration, descr_short.

# Дополнительные рекомендации

- В пояснениях к отчёту укажи:
  - что длительное время выполнения DBMSSQL может указывать на
    проблемы с SQL-запросами, индексами или блокировками;
  - что длительные CALL могут быть связаны с тяжёлым прикладным кодом;
  - что корреляцию с блокировками и ошибками можно получить,
    комбинируя этот отчёт с результатами агентов 1c-lock-analytics
    и 1c-error-analytics.
