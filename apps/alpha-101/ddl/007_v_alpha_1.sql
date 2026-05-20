CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_1 AS
WITH ranked AS (
  SELECT
    window_start AS time,
    array_sort(p -> p.2, group_array((stock_id, ts_argmax))) AS sorted_pairs,
    length(group_array(stock_id))                            AS n
  FROM tumble({{ .DB }}.v_ts_argmax_5, time, {{ .Config.bucket }})
  WHERE ts_argmax IS NOT NULL
  GROUP BY window_start
)
SELECT
  time,
  sorted_pairs[idx].1                        AS stock_id,
  cast(idx, 'float64') / n - 0.5             AS alpha_1
FROM ranked
ARRAY JOIN array_enumerate(sorted_pairs) AS idx
