CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_1 AS
WITH ranked AS (
  SELECT
    window_start AS time,
    array_sort(p -> p.2, group_array((stock_id, ts_argmax, returns))) AS sorted_triples,
    length(group_array(stock_id))                                     AS n
  FROM tumble({{ .DB }}.v_ts_argmax_5_alpha_1, time, {{ .Config.bucket }})
  WHERE ts_argmax IS NOT NULL
  GROUP BY window_start
)
SELECT
  time,
  sorted_triples[idx].1                                          AS stock_id,
  cast(idx - 1, 'float64') / null_if(n - 1, 0) - 0.5              AS alpha_1,
  sorted_triples[idx].3                                           AS returns
FROM ranked
ARRAY JOIN array_enumerate(sorted_triples) AS idx
