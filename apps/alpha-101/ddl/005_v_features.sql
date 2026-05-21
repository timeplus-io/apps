CREATE OR REPLACE VIEW {{ .DB }}.v_features AS
SELECT
  time, stock_id, close, returns, sigma_ret_20,
  sign(cond) * cond * cond AS signed_power
FROM (
  SELECT
    time, stock_id, close, returns, sigma_ret_20,
    if(returns < 0, sigma_ret_20, close) AS cond
  FROM (
    SELECT
      time, stock_id, close,
      (array_element(close21, 1) - array_element(close21, 2)) / null_if(array_element(close21, 2), 0) AS returns,
      array_reduce(
        'stddev_pop',
        array_map(
          i -> (array_element(close21, i) - array_element(close21, i + 1)) / null_if(array_element(close21, i + 1), 0),
          range(1, 21)
        )
      ) AS sigma_ret_20
    FROM (
      SELECT
        time, stock_id, close,
        lags(close, 0, 20) AS close21
      FROM {{ .DB }}.v_bars
      PARTITION BY stock_id
    )
  )
)
