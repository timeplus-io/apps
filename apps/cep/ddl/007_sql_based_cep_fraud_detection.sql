CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.sql_based_cep_fraud_detection
(
  `userId`                string,
  `total_events`          uint64,
  `login_count`           uint64,
  `purchase_count`        uint64,
  `total_purchase_amount` float64,
  `all_locations`         array(string),
  `event_sequence`        array(string),
  `time_sequence`         array(datetime64(3)),
  `t_start`               datetime64(3),
  `t_end`                 datetime64(3),
  `_tp_time`              datetime64(3, 'UTC') DEFAULT now64(3, 'UTC'),
  `_tp_sn`                int64
) AS
SELECT
  userId,
  count(*) AS total_events,
  count_if(eventType = 'login') AS login_count,
  count_if(eventType = 'purchase') AS purchase_count,
  sum(amount) AS total_purchase_amount,
  group_array(location) AS all_locations,
  group_array(eventType) AS event_sequence,
  group_array(timestamp) AS time_sequence,
  window_start AS t_start,
  window_end AS t_end
FROM
  hop({{ .DB }}.unified_user_events, timestamp, 5s, 10m)
GROUP BY
  userId, window_start, window_end
HAVING
  (length(array_distinct(all_locations)) >= 2) AND (total_purchase_amount > 1000) AND (purchase_count >= 1)
