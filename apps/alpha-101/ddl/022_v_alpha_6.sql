CREATE VIEW IF NOT EXISTS {{ .DB }}.v_alpha_6 AS
SELECT
  time,
  stock_id,
  returns,
  -1 * cov / null_if(sqrt(var_o * var_v), 0) AS alpha_6
FROM (
  SELECT
    time, stock_id, returns,
    o_arr, v_arr,
    array_reduce('avg', o_arr)                                                            AS mean_o,
    array_reduce('avg', v_arr)                                                            AS mean_v,
    array_reduce('avg', array_map(o -> (o - mean_o) * (o - mean_o), o_arr))               AS var_o,
    array_reduce('avg', array_map(v -> (v - mean_v) * (v - mean_v), v_arr))               AS var_v,
    array_reduce('avg', array_map((o, v) -> (o - mean_o) * (v - mean_v), o_arr, v_arr))   AS cov
  FROM (
    SELECT
      time, stock_id, returns,
      lags(open,     0, 9) AS o_arr,
      lags(volume_f, 0, 9) AS v_arr
    FROM {{ .DB }}.v_features_alpha_6
    PARTITION BY stock_id
  )
)
