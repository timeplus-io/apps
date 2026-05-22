CREATE VIEW IF NOT EXISTS {{ .DB }}.v_ranks_alpha_2 AS
WITH bucketed AS (
  SELECT
    window_start                                                                              AS time,
    group_array((stock_id, intraday_ret, log_vol_delta_2, returns))                           AS rows,
    array_sort(t -> t.2, group_array((stock_id, intraday_ret, log_vol_delta_2, returns)))     AS sorted_by_ret,
    array_sort(t -> t.3, group_array((stock_id, intraday_ret, log_vol_delta_2, returns)))     AS sorted_by_vol,
    length(group_array(stock_id))                                                             AS n
  FROM tumble({{ .DB }}.v_features_alpha_2, time, {{ .Config.bucket }})
  WHERE intraday_ret IS NOT NULL AND log_vol_delta_2 IS NOT NULL
  GROUP BY window_start
)
SELECT
  time,
  rows[idx].1                                                                                            AS stock_id,
  rows[idx].2                                                                                            AS intraday_ret,
  rows[idx].3                                                                                            AS log_vol_delta_2,
  rows[idx].4                                                                                            AS returns,
  cast(array_first_index(t -> t.1 = rows[idx].1, sorted_by_ret) - 1, 'float64') / null_if(n - 1, 0) - 0.5 AS rank_ret,
  cast(array_first_index(t -> t.1 = rows[idx].1, sorted_by_vol) - 1, 'float64') / null_if(n - 1, 0) - 0.5 AS rank_vol
FROM bucketed
ARRAY JOIN array_enumerate(rows) AS idx
