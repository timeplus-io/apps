CREATE OR REPLACE VIEW {{ .DB }}.v_bars AS
SELECT
  window_start    AS time,
  stock_id,
  earliest(price) AS open,
  latest(price)   AS close,
  sum(volume)     AS volume
FROM tumble({{ .DB }}.market_data, {{ .Config.bucket }})
GROUP BY window_start, stock_id
