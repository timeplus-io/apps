CREATE OR REPLACE VIEW {{ .DB }}.v_ts_argmax_5_alpha_1 AS
SELECT
  time,
  stock_id,
  signed_power,
  returns,
  sp5,
  array_first_index(x -> x = array_max(sp5), sp5) AS ts_argmax
FROM (
  SELECT
    time,
    stock_id,
    signed_power,
    returns,
    lags(if_null(signed_power, 0), 0, 4) AS sp5
  FROM {{ .DB }}.v_features_alpha_1
  PARTITION BY stock_id
)
