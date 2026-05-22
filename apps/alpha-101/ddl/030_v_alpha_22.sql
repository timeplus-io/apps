CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_22 AS
WITH bucketed AS (
  SELECT
    window_start                                                                AS time,
    group_array((stock_id, stddev20, delta_corr5, returns))                     AS rows,
    array_sort(t -> t.2, group_array((stock_id, stddev20, delta_corr5, returns))) AS sorted_by_stddev,
    length(group_array(stock_id))                                               AS n
  FROM tumble({{ .DB }}.v_features_alpha_22, time, {{ .Config.bucket }})
  WHERE stddev20 IS NOT NULL AND delta_corr5 IS NOT NULL
  GROUP BY window_start
)
SELECT
  time,
  rows[idx].1                                                                                              AS stock_id,
  rows[idx].4                                                                                              AS returns,
  -1 * rows[idx].3
     * (cast(array_first_index(t -> t.1 = rows[idx].1, sorted_by_stddev) - 1, 'float64') / null_if(n - 1, 0) - 0.5)
                                                                                                            AS alpha_22
FROM bucketed
ARRAY JOIN array_enumerate(rows) AS idx
