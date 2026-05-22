CREATE VIEW IF NOT EXISTS {{ .DB }}.v_backtest_alpha_4 AS
SELECT
  time, stock_id, alpha_4, returns, alpha_prev,
{{- if eq .Config.strategy "sign" }}
  sign(alpha_prev) * returns AS pnl
{{- else }}
  alpha_prev * returns AS pnl
{{- end }}
FROM (
  SELECT
    time, stock_id, alpha_4, returns,
    lag(alpha_4) OVER (PARTITION BY stock_id) AS alpha_prev
  FROM {{ .DB }}.v_alpha_4
)
