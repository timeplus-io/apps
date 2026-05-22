CREATE VIEW IF NOT EXISTS {{ .DB }}.v_backtest_alpha_6 AS
SELECT
  time, stock_id, alpha_6, returns, alpha_prev,
{{- if eq .Config.strategy "sign" }}
  sign(alpha_prev) * returns AS pnl
{{- else }}
  alpha_prev * returns AS pnl
{{- end }}
FROM (
  SELECT
    time, stock_id, alpha_6, returns,
    lag(alpha_6) OVER (PARTITION BY stock_id) AS alpha_prev
  FROM {{ .DB }}.v_alpha_6
)
