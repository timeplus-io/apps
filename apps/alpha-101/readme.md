# Realtime Alpha 101

Streaming demo of WorldQuant **Alpha #1** from *101 Formulaic Alphas* (arxiv.org/abs/1601.00991) over a synthetic 10-stock random feed.

```
rank(Ts_ArgMax(SignedPower((returns < 0 ? stddev(returns, 20) : close), 2.), 5)) - 0.5
```

## Pipeline

`random_market_data` (eps=100) → `mv_market_data` → `market_data` → `v_bars` (tumble at `bucket`) → `v_features` (returns, σ₂₀, signed_power) → `v_ts_argmax_5` (argmax over last 5) → `v_alpha_1` (cross-sectional rank − 0.5).

`bucket` is a configurable parameter (`1s` / `5s` / `1m`, default `1s`).

## Install

```bash
make build && make install
```

## Inspect

```sql
SELECT time, stock_id, alpha_1 FROM alpha_101.v_alpha_1 LIMIT 10 BY time;
```
