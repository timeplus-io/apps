# Realtime Alpha 101

Streaming demo of WorldQuant **Alpha #1** from *101 Formulaic Alphas* (arxiv.org/abs/1601.00991) over a synthetic multi-stock random feed.

Two config knobs: `bucket` (`1s` / `5s` / `1m`, default `1s`) and `num_stocks` (integer 1–10, default `3`).

```
rank(Ts_ArgMax(SignedPower((returns < 0 ? stddev(returns, 20) : close), 2.), 5)) - 0.5
```

## Pipeline

```
random_market_data  →  mv_market_data  →  market_data
       │
       ▼  tumble({{bucket}})
   v_bars  →  v_features  →  v_ts_argmax_5  →  v_alpha_1  →  v_backtest
```

- `v_alpha_1` — the live signal (cross-sectional rank − 0.5)
- `v_backtest` — pairs the previous bucket's alpha with the current bucket's return, exposing `alpha_prev * returns` as the per-stock per-period PnL of a dollar-neutral long-short portfolio

## Install

```bash
make build && make install
```

## Inspect the live signal

```sql
SELECT time, stock_id, alpha_1 FROM alpha_101.v_alpha_1 LIMIT 10 BY time;
```

## Backtest

```bash
make backtest
```

Runs `backtest.sql` against the full history of `v_backtest` (`SETTINGS seek_to='earliest', query_mode='table'`) and reports:

| Metric | Meaning |
|---|---|
| `n_obs`, `n_stocks` | Sample size |
| `t_start`, `t_end` | Backtest window |
| `cum_pnl` | Σ `alpha_prev * returns` across all stocks & buckets |
| `mean_pnl_per_obs`, `std_pnl` | Per-observation mean and stddev |
| `sharpe_per_obs` | `mean / std` (per-period; multiply by `√(periods/year)` to annualize) |
| `hit_rate_pct` | % of observations where the alpha-weighted bet was profitable |
| `worst_obs`, `best_obs` | Most negative / most positive single-observation PnL |

Edit the `WHERE` clause in `backtest.sql` to scope the window:

```sql
WHERE pnl IS NOT NULL
  AND time BETWEEN '2026-05-20 21:00:00' AND '2026-05-20 21:10:00'
```

### Expected outcome on synthetic data

The data source is independent random ticks with no genuine predictive structure, so Alpha #1 has no edge to exploit. A representative run over ~7 minutes:

| Metric | Value |
|---|---|
| `hit_rate_pct` | ≈ 50% |
| `sharpe_per_obs` | ≈ 0 |
| `cum_pnl` | small, sign varies run-to-run |

That's the **correct** null result — it confirms the backtest math is sound. To see a real edge, point the pipeline at real market data (replace the random source with an external stream).
