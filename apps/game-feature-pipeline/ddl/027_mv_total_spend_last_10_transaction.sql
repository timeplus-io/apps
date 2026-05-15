CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_total_spend_last_10_transaction
INTO {{ .DB }}.total_spend_last_10_transaction
AS SELECT
    user_id,
    array_sum(x->x, group_array_last(amount_usd, 10)) AS total_spend
FROM {{ .DB }}.transactions
GROUP BY user_id
EMIT ON UPDATE WITH BATCH 2s;
