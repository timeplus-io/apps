CREATE OR REPLACE VIEW {{ .DB }}.v_backtest AS
SELECT
  time,
  stock_id,
  alpha_1,
  returns,
  lag(alpha_1) OVER (PARTITION BY stock_id)            AS alpha_prev,
  lag(alpha_1) OVER (PARTITION BY stock_id) * returns  AS pnl
FROM {{ .DB }}.v_alpha_1
