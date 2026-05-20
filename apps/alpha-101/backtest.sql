-- Backtest report for Alpha #1
--
-- Treats `alpha_prev * returns` as the per-stock per-bucket PnL of a
-- dollar-neutral long-short portfolio that uses the previous bucket's
-- centered rank as the position weight.
--
-- Run via:
--   echo "$(cat apps/alpha-101/backtest.sql)" | \
--     curl -u proton:proton@t+ --data-binary @- \
--          "http://localhost:8123/?default_format=PrettyCompact"
--
-- Adjust the WHERE clause to scope the backtest window.

SELECT
  count()                                                  AS n_obs,
  uniq(stock_id)                                           AS n_stocks,
  min(time)                                                AS t_start,
  max(time)                                                AS t_end,
  round(sum(pnl), 6)                                       AS cum_pnl,
  round(avg(pnl), 8)                                       AS mean_pnl_per_obs,
  round(stddev_pop(pnl), 8)                                AS std_pnl,
  round(avg(pnl) / nullif(stddev_pop(pnl), 0), 4)          AS sharpe_per_obs,
  round(count_if(pnl > 0) * 100.0 / count(), 2)            AS hit_rate_pct,
  round(min(pnl), 6)                                       AS worst_obs,
  round(max(pnl), 6)                                       AS best_obs
FROM alpha_101.v_backtest
WHERE pnl IS NOT NULL
  AND time < now()
SETTINGS seek_to = 'earliest', query_mode = 'table'
