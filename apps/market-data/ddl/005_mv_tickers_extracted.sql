CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_coinbase_tickers_extracted
INTO {{ .DB }}.coinbase_tickers
AS
SELECT
  full_payload:best_ask::float       AS best_ask,
  full_payload:product_id            AS product_id,
  full_payload:price::float          AS price,
  full_payload:trade_id::float       AS trade_id,
  full_payload:best_bid::float       AS best_bid,
  full_payload:open_24h::float       AS open_24h,
  full_payload:sequence::float       AS sequence,
  full_payload:volume_30d::float     AS volume_30d,
  full_payload:high_24h::float       AS high_24h,
  full_payload:low_24h::float        AS low_24h,
  full_payload:last_size::float      AS last_size,
  full_payload:side                  AS side,
  full_payload:time                  AS time,
  full_payload:type                  AS type,
  full_payload:volume_24h::float     AS volume_24h,
  full_payload:best_ask_size::float  AS best_ask_size,
  full_payload:best_bid_size::float  AS best_bid_size,
  to_time(time)                      AS _tp_time
FROM {{ .DB }}.coinbase_websocket_read_connector
WHERE full_payload:type = 'ticker';
