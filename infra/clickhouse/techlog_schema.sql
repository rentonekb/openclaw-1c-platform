USE openclaw;

-- RAW: техжурнал как есть из Vector/Filebeat
DROP TABLE IF EXISTS techlog_raw_any;

CREATE TABLE techlog_raw_any
(
    ts     DateTime DEFAULT parseDateTimeBestEffort(ts_str),
    ts_str String,
    msg    String
)
ENGINE = MergeTree
ORDER BY ts
TTL ts + INTERVAL 3 DAY
SETTINGS index_granularity = 8192;

-- PARSED: нормализованный техжурнал
DROP TABLE IF EXISTS techlog_parsed;

CREATE TABLE techlog_parsed
(
    ts           DateTime,
    app          String,
    server_ip    String,
    log_type     String,
    t_event      String,
    t_time       DateTime,
    t_level      String,
    t_process    String,
    t_thread     String,
    t_descr      String,
    t_ret_excp   String,
    t_memory_peak UInt64,
    t_client_id  String,
    t_app_name   String,
    t_context    String,
    t_severity   String,
    t_row        String
)
ENGINE = MergeTree
ORDER BY (ts, app, server_ip)
TTL ts + INTERVAL 30 DAY
SETTINGS
    index_granularity = 8192,
    compress_primary_key = 1;

-- MATERIALIZED VIEW: парсинг JSON + строки техжурнала
DROP VIEW IF EXISTS techlog_parsed_mv;

CREATE MATERIALIZED VIEW techlog_parsed_mv
TO techlog_parsed
AS
SELECT
    ts,
    JSONExtractString(msg, 'app')        AS app,
    JSONExtractString(msg, 'server_ip')  AS server_ip,
    JSONExtractString(msg, 'log_type')   AS log_type,
    splitByChar(',', JSONExtractString(msg, 'message'))[2]      AS t_event,
    JSONExtractString(msg, 'message')    AS t_row,
    NULL                                 AS t_time,
    splitByChar(',', JSONExtractString(msg, 'message'))[2]      AS t_level,
    extract(JSONExtractString(msg, 'message'), 'process=([^,]+)')      AS t_process,
    extract(JSONExtractString(msg, 'message'), 'OSThread=([^,]+)')     AS t_thread,
    extract(JSONExtractString(msg, 'message'), 'Descr=([^,]+)')        AS t_descr,
    extract(JSONExtractString(msg, 'message'), 'RetExcp=([^,]+)')      AS t_ret_excp,
    toUInt64OrZero(
        extract(JSONExtractString(msg, 'message'), 'MemoryPeak=([0-9]+)')
    ) AS t_memory_peak,
    extract(JSONExtractString(msg, 'message'), 't:clientID=([^,]+)')   AS t_client_id,
    extract(JSONExtractString(msg, 'message'), 't:applicationName=([^,]+)') AS t_app_name,
    extract(JSONExtractString(msg, 'message'), 'Context=([^,]+)')      AS t_context,
    CASE
        WHEN like(JSONExtractString(msg, 'message'), '%level=ERROR%')   THEN 'ERROR'
        WHEN like(JSONExtractString(msg, 'message'), '%level=WARNING%') THEN 'WARNING'
        WHEN like(JSONExtractString(msg, 'message'), '%level=INFO%')    THEN 'INFO'
        ELSE 'OTHER'
    END                                         AS t_severity
FROM techlog_raw_any;
