# Timeplus Apps

A collection of installable Timeplus apps (`.tpapp` packages). Each app bundles a streaming data pipeline — DDL SQL resources and dashboards — into a single zip archive.

## Apps

| App | Description | Downloads |
|-----|-------------|-----------|
| [market-data](apps/market-data/README.md) | Real-time crypto market data from Coinbase WebSocket — OHLC candlesticks, RSI, VWAP, and alpha signals | ![Downloads](https://img.shields.io/github/downloads/timeplus-io/apps/latest/market-data.tpapp?label=downloads) |
| [github](apps/github/) | Real-time GitHub public events pipeline — hot repos, push activity, and live event feed via PyGithub | ![Downloads](https://img.shields.io/github/downloads/timeplus-io/apps/latest/github.tpapp?label=downloads) |
| [cep](apps/cep/) | Complex event processing demo — SQL-based fraud detection and JavaScript UDF pattern matching over simulated event streams | ![Downloads](https://img.shields.io/github/downloads/timeplus-io/apps/latest/cep.tpapp?label=downloads) |
| [hacker-news](apps/hacker-news/) | Continuously ingests Hacker News posts and comments via the Firebase API — trending stories, active users, and post-type distributions | ![Downloads](https://img.shields.io/github/downloads/timeplus-io/apps/latest/hacker-news.tpapp?label=downloads) |
| [invest-insights](apps/invest-insights/) | Real-time trading monitoring — order management, position tracking, continuous auction participation rate, and live P&L | ![Downloads](https://img.shields.io/github/downloads/timeplus-io/apps/latest/invest-insights.tpapp?label=downloads) |
| [cisco-asa-ddos](apps/cisco-asa-ddos/) | Real-time DDoS detection from simulated Cisco ASA firewall logs — dynamic per-IP baselines, spike detection, and webhook alerting | ![Downloads](https://img.shields.io/github/downloads/timeplus-io/apps/latest/cisco-asa-ddos.tpapp?label=downloads) |
| [game-feature-pipeline](apps/game-feature-pipeline/) | Real-time ML feature pipeline for game analytics — player actions, transactions, social engagement, and spend anomaly detection | ![Downloads](https://img.shields.io/github/downloads/timeplus-io/apps/latest/game-feature-pipeline.tpapp?label=downloads) |

## Build & Install

```bash
# Build an app (default: market-data)
make build APP=<name>

# Build and install to a local Timeplus instance
make install APP=<name>

# Override the target instance
make install APP=<name> NEUTRON_URL=http://my-host:8000 TENANT=my-tenant
```

## Adding a New App

1. Create `apps/<your-app>/` with `manifest.yaml`, `ddl/`, and `dashboards/`
2. Copy the `Makefile` from an existing app and update `APP_NAME`
3. Run `make build APP=<your-app>` from the repo root
