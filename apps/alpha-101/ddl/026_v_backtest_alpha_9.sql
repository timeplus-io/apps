CREATE OR REPLACE VIEW {{ .DB }}.v_backtest_alpha_9 AS
SELECT
  time, stock_id, alpha_9, returns, alpha_prev,
{{- if eq .Config.strategy "sign" }}
  sign(alpha_prev) * returns AS pnl
{{- else }}
  alpha_prev * returns AS pnl
{{- end }}
FROM (
  SELECT
    time, stock_id, alpha_9, returns,
    lag(alpha_9) OVER (PARTITION BY stock_id) AS alpha_prev
  FROM {{ .DB }}.v_alpha_9
)
