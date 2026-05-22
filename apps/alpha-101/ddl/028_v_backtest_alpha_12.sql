CREATE OR REPLACE VIEW {{ .DB }}.v_backtest_alpha_12 AS
SELECT
  time, stock_id, alpha_12, returns, alpha_prev,
{{- if eq .Config.strategy "sign" }}
  sign(alpha_prev) * returns AS pnl
{{- else }}
  alpha_prev * returns AS pnl
{{- end }}
FROM (
  SELECT
    time, stock_id, alpha_12, returns,
    lag(alpha_12) OVER (PARTITION BY stock_id) AS alpha_prev
  FROM {{ .DB }}.v_alpha_12
)
