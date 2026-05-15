CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_stock
INTO {{ .DB }}.stock
AS SELECT
    to_unix_timestamp64_milli(now64(3))             AS event_ts,
    to_string(100000 + security_idx)                AS SecurityID,
    concat(to_string(100000 + security_idx), '.US') AS Symbol,
    100.0                                            AS PreClosePx,
    100::float64 + price_delta                      AS LastPx,
    99.0                                             AS OpenPx,
    100.0                                            AS ClosePx,
    100.0                                            AS HighPx,
    90.0                                             AS LowPx
FROM {{ .DB }}.quote_random;
