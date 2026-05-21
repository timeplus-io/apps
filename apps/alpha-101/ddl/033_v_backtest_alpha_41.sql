CREATE OR REPLACE VIEW {{ .DB }}.v_backtest_alpha_41 AS
SELECT
  time, stock_id, alpha_41, returns, alpha_prev,
{{- if eq .Config.strategy "sign" }}
  sign(alpha_prev) * returns AS pnl
{{- else }}
  alpha_prev * returns AS pnl
{{- end }}
FROM (
  SELECT
    time, stock_id, alpha_41, returns,
    lag(alpha_41) OVER (PARTITION BY stock_id) AS alpha_prev
  FROM {{ .DB }}.v_alpha_41
)
