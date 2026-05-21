CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_2 AS
SELECT
  time,
  stock_id,
  returns,
  -1 * cov / null_if(sqrt(var_rv * var_rr), 0) AS alpha_2
FROM (
  SELECT
    time, stock_id, returns,
    rv_arr, rr_arr,
    array_reduce('avg', rv_arr)                                                              AS mean_rv,
    array_reduce('avg', rr_arr)                                                              AS mean_rr,
    array_reduce('avg', array_map(v -> (v - mean_rv) * (v - mean_rv), rv_arr))               AS var_rv,
    array_reduce('avg', array_map(r -> (r - mean_rr) * (r - mean_rr), rr_arr))               AS var_rr,
    array_reduce('avg', array_map((v, r) -> (v - mean_rv) * (r - mean_rr), rv_arr, rr_arr))  AS cov
  FROM (
    SELECT
      time, stock_id, returns,
      lags(rank_vol, 0, 5) AS rv_arr,
      lags(rank_ret, 0, 5) AS rr_arr
    FROM {{ .DB }}.v_ranks_alpha_2
    PARTITION BY stock_id
  )
)
