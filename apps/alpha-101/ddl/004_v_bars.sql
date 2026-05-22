CREATE VIEW IF NOT EXISTS {{ .DB }}.v_bars AS
SELECT
  time,
  stock_id,
  open,
  close,
  high,
  low,
  vol_sum                                          AS volume,
  sum_pv / null_if(cast(vol_sum, 'float64'), 0)    AS vwap
FROM (
  SELECT
    window_start              AS time,
    stock_id,
    earliest(price)           AS open,
    latest(price)             AS close,
    max(price)                AS high,
    min(price)                AS low,
    sum(volume)               AS vol_sum,
    sum(price * volume)       AS sum_pv
  FROM tumble({{ .DB }}.market_data, {{ .Config.bucket }})
  GROUP BY window_start, stock_id
)
