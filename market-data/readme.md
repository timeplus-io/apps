---

## Market Data (Coinbase)

**ID:** `io.timeplus.market-data`  
**Version:** `1.0.0`  
**DB:** `market_data`

Real-time crypto market data from the Coinbase WebSocket feed. Provides OHLC candlesticks, RSI, order book snapshots, VWAP, and eight quantitative alpha signals.

### Directory structure

```
market-data.tpapp (zip)
├── manifest.yaml
├── ddl/
│   ├── 001_python_packages.sql
│   ├── 002_coinbase_websocket.sql
│   ├── 003_coinbase_tickers.sql
│   ├── 004_mv_tickers_extracted.sql
│   ├── 005_v_btc_ohlc_1m.sql
│   ├── 006_v_btc_1m_ret.sql
│   ├── 007_v_btc_1m_rsi.sql
│   ├── 008_coinbase_ohlc_1m_vkv.sql
│   ├── 009_mv_ohlc_by_symbol.sql
│   ├── 010_coinbase_1s.sql
│   ├── 011_mv_coinbase_1s.sql
│   ├── 012_alpha_momentum.sql
│   ├── 013_alpha_mean_reversion.sql
│   ├── 014_alpha_spread_pressure.sql
│   ├── 015_alpha_ma_crossover.sql
│   ├── 016_alpha_price_acceleration.sql
│   ├── 017_alpha_bollinger_position.sql
│   ├── 018_alpha_vwap.sql
│   ├── 019_alpha_trade_flow.sql
│   ├── 020_alpha_spread_regime.sql
│   ├── 021_alpha_volume_spike.sql
│   └── 022_alpha_composite.sql
└── dashboards/
    └── coinbase.json
```

### `manifest.yaml`

```yaml
package_format_version: 1
id: io.timeplus.market-data
name: Market Data (Coinbase)
version: 1.0.0
author: Timeplus
description: >
  Real-time crypto market data from Coinbase WebSocket — OHLC candlesticks,
  RSI, order book snapshots, VWAP, and quantitative alpha signals.
db_name: market_data

resources:
  - file: ddl/001_python_packages.sql
    type: system
    name: python_packages
  - file: ddl/002_coinbase_websocket.sql
    type: external_stream
    name: coinbase_websocket_read_connector
  - file: ddl/003_coinbase_tickers.sql
    type: stream
    name: coinbase_tickers
  - file: ddl/004_mv_tickers_extracted.sql
    type: materialized_view
    name: mv_coinbase_tickers_extracted
  - file: ddl/005_v_btc_ohlc_1m.sql
    type: view
    name: v_coinbase_btc_ohlc_1m
  - file: ddl/006_v_btc_1m_ret.sql
    type: view
    name: v_coinbase_btc_1m_ret
  - file: ddl/007_v_btc_1m_rsi.sql
    type: view
    name: v_coinbase_btc_1m_rsi
  - file: ddl/008_coinbase_ohlc_1m_vkv.sql
    type: mutable_stream
    name: coinbase_ohlc_1m_vkv
  - file: ddl/009_mv_ohlc_by_symbol.sql
    type: materialized_view
    name: mv_ohlc_by_symbol
  - file: ddl/010_coinbase_1s.sql
    type: stream
    name: coinbase_1s
  - file: ddl/011_mv_coinbase_1s.sql
    type: materialized_view
    name: mv_coinbase_1s
  - file: ddl/012_alpha_momentum.sql
    type: view
    name: v_alpha_momentum
  - file: ddl/013_alpha_mean_reversion.sql
    type: view
    name: v_alpha_mean_reversion
  - file: ddl/014_alpha_spread_pressure.sql
    type: view
    name: v_alpha_spread_pressure
  - file: ddl/015_alpha_ma_crossover.sql
    type: view
    name: v_alpha_ma_crossover
  - file: ddl/016_alpha_price_acceleration.sql
    type: view
    name: v_alpha_price_acceleration
  - file: ddl/017_alpha_bollinger_position.sql
    type: view
    name: v_alpha_bollinger_position
  - file: ddl/018_alpha_vwap.sql
    type: view
    name: v_alpha_vwap
  - file: ddl/019_alpha_trade_flow.sql
    type: view
    name: v_alpha_trade_flow
  - file: ddl/020_alpha_spread_regime.sql
    type: view
    name: v_alpha_spread_regime
  - file: ddl/021_alpha_volume_spike.sql
    type: view
    name: v_alpha_volume_spike
  - file: ddl/022_alpha_composite.sql
    type: view
    name: v_alpha_composite

dashboards:
  - file: dashboards/coinbase.json
    name: Coinbase Market Data
    description: Real-time OHLC, returns, and RSI for Coinbase crypto pairs
```

### DDL files

#### `ddl/001_python_packages.sql`
```sql
SYSTEM INSTALL PYTHON PACKAGE 'json5>=0.9.6';
SYSTEM INSTALL PYTHON PACKAGE 'websocket-client>=1.4.0';
```

#### `ddl/002_coinbase_websocket.sql`
```sql
CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.coinbase_websocket_read_connector(
  type string,
  product_id string,
  channel string,
  full_payload string,
  received_at datetime64(3)
)
AS $$
import websocket
import json5
import time
from datetime import datetime

def read_coinbase_websocket_stream():
    websocket_url = "wss://ws-feed.exchange.coinbase.com"
    subscription_message = '{"type": "subscribe", "product_ids": ["BTC-USD"], "channels": ["ticker"]}'

    ws = None
    while True:
        try:
            ws = websocket.create_connection(websocket_url)
            ws.send(subscription_message)

            while True:
                message = ws.recv() or ""
                parsed_message = json5.loads(message) or {}

                msg_type = parsed_message.get("type") or ""
                product_id = parsed_message.get("product_id") or ""

                channel_name = ""
                channels = parsed_message.get("channels")
                if msg_type == "subscriptions" and channels:
                    channel_name = ", ".join([c.get("name", "unknown") for c in channels]) or ""
                elif "channel" in parsed_message:
                    channel_name = parsed_message.get("channel") or ""

                yield (
                    msg_type,
                    product_id,
                    channel_name,
                    message,
                    datetime.utcnow(),
                )

        except Exception:
            time.sleep(5)
        finally:
            if ws:
                ws.close()
        time.sleep(1)

$$
SETTINGS type='python', mode='streaming', read_function_name='read_coinbase_websocket_stream';
```

#### `ddl/003_coinbase_tickers.sql`
```sql
CREATE STREAM IF NOT EXISTS {{ .DB }}.coinbase_tickers
(
  `best_ask`      float64,
  `product_id`    string,
  `price`         float64,
  `trade_id`      float64,
  `best_bid`      float64,
  `open_24h`      float64,
  `sequence`      float64,
  `volume_30d`    float64,
  `high_24h`      float64,
  `low_24h`       float64,
  `last_size`     float64,
  `side`          string,
  `time`          string,
  `type`          string,
  `volume_24h`    float64,
  `best_ask_size` float64,
  `best_bid_size` float64
)
TTL to_datetime(_tp_time) + INTERVAL 24 HOUR
SETTINGS logstore_retention_bytes = '107374182', logstore_retention_ms = '300000';
```

#### `ddl/004_mv_tickers_extracted.sql`
```sql
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
```

#### `ddl/005_v_btc_ohlc_1m.sql`
```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_coinbase_btc_ohlc_1m
AS
SELECT
  window_start,
  earliest(price) AS open,
  latest(price)   AS close,
  max(price)      AS high,
  min(price)      AS low
FROM tumble({{ .DB }}.coinbase_tickers, 1m)
WHERE product_id = 'BTC-USD'
  AND _tp_time > (now() - 1h)
GROUP BY window_start;
```

#### `ddl/006_v_btc_1m_ret.sql`
```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_coinbase_btc_1m_ret
AS
SELECT
  window_start AS time,
  close,
  lag(close)                      AS prev_close,
  (close - prev_close) / prev_close AS ret
FROM {{ .DB }}.v_coinbase_btc_ohlc_1m
WHERE prev_close > 0;
```

#### `ddl/007_v_btc_1m_rsi.sql`
```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_coinbase_btc_1m_rsi
AS
SELECT
  time,
  lags(ret, 1, 14)                                              AS rets,
  array_avg(array_map(x -> if(x > 0, x, 0), rets))             AS avg_gains,
  array_avg(array_map(x -> if(x > 0, 0, -x), rets))            AS avg_losses,
  avg_gains / avg_losses                                        AS RS,
  100 - (100 / (1 + RS))                                        AS RSI
FROM {{ .DB }}.v_coinbase_btc_1m_ret;
```

#### `ddl/008_coinbase_ohlc_1m_vkv.sql`
```sql
CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.coinbase_ohlc_1m_vkv
(
  `time`    datetime64(3),
  `symbol`  string,
  `open`    float32,
  `close`   float32,
  `high`    float32,
  `low`     float32,
  `_tp_time` datetime64(3, 'UTC') DEFAULT now64(3, 'UTC')
)
PRIMARY KEY (time, symbol);
```

#### `ddl/009_mv_ohlc_by_symbol.sql`
```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_ohlc_by_symbol
INTO {{ .DB }}.coinbase_ohlc_1m_vkv
AS
SELECT
  window_start       AS time,
  product_id         AS symbol,
  earliest(price)    AS open,
  latest(price)      AS close,
  max(price)         AS high,
  min(price)         AS low
FROM tumble({{ .DB }}.coinbase_tickers, 1m)
WHERE _tp_time > (now() - 1h)
GROUP BY window_start, product_id
EMIT STREAM PERIODIC 250ms;
```

#### `ddl/010_coinbase_1s.sql`
```sql
CREATE STREAM IF NOT EXISTS {{ .DB }}.coinbase_1s
(
  `window_start`   datetime64(3, 'UTC'),
  `product_id`     string,
  `open`           float64,
  `high`           float64,
  `low`            float64,
  `close`          float64,
  `volume`         float64,
  `buy_volume`     float64,
  `sell_volume`    float64,
  `trade_count`    uint64,
  `best_bid`       float64,
  `best_ask`       float64,
  `best_bid_size`  float64,
  `best_ask_size`  float64,
  `spread`         float64,
  `vwap`           float64
)
PARTITION BY to_start_of_hour(_tp_time)
TTL to_datetime(_tp_time) + INTERVAL 4 HOUR
SETTINGS index_granularity = 8192,
         logstore_retention_bytes = '107374182',
         logstore_retention_ms = '300000';
```

#### `ddl/011_mv_coinbase_1s.sql`
```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_coinbase_1s
INTO {{ .DB }}.coinbase_1s
AS
SELECT
  window_start,
  product_id,
  open, high, low, close,
  volume, buy_volume, sell_volume, trade_count,
  best_bid, best_ask, best_bid_size, best_ask_size,
  best_ask - best_bid                          AS spread,
  total_cost / (volume + 0.0001)               AS vwap
FROM (
  SELECT
    window_start,
    product_id,
    earliest(price)                            AS open,
    max(price)                                 AS high,
    min(price)                                 AS low,
    latest(price)                              AS close,
    sum(last_size)                             AS volume,
    sum(if(side = 'buy',  last_size, 0))       AS buy_volume,
    sum(if(side = 'sell', last_size, 0))       AS sell_volume,
    count(*)                                   AS trade_count,
    latest(best_bid)                           AS best_bid,
    latest(best_ask)                           AS best_ask,
    latest(best_bid_size)                      AS best_bid_size,
    latest(best_ask_size)                      AS best_ask_size,
    sum(price * last_size)                     AS total_cost
  FROM tumble({{ .DB }}.coinbase_tickers, 1s)
  GROUP BY window_start, product_id
);
```

#### `ddl/012_alpha_momentum.sql`
```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_momentum AS
SELECT
  product_id,
  time,
  close,
  (close - array_element(lags(close, 3, 3), 1))
    / array_element(lags(close, 3, 3), 1)                               AS return_3s,
  (close - array_element(lags(close, 10, 10), 1))
    / array_element(lags(close, 10, 10), 1)                             AS return_10s,
  ((close - array_element(lags(close, 3, 3), 1)) / array_element(lags(close, 3, 3), 1))
  - ((close - array_element(lags(close, 10, 10), 1)) / array_element(lags(close, 10, 10), 1))
                                                                         AS momentum_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
```

#### `ddl/013_alpha_mean_reversion.sql`
```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_mean_reversion AS
SELECT
  product_id,
  time,
  close,
  array_avg(lags(close, 1, 20))                                         AS ma_20s,
  (close - array_avg(lags(close, 1, 20)))
    / array_avg(lags(close, 1, 20))                                     AS deviation,
  -1 * (close - array_avg(lags(close, 1, 20)))
    / array_avg(lags(close, 1, 20))                                     AS mean_reversion_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
```

#### `ddl/014_alpha_spread_pressure.sql`
```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_spread_pressure AS
SELECT
  product_id,
  time,
  close,
  best_bid,
  best_ask,
  spread * 10000 / close                                                AS spread_bps,
  (close - (best_bid + best_ask) / 2)
    / (spread + 0.0001)                                                 AS trade_location_alpha,
  (best_bid_size - best_ask_size)
    / (best_bid_size + best_ask_size + 0.0001)                         AS book_imbalance_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
```

#### `ddl/015_alpha_ma_crossover.sql`
```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_ma_crossover AS
SELECT
  product_id,
  time,
  close,
  array_avg(lags(close, 0, 4))                                          AS ma_5s,
  array_avg(lags(close, 0, 19))                                         AS ma_20s,
  (array_avg(lags(close, 0, 4)) - array_avg(lags(close, 0, 19)))
    / array_avg(lags(close, 0, 19))                                     AS ma_crossover_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
```

#### `ddl/016_alpha_price_acceleration.sql`
```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_price_acceleration AS
SELECT
  product_id,
  time,
  close,
  (close - array_element(lags(close, 1, 1), 1))                        AS velocity_now,
  (array_element(lags(close, 1, 1), 1) - array_element(lags(close, 2, 2), 1))
                                                                         AS velocity_prev,
  ((close - array_element(lags(close, 1, 1), 1))
   - (array_element(lags(close, 1, 1), 1) - array_element(lags(close, 2, 2), 1)))
    / close                                                              AS acceleration_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
```

#### `ddl/017_alpha_bollinger_position.sql`
```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_bollinger_position AS
SELECT
  product_id,
  time,
  close,
  array_avg(lags(close, 1, 20))                                         AS mean_20s,
  sqrt(array_avg(
    array_map(x -> pow(x - array_avg(lags(close, 1, 20)), 2), lags(close, 1, 20))
  ))                                                                     AS std_dev,
  (close - array_avg(lags(close, 1, 20)))
    / (2 * sqrt(array_avg(
        array_map(x -> pow(x - array_avg(lags(close, 1, 20)), 2), lags(close, 1, 20))
      )) + 0.0001)                                                      AS bollinger_position_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
```

#### `ddl/018_alpha_vwap.sql`
```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_vwap AS
SELECT
  product_id,
  time,
  close,
  vwap,
  array_sum(array_map(
    (p, v) -> p * v,
    lags(vwap, 0, 19),
    lags(volume, 0, 19)
  )) / (array_sum(lags(volume, 0, 19)) + 0.0001)                       AS vwap_20s,
  (close - array_sum(array_map(
    (p, v) -> p * v,
    lags(vwap, 0, 19),
    lags(volume, 0, 19)
  )) / (array_sum(lags(volume, 0, 19)) + 0.0001))
    / close                                                              AS vwap_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
```

#### `ddl/019_alpha_trade_flow.sql`
```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_trade_flow AS
SELECT
  product_id,
  time,
  close,
  buy_volume,
  sell_volume,
  array_sum(lags(buy_volume,  0, 19))                                   AS buy_vol_20s,
  array_sum(lags(sell_volume, 0, 19))                                   AS sell_vol_20s,
  (array_sum(lags(buy_volume, 0, 19)) - array_sum(lags(sell_volume, 0, 19)))
    / (array_sum(lags(volume, 0, 19)) + 0.0001)                        AS trade_flow_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
```

#### `ddl/020_alpha_spread_regime.sql`
```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_spread_regime AS
SELECT
  product_id,
  time,
  close,
  spread,
  array_avg(lags(spread, 1, 20))                                        AS avg_spread_20s,
  spread / (array_avg(lags(spread, 1, 20)) + 0.0001)                   AS spread_ratio,
  -1 * (spread / (array_avg(lags(spread, 1, 20)) + 0.0001) - 1)       AS spread_regime_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
```

#### `ddl/021_alpha_volume_spike.sql`
```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_volume_spike AS
SELECT
  product_id,
  time,
  close,
  volume,
  array_avg(lags(volume, 1, 20))                                        AS avg_volume_20s,
  volume / (array_avg(lags(volume, 1, 20)) + 0.0001)                   AS volume_ratio,
  (volume / (array_avg(lags(volume, 1, 20)) + 0.0001))
    * ((close - array_element(lags(close, 1, 1), 1)) / close)          AS volume_spike_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
```

#### `ddl/022_alpha_composite.sql`
```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_composite AS
SELECT
  product_id,
  time,
  close,
  (close - array_element(lags(close, 3, 3), 1))
    / array_element(lags(close, 3, 3), 1)                               AS momentum,
  -1 * (close - array_avg(lags(close, 1, 20)))
    / array_avg(lags(close, 1, 20))                                     AS mean_rev,
  (best_bid_size - best_ask_size)
    / (best_bid_size + best_ask_size + 0.0001)                         AS book_imb,
  (buy_volume - sell_volume)
    / (volume + 0.0001)                                                  AS flow,
  (
    (close - array_element(lags(close, 3, 3), 1)) / array_element(lags(close, 3, 3), 1)
    + (-1 * (close - array_avg(lags(close, 1, 20))) / array_avg(lags(close, 1, 20)))
    + (best_bid_size - best_ask_size) / (best_bid_size + best_ask_size + 0.0001)
    + (buy_volume - sell_volume) / (volume + 0.0001)
  ) / 4                                                                  AS composite_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
```

### `dashboards/coinbase.json`

The dashboard provides interactive controls and four panels. Controls use `{{filter_product}}`, `{{filter_time_range}}`, and `{{filter_window_size}}` variables wired across all chart queries.

```json
[
  {
    "id": "bad0f748-5b56-4743-9bee-5f2f3ef1269c",
    "title": "new panel",
    "description": "",
    "position": { "h": 1, "nextX": 3, "nextY": 1, "w": 3, "x": 0, "y": 0 },
    "viz_type": "control",
    "viz_content": "",
    "viz_config": {
      "chartType": "selector",
      "defaultValue": "BTC-USD",
      "inlineValues": "BTC-USD,ETC-USD,DAI-USD",
      "label": "Product",
      "labelWidth": "42",
      "target": "filter_product"
    }
  },
  {
    "id": "031da2c1-1089-48b3-91f5-b8f79b288130",
    "title": "new panel",
    "description": "",
    "position": { "h": 1, "nextX": 9, "nextY": 1, "w": 3, "x": 6, "y": 0 },
    "viz_type": "control",
    "viz_content": "",
    "viz_config": {
      "chartType": "selector",
      "defaultValue": "1h",
      "inlineValues": "1m,5m,15m,1h,2h,12h,24h",
      "label": "Time Range",
      "labelWidth": "60",
      "target": "filter_time_range"
    }
  },
  {
    "id": "b3af75db-957d-4c31-89f6-40940cd4de82",
    "title": "new panel",
    "description": "",
    "position": { "h": 1, "nextX": 6, "nextY": 1, "w": 3, "x": 3, "y": 0 },
    "viz_type": "control",
    "viz_content": "",
    "viz_config": {
      "chartType": "selector",
      "defaultValue": "1m",
      "inlineValues": "1s,5s,1m,5m,15m,1h,24h",
      "label": "Window Size",
      "labelWidth": "60",
      "target": "filter_window_size"
    }
  },
  {
    "id": "751e6afe-3337-4e22-95dc-b387b5ecaf9e",
    "title": "OHLC (Open, High, Low, Close)",
    "description": "",
    "position": { "h": 4, "nextX": 6, "nextY": 5, "w": 6, "x": 0, "y": 1 },
    "viz_type": "chart",
    "viz_content": "SELECT\n  window_start as time, earliest(price) AS open, latest(price) AS close, max(price) AS high, min(price) AS low\nFROM\n  tumble(market_data.coinbase_tickers, {{filter_window_size}})\nWHERE product_id = '{{filter_product}}' and _tp_time > now() -{{filter_time_range}}\nGROUP BY\n  window_start",
    "viz_config": {
      "chartType": "ohlc",
      "config": { "xRange": "Infinity", "yRange": { "max": null, "min": null } }
    }
  },
  {
    "id": "d2931af2-b3e6-4abf-8174-6f07858fc84b",
    "title": "Real-time Returns",
    "description": "",
    "position": { "h": 4, "nextX": 12, "nextY": 5, "w": 6, "x": 6, "y": 1 },
    "viz_type": "chart",
    "viz_content": "with ohlc as (\nSELECT\n  window_start as time, earliest(price) AS open, latest(price) AS close, max(price) AS high, min(price) AS low\nFROM\n  tumble(market_data.coinbase_tickers, {{filter_window_size}})\nWHERE product_id = '{{filter_product}}' and _tp_time > now() -{{filter_time_range}}\nGROUP BY\n  window_start\n)\nSELECT\n  time, close, lag(close) AS prev_close, (close - prev_close) / prev_close AS ret\nFROM\n  ohlc\nWHERE\n  prev_close > 0",
    "viz_config": {
      "chartType": "column",
      "config": {
        "dataLabel": false,
        "fractionDigits": 2,
        "gridlines": true,
        "groupType": "stack",
        "legend": false,
        "updateMode": "all",
        "xAxis": "time",
        "xFormat": "LT",
        "yAxis": "ret"
      }
    }
  },
  {
    "id": "d665f406-629e-45cd-a4c7-12ee90ea9b98",
    "title": "RSI (Relative Strength Index)",
    "description": "",
    "position": { "h": 4, "nextX": 6, "nextY": 9, "w": 12, "x": 0, "y": 5 },
    "viz_type": "chart",
    "viz_content": "with ohlc as (\nSELECT\n  window_start as time, earliest(price) AS open, latest(price) AS close, max(price) AS high, min(price) AS low\nFROM\n  tumble(market_data.coinbase_tickers, {{filter_window_size}})\nWHERE product_id = '{{filter_product}}' and _tp_time > now() -{{filter_time_range}}\nGROUP BY\n  window_start\n),\nreturns as (\nSELECT\n  time, close, lag(close) AS prev_close, (close - prev_close) / prev_close AS ret\nFROM\n  ohlc\nWHERE\n  prev_close > 0\n)\nSELECT\n  time,\n  lags(ret, 1, 14) AS rets,\n  array_avg(array_map(x -> if(x > 0, x, 0), rets)) AS avg_gains,\n  array_avg(array_map(x -> if(x > 0, 0, -x), rets)) AS avg_losses,\n  avg_gains / avg_losses AS RS,\n  100 - (100/(1+RS)) as RSI\nFROM returns",
    "viz_config": {
      "chartType": "line",
      "config": {
        "dataLabel": true,
        "fractionDigits": 2,
        "gridlines": true,
        "legend": false,
        "lineStyle": "curve",
        "points": true,
        "xAxis": "time",
        "xRange": "Infinity",
        "yAxis": "RSI"
      }
    }
  },
  {
    "id": "2c925a76-c40e-4893-8f27-c178cabd6287",
    "title": "OHLC Trending Highlight",
    "description": "",
    "position": { "h": 4, "nextX": 12, "nextY": 13, "w": 12, "x": 0, "y": 9 },
    "viz_type": "chart",
    "viz_content": "SELECT\n  window_start as time, product_id, earliest(price) AS open, latest(price) AS close, max(price) AS high, min(price) AS low\nFROM\n  tumble(market_data.coinbase_tickers, {{filter_window_size}})\nWHERE _tp_time > now() -{{filter_time_range}}\nGROUP BY\n  window_start,product_id",
    "viz_config": {
      "chartType": "table",
      "config": {
        "rowCount": 5,
        "tableStyles": {
          "close":      { "show": true, "trend": true, "increaseColor": "green", "decreaseColor": "red", "width": 161 },
          "high":       { "show": true, "trend": true, "increaseColor": "green", "decreaseColor": "red", "width": 166 },
          "low":        { "show": true, "trend": true, "increaseColor": "green", "decreaseColor": "red", "width": 289 },
          "open":       { "show": true, "trend": true, "increaseColor": "green", "decreaseColor": "red", "width": 163 },
          "product_id": { "show": true, "trend": false, "width": 139 },
          "time":       { "show": true, "trend": false, "width": 210 }
        },
        "tableWrap": false,
        "updateKey": "product_id",
        "updateMode": "key"
      }
    }
  }
]
```

### Install

```bash
# Build the package
cd market-data && zip -r ../market-data.tpapp manifest.yaml ddl/ dashboards/

# Install via API
curl -X POST http://localhost:8000/default/api/v1beta2/apps/install \
  -F "file=@market-data.tpapp"
```

### Resource dependency order

```
python_packages
  └── coinbase_websocket_read_connector  (external stream, reads from Coinbase WSS)
        └── mv_coinbase_tickers_extracted  (MV → coinbase_tickers)
              ├── coinbase_tickers  (raw ticker stream, 24h TTL)
              │     ├── v_coinbase_btc_ohlc_1m  → v_coinbase_btc_1m_ret → v_coinbase_btc_1m_rsi
              │     ├── coinbase_ohlc_1m_vkv ← mv_ohlc_by_symbol
              │     └── coinbase_1s ← mv_coinbase_1s
              │           └── v_alpha_* (11 alpha signal views)
              │                 └── v_alpha_composite
```
