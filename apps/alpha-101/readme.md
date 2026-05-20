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

## Dashboards

Two dashboards are installed:

- **Realtime Alpha 101** — live prices, latest leaderboard, alpha over time
- **Alpha #1 Backtest** — summary metrics, per-stock PnL, portfolio PnL per 30s, per-stock PnL over time

## Inspect the live signal

```sql
SELECT time, stock_id, alpha_1 FROM alpha_101.v_alpha_1 LIMIT 10 BY time;
```

## Backtest report (ad-hoc)

The backtest dashboard renders the same numbers continuously, but you can also run a one-shot report against the full retained history:

```sql
SELECT
  count()                                                  AS n_obs,
  uniq(stock_id)                                           AS n_stocks,
  min(time)                                                AS t_start,
  max(time)                                                AS t_end,
  round(sum(pnl), 6)                                       AS cum_pnl,
  round(avg(pnl), 8)                                       AS mean_pnl_per_obs,
  round(stddev_pop(pnl), 8)                                AS std_pnl,
  round(avg(pnl) / nullif(stddev_pop(pnl), 0), 4)          AS sharpe_per_obs,
  round(count_if(pnl > 0) * 100.0 / count(), 2)            AS hit_rate_pct,
  round(min(pnl), 6)                                       AS worst_obs,
  round(max(pnl), 6)                                       AS best_obs
FROM alpha_101.v_backtest
WHERE pnl IS NOT NULL
  AND time < now()
SETTINGS seek_to = 'earliest', query_mode = 'table'
```

Pipe it through `curl` (the `query_mode = 'table'` setting makes the streaming query terminate after sweeping history, so it returns a single row of results):

```bash
echo "<sql above>" | \
  curl -s -u 'proton:proton@t+' --data-binary @- \
       "http://localhost:8123/?default_format=PrettyCompact"
```

Tighten the window for a specific period:

```sql
WHERE pnl IS NOT NULL
  AND time BETWEEN '2026-05-20 21:00:00' AND '2026-05-20 21:10:00'
```

| Metric | Meaning |
|---|---|
| `n_obs`, `n_stocks` | Sample size |
| `t_start`, `t_end` | Backtest window |
| `cum_pnl` | Σ `alpha_prev * returns` across all stocks & buckets |
| `mean_pnl_per_obs`, `std_pnl` | Per-observation mean and stddev |
| `sharpe_per_obs` | `mean / std` (per-period; multiply by `√(periods/year)` to annualize) |
| `hit_rate_pct` | % of observations where the alpha-weighted bet was profitable |
| `worst_obs`, `best_obs` | Most negative / most positive single-observation PnL |

### Expected outcome on synthetic data

The source is independent random ticks with no genuine predictive structure, so Alpha #1 has no edge to exploit. A representative run over ~2 hours:

| Metric | Value |
|---|---|
| `hit_rate_pct` | ≈ 50% |
| `sharpe_per_obs` | ≈ 0 |
| `cum_pnl` | small, sign varies run-to-run |

That's the **correct** null result — it confirms the backtest math is sound. To see a real edge, point the pipeline at real market data (replace the random source with an external stream, e.g. the Coinbase WebSocket connector in `apps/market-data`).
