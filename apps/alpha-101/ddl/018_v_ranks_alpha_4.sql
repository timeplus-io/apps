CREATE OR REPLACE VIEW {{ .DB }}.v_ranks_alpha_4 AS
WITH bucketed AS (
  SELECT
    window_start                                                          AS time,
    group_array((stock_id, low, returns))                                 AS rows,
    array_sort(t -> t.2, group_array((stock_id, low, returns)))           AS sorted_by_low,
    length(group_array(stock_id))                                         AS n
  FROM tumble({{ .DB }}.v_features_alpha_4, time, {{ .Config.bucket }})
  WHERE returns IS NOT NULL
  GROUP BY window_start
)
SELECT
  time,
  rows[idx].1                                                                                             AS stock_id,
  rows[idx].3                                                                                             AS returns,
  cast(array_first_index(t -> t.1 = rows[idx].1, sorted_by_low) - 1, 'float64') / null_if(n - 1, 0) - 0.5 AS rank_low
FROM bucketed
ARRAY JOIN array_enumerate(rows) AS idx
