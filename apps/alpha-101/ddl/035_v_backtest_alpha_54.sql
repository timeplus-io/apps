CREATE VIEW IF NOT EXISTS {{ .DB }}.v_backtest_alpha_54 AS
SELECT
  time, stock_id, alpha_54, returns, alpha_prev,
{{- if eq .Config.strategy "sign" }}
  sign(alpha_prev) * returns AS pnl
{{- else }}
  alpha_prev * returns AS pnl
{{- end }}
FROM (
  SELECT
    time, stock_id, alpha_54, returns,
    lag(alpha_54) OVER (PARTITION BY stock_id) AS alpha_prev
  FROM {{ .DB }}.v_alpha_54
)
