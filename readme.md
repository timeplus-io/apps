# Timeplus Apps

A collection of installable Timeplus apps (`.tpapp` packages). Each app bundles a streaming data pipeline — DDL SQL resources and dashboards — into a single zip archive.

## Apps

| App | Description | Downloads |
|-----|-------------|-----------|
| [market-data](apps/market-data/readme.md) | Real-time crypto market data from Coinbase WebSocket — OHLC, RSI, VWAP, and alpha signals | ![Downloads](https://img.shields.io/github/downloads/timeplus-io/apps/total/market-data.tpapp) |
| [github](apps/github/) | Real-time GitHub public events pipeline — hot repos, push activity, and live event feed via PyGithub | ![Downloads](https://img.shields.io/github/downloads/timeplus-io/apps/total/github.tpapp) |
| [cep](apps/cep/) | Complex event processing demo — SQL-based fraud detection and JavaScript UDF pattern matching over simulated event streams | ![Downloads](https://img.shields.io/github/downloads/timeplus-io/apps/total/cep.tpapp) |

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
