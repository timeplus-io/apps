CREATE STREAM IF NOT EXISTS {{ .DB }}.transactions
(
    transaction_id string,
    user_id string,
    session_id string,
    timestamp datetime64(3),
    transaction_type enum8('iap_purchase' = 1, 'subscription' = 2, 'refund' = 3),
    item_category enum8('cosmetic' = 1, 'power_up' = 2, 'loot_box' = 3, 'battle_pass' = 4),
    item_id string,
    amount_usd float64,
    currency_type enum8('real_money' = 1, 'virtual_currency' = 2),
    payment_method enum8('apple_pay' = 1, 'google_pay' = 2, 'credit_card' = 3, 'paypal' = 4),
    location string,
    device_fingerprint string
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_hours }} HOUR
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}';
