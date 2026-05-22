CREATE VIEW IF NOT EXISTS {{ .DB }}.v_alpha_9 AS
SELECT
  time,
  stock_id,
  returns,
  multi_if(
    ts_min > 0,    delta_close_1,
    ts_max < 0,    delta_close_1,
                  -delta_close_1
  ) AS alpha_9
FROM (
  SELECT
    time, stock_id, returns, delta_close_1,
    array_min(d5)  AS ts_min,
    array_max(d5)  AS ts_max
  FROM (
    SELECT
      time, stock_id, returns, delta_close_1,
      lags(if_null(delta_close_1, 0), 0, 4) AS d5
    FROM {{ .DB }}.v_features_alpha_9
    PARTITION BY stock_id
  )
)
