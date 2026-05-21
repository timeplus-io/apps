CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_market_data
INTO {{ .DB }}.market_data AS
SELECT time, stock_id, price, volume
FROM {{ .DB }}.random_market_data
