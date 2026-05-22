CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_3 AS
SELECT
  time,
  stock_id,
  returns,
  -1 * cov / null_if(sqrt(var_o * var_v), 0) AS alpha_3
FROM (
  SELECT
    time, stock_id, returns,
    ro_arr, rv_arr,
    array_reduce('avg', ro_arr)                                                            AS mean_o,
    array_reduce('avg', rv_arr)                                                            AS mean_v,
    array_reduce('avg', array_map(o -> (o - mean_o) * (o - mean_o), ro_arr))               AS var_o,
    array_reduce('avg', array_map(v -> (v - mean_v) * (v - mean_v), rv_arr))               AS var_v,
    array_reduce('avg', array_map((o, v) -> (o - mean_o) * (v - mean_v), ro_arr, rv_arr))  AS cov
  FROM (
    SELECT
      time, stock_id, returns,
      lags(rank_open, 0, 9) AS ro_arr,
      lags(rank_vol,  0, 9) AS rv_arr
    FROM {{ .DB }}.v_ranks_alpha_3
    PARTITION BY stock_id
  )
)
