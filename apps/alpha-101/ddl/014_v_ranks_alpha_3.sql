CREATE OR REPLACE VIEW {{ .DB }}.v_ranks_alpha_3 AS
WITH bucketed AS (
  SELECT
    window_start                                                                       AS time,
    group_array((stock_id, open, volume_f, returns))                                   AS rows,
    array_sort(t -> t.2, group_array((stock_id, open, volume_f, returns)))             AS sorted_by_open,
    array_sort(t -> t.3, group_array((stock_id, open, volume_f, returns)))             AS sorted_by_vol,
    length(group_array(stock_id))                                                      AS n
  FROM tumble({{ .DB }}.v_features_alpha_3, time, {{ .Config.bucket }})
  WHERE returns IS NOT NULL
  GROUP BY window_start
)
SELECT
  time,
  rows[idx].1                                                                                             AS stock_id,
  rows[idx].4                                                                                             AS returns,
  cast(array_first_index(t -> t.1 = rows[idx].1, sorted_by_open) - 1, 'float64') / null_if(n - 1, 0) - 0.5 AS rank_open,
  cast(array_first_index(t -> t.1 = rows[idx].1, sorted_by_vol)  - 1, 'float64') / null_if(n - 1, 0) - 0.5 AS rank_vol
FROM bucketed
ARRAY JOIN array_enumerate(rows) AS idx
