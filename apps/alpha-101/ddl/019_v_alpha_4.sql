CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_4 AS
SELECT
  time,
  stock_id,
  returns,
  -1 * cast(array_count(x -> x <= rank_low, rl_arr), 'float64') / 9 AS alpha_4
FROM (
  SELECT
    time, stock_id, returns, rank_low,
    lags(rank_low, 0, 8) AS rl_arr
  FROM {{ .DB }}.v_ranks_alpha_4
  PARTITION BY stock_id
)
