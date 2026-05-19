# Real-time Investment Insights

A trading-monitoring demo — order management, position tracking, market quotes, continuous auction participation rate, and live P&L. Data is generated internally via random streams, so the app runs without any external market data feed.

## How it works

Two random streams produce orders and quotes at configurable rates. Materialized views derive executions, positions, and live P&L. A scheduled task recomputes the portfolio baseline (`pre_value`) periodically so P&L can be expressed as a delta from a known starting point.

## Build & install

```bash
make build
make install
```

Or from the repo root: `make build APP=invest-insights`.

## Config

| key | default | notes |
|---|---|---|
| `order_eps` | `1200` | Order stream events/sec |
| `quote_eps` | `3000` | Quote stream events/sec |
| `stream_ttl_hours` | `4` | TTL on order and execution streams |
| `pre_value_schedule_hours` | `24` | How often the `pre_value` baseline task runs |
| `pre_value_timeout_minutes` | `2` | Timeout per `pre_value` run |
| `logstore_retention_bytes` | `107374182` | Logstore size per stream (~100 MB) |
| `logstore_retention_ms` | `300000` | Logstore retention (5 min) |

## Dashboard

`dashboards/main.json` — real-time trading metrics, participation rate, and P&L.
