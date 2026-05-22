CREATE VIEW IF NOT EXISTS {{ .DB }}.v_alpha_volume_spike AS
SELECT
  product_id,
  time,
  close,
  volume,
  array_avg(lags(volume, 1, 20))                                          AS avg_volume_20s,
  volume / (array_avg(lags(volume, 1, 20)) + 0.0001)                     AS volume_ratio,
  (volume / (array_avg(lags(volume, 1, 20)) + 0.0001))
    * ((close - array_element(lags(close, 1, 1), 1)) / close)            AS volume_spike_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
