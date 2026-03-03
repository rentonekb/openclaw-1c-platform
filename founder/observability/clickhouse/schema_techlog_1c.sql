CREATE TABLE IF NOT EXISTS openclaw.techlog_1c
(
    received_at   DateTime        DEFAULT now(),
    host          LowCardinality(String),
    log_file      String,
    ts            DateTime64(6),
    level         LowCardinality(String),
    event         LowCardinality(String),
    process       LowCardinality(String),
    p_id          UInt32,
    t_id          UInt64,
    session       UInt64,
    usr           String,
    db            LowCardinality(String),
    duration      UInt64,
    memory        UInt64,
    memory_peak   UInt64,
    sql           String,
    context       String,
    descr         String,
    raw           String
)
ENGINE = MergeTree
ORDER BY ts;
