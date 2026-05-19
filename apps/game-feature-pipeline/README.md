# Real-time ML Feature Pipeline for Game Analytics

A demo of a real-time machine-learning feature pipeline over simulated game events — player action features, transaction features, social engagement features, and composite features for behavior analysis and spend-anomaly detection.

## How it works

Three random streams produce raw events: player actions, transactions, and performance metrics. Materialized views derive rolling features per player (5-minute windows for behavior, 15-minute windows for transactions, plus composite features joining across streams). An alert watches total spend across the last 10 transactions and fires when it exceeds `alert_threshold`.

## Build & install

```bash
make build
make install
```

Or from the repo root: `make build APP=game-feature-pipeline`.

## Config

| key | default | notes |
|---|---|---|
| `player_actions_eps` | `50` | Player actions events/sec |
| `transactions_eps` | `10` | Transactions events/sec |
| `performance_metrics_eps` | `20` | Performance metrics events/sec |
| `stream_ttl_hours` | `24` | TTL on event and feature streams |
| `slack_webhook_url` | `""` | Slack webhook for spend-anomaly alerts (empty = disabled) |
| `alert_threshold` | `750` | USD spend threshold across last 10 txns that triggers an alert |
| `logstore_retention_bytes` | `107374182` | Logstore size per stream (~100 MB) |
| `logstore_retention_ms` | `300000` | Logstore retention (5 min) |
