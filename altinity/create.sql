CREATE TABLE otel_logs ON CLUSTER '{cluster}'
(
    `Timestamp` DateTime,
    `TraceId` String CODEC(ZSTD(3)),
    `SpanId` String CODEC(ZSTD(3)),
    `TraceFlags` UInt8,
    `SeverityText` LowCardinality(String),
    `SeverityNumber` UInt8,
    `ServiceName` LowCardinality(String),
    `Body` String CODEC(ZSTD(3)),
    `ResourceSchemaUrl` LowCardinality(String),
    `ResourceAttributes` LowCardinality(String),
    `ScopeSchemaUrl` LowCardinality(String),
    `ScopeName` LowCardinality(String),
    `ScopeVersion` LowCardinality(String),
    `ScopeAttributes` Map(LowCardinality(String), String),
    `LogAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(3)),
    INDEX text_idx Body TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = lower(Body)) GRANULARITY 100000000
)
ENGINE = ReplicatedMergeTree
PRIMARY KEY (ServiceName, Timestamp)
ORDER BY (ServiceName, Timestamp)
SETTINGS optimize_row_order = 1, min_level_for_wide_part = 1, parts_to_throw_insert = 30000;
