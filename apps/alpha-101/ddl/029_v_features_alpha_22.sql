-- Per-stock derived series for Alpha #22:
--   corr5      = rolling 5-bucket Pearson correlation between high and volume
--   stddev20   = rolling 20-bucket pop stddev of close
--   delta_corr5= corr5 − corr5 from 5 buckets ago
-- Plus close-to-close returns for the backtest layer.
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_features_alpha_22 AS
SELECT
  time, stock_id, returns,
  corr5,
  corr5 - corr5_lag5 AS delta_corr5,
  stddev20
FROM (
  SELECT
    time, stock_id, returns,
    -- current 5-bucket corr(high, volume)
    cov5 / null_if(sqrt(var_h * var_v), 0) AS corr5,
    -- corr5 five buckets ago via lags()
    array_element(lags(cov5 / null_if(sqrt(var_h * var_v), 0), 5, 5), 1) AS corr5_lag5,
    -- 20-bucket pop stddev of close
    array_reduce('stddev_pop', close20) AS stddev20
  FROM (
    SELECT
      time, stock_id, h5, v5, close20,
      (close - array_element(lags(close, 1, 1), 1))
        / null_if(array_element(lags(close, 1, 1), 1), 0)                                AS returns,
      array_reduce('avg', h5)                                                            AS mh,
      array_reduce('avg', v5)                                                            AS mv,
      array_reduce('avg', array_map(h -> (h - mh) * (h - mh), h5))                       AS var_h,
      array_reduce('avg', array_map(v -> (v - mv) * (v - mv), v5))                       AS var_v,
      array_reduce('avg', array_map((h, v) -> (h - mh) * (v - mv), h5, v5))              AS cov5
    FROM (
      SELECT
        time, stock_id, close,
        lags(high, 0, 4)                       AS h5,
        lags(cast(volume, 'float64'), 0, 4)    AS v5,
        lags(close, 0, 19)                     AS close20
      FROM {{ .DB }}.v_bars
      PARTITION BY stock_id
    )
  )
  PARTITION BY stock_id
)
