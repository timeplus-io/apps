CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_transaction_features_15m
INTO {{ .DB }}.transaction_features_15m
AS SELECT
    user_id,
    window_start AS ts,
    window_end AS te,
    count(*) AS transaction_count_15m,
    sum(amount_usd) AS total_spent_15m,
    avg(amount_usd) AS avg_transaction_15m,
    max(amount_usd) AS max_transaction_15m,
    count_distinct(item_category) AS unique_categories_15m,
    count_distinct(device_fingerprint) AS unique_devices_15m,
    count_distinct(location:city) AS unique_cities_15m
FROM tumble({{ .DB }}.transactions, 15m)
WHERE _tp_time > earliest_ts()
GROUP BY user_id, window_start, window_end;
