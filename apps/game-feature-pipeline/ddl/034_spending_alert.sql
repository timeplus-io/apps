CREATE ALERT IF NOT EXISTS {{ .DB }}.spending_alert
BATCH 10 EVENTS WITH TIMEOUT 5s
LIMIT 1 ALERTS PER 15s
CALL alert_to_slack
AS SELECT
    concat(user_id, ' spent $', to_string(total_spend), ' across last 10 transactions') AS value
FROM {{ .DB }}.total_spend_last_10_transaction
WHERE total_spend > {{ .Config.alert_threshold }};
