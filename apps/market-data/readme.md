# Market Data (Coinbase)

**ID:** `io.timeplus.market-data`  
**Version:** `1.0.0`  
**DB:** `market_data`

Real-time crypto market data from the Coinbase WebSocket feed. Provides OHLC candlesticks, RSI, a mutable OHLC key-value stream, 1-second bars, and ten quantitative alpha signals.

## Directory structure

```
market-data/
├── Makefile
├── manifest.yaml
├── ddl/
│   ├── 001_python_package_json5.sql       system — install json5
│   ├── 002_python_package_websocket.sql   system — install websocket-client
│   ├── 003_coinbase_websocket.sql         external_stream — Python WebSocket source
│   ├── 004_coinbase_tickers.sql           stream — raw ticker events (24h TTL)
│   ├── 005_mv_tickers_extracted.sql       materialized_view — JSON → coinbase_tickers
│   ├── 006_v_btc_ohlc_1m.sql             view — BTC 1-min OHLC
│   ├── 007_v_btc_1m_ret.sql              view — BTC 1-min returns
│   ├── 008_v_btc_1m_rsi.sql              view — BTC 14-period RSI
│   ├── 009_coinbase_ohlc_1m_vkv.sql      mutable_stream — OHLC by symbol (PK: time, symbol)
│   ├── 010_mv_ohlc_by_symbol.sql         materialized_view — all symbols → ohlc_1m_vkv
│   ├── 011_coinbase_1s.sql               stream — 1-second bars (4h TTL)
│   ├── 012_mv_coinbase_1s.sql            materialized_view — tickers → 1s bars
│   ├── 013_alpha_momentum.sql            view — 3s vs 10s return momentum
│   ├── 014_alpha_mean_reversion.sql      view — deviation from 20s MA
│   ├── 015_alpha_spread_pressure.sql     view — trade location & book imbalance
│   ├── 016_alpha_ma_crossover.sql        view — 5s/20s MA crossover
│   ├── 017_alpha_price_acceleration.sql  view — price velocity delta
│   ├── 018_alpha_bollinger_position.sql  view — position within Bollinger bands
│   ├── 019_alpha_vwap.sql               view — price vs 20s VWAP
│   ├── 020_alpha_trade_flow.sql          view — buy/sell volume imbalance
│   ├── 021_alpha_spread_regime.sql       view — spread vs 20s avg spread
│   ├── 022_alpha_volume_spike.sql        view — volume spike × price direction
│   └── 023_alpha_composite.sql           view — equal-weight average of 4 signals
└── dashboards/
    └── coinbase.json                      OHLC, Returns, RSI, and trending table panels
```

## Resource dependency order

```
python packages (json5, websocket-client)
  └── coinbase_websocket_read_connector   (external stream — Coinbase WSS)
        └── mv_coinbase_tickers_extracted (MV → coinbase_tickers)
              ├── coinbase_tickers        (raw tickers, 24h TTL)
              │     ├── v_coinbase_btc_ohlc_1m → v_coinbase_btc_1m_ret → v_coinbase_btc_1m_rsi
              │     ├── coinbase_ohlc_1m_vkv ← mv_ohlc_by_symbol
              │     └── coinbase_1s ← mv_coinbase_1s
              │           └── v_alpha_momentum, mean_reversion, spread_pressure,
              │               ma_crossover, price_acceleration, bollinger_position,
              │               vwap, trade_flow, spread_regime, volume_spike
              │                 └── v_alpha_composite
```

## Install

```bash
# From the app directory
make build    # produces market-data.tpapp
make install  # build + POST to http://localhost:8000

# From the repo root
make build APP=market-data
make install APP=market-data NEUTRON_URL=http://my-host:8000 TENANT=my-tenant

# Manually
curl -X POST http://localhost:8000/default/api/v1beta2/apps/install \
  -F "file=@market-data.tpapp"
```

## Config

| Key | Default | Description |
|-----|---------|-------------|
| `websocket_url` | `wss://ws-feed.exchange.coinbase.com` | Coinbase WebSocket feed URL |
