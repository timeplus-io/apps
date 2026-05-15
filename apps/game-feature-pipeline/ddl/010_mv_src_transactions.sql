CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_src_transactions
INTO {{ .DB }}.transactions
AS SELECT * FROM {{ .DB }}.src_transactions;
