# Realtime Alpha 101

Streaming demo of WorldQuant alphas from *101 Formulaic Alphas* (arxiv.org/abs/1601.00991) over a synthetic multi-stock random feed. Currently implements **10 alphas** (#1, #2, #3, #4, #6, #9, #12, #22, #41, #54), chosen to span different streaming-SQL patterns. All share the same upstream data pipeline.

Three config knobs:

| Key | Type | Default | Choices / Range | Meaning |
|---|---|---|---|---|
| `bucket` | choice | `1s` | `1s` / `5s` / `1m` | Tumble window size for bars |
| `num_stocks` | integer | `3` | `2`–`10` | Number of simulated stocks (mean-zero alpha needs N ≥ 2) |
| `strategy` | choice | `linear` | `linear` / `sign` | How alpha maps to a position in the backtest (see below) |

## Alphas implemented

Each row links the formula to the streaming-SQL pattern it demonstrates.

| # | Formula | Streaming-SQL pattern showcased |
|---|---------|----------------------------------|
| **1** | `rank(ts_argmax(signed_power(returns<0 ? stddev(returns,20) : close, 2.), 5)) - 0.5` | `lags` window + `signed_power` + `array_first_index` for ts_argmax + cross-sectional rank via `group_array + array_sort + ARRAY JOIN array_enumerate` |
| **2** | `-1 * correlation(rank(delta(log(volume), 2)), rank((close-open)/open), 6)` | Cross-sectional rank of two derived features per bucket, then per-stock 6-bucket Pearson correlation via `array_reduce('avg', array_map(...))` |
| **3** | `-1 * correlation(rank(open), rank(volume), 10)` | Same cross-sectional-rank-then-correlation pattern as #2 but with **raw OHLC inputs** and a 10-bucket window |
| **4** | `-1 * ts_rank(rank(low), 9)` | **Time-series rank within a rolling window** — `array_count(x -> x <= current, lags(_, 0, 8))` |
| **6** | `-1 * correlation(open, volume, 10)` | **Raw-value** rolling Pearson correlation (no rank step) — contrast with #2 and #3 |
| **9** | nested-if(`ts_min(Δclose, 5) > 0`, Δclose, if(`ts_max(Δclose, 5) < 0`, Δclose, −Δclose)) | **Rolling min/max** via `array_min`/`array_max` over `lags(_, 0, 4)` + `multi_if` for nested conditionals |
| **12** | `sign(Δvolume) × −Δclose` | **Minimal alpha** — single-step deltas via `lags(_, 1, 1)`, `sign()`, multiplication; tiny SQL footprint |
| **22** | `-1 * delta(correlation(high, volume, 5), 5) * rank(stddev(close, 20))` | **Chained derived series:** rolling correlation → `delta` of correlation × cross-sectional rank of rolling stddev |
| **41** | `√(high × low) − vwap` | **VWAP derivation** in `v_bars` (`sum(price * volume) / sum(volume)`) + intra-bar nonlinear |
| **54** | `-1 × (low - close) × open⁵ / ((low - high) × close⁵)` | **Pure intra-bar nonlinear OHLC** — no lags, no aggregation, all instantaneous |

## Pipeline

Shared upstream:

```
random_market_data  →  mv_market_data  →  market_data  →  v_bars
                                                    (time, stock_id,
                                                     open, close, high, low,
                                                     volume, vwap)
```

Per-alpha branches all follow the same shape:

```
v_bars
  →  v_features_alpha_N    (per-stock features + close-to-close returns)
  →  [v_ranks_alpha_N]     (optional: cross-sectional ranks per bucket)
  →  v_alpha_N             (the signal itself)
  →  v_backtest_alpha_N    (pairs lag(alpha) × returns, branched on strategy)
```

Simpler alphas (#12, #41, #54) skip the features and ranks layers — they compute everything in a single view from `v_bars`.

## Install

```bash
make build && make install
```

Override config at install time with `config[<key>]=<value>` form fields:

```bash
make build
curl -X POST http://localhost:8000/default/api/v1beta2/apps/install \
  -F "file=@alpha-101.tpapp" \
  -F "config[strategy]=sign" \
  -F "config[num_stocks]=5" \
  -F "config[bucket]=5s"
```

## Strategy

The `strategy` config controls how each bucket's alpha signal becomes a position weight in `v_backtest`:

- **`linear` (default)** — `pnl = alpha_prev × returns`. Continuous weighting: the magnitude of the rank matters. Mathematically optimal for capturing a linear signal, sensitive to alpha-scaling.
- **`sign`** — `pnl = sign(alpha_prev) × returns`. Equal-magnitude long/short: only the direction of the alpha matters. More robust to noisy alphas; ignores rank-magnitude information.

The alpha itself is mean-zero by construction (`(rank − 1) / (N − 1) − 0.5`), so both strategies are dollar-neutral on average across stocks per bucket.

## Dashboards

Two dashboards are installed; each has an **Alpha** dropdown so a single dashboard serves all 10 alphas (`1, 2, 3, 4, 6, 9, 12, 22, 41, 54`):

- **Realtime Alpha 101** — live prices + volume (filtered by selected stock), alpha leaderboard + alpha over time (filtered by selected alpha)
- **Alpha 101 Backtest** — t-stat tile, summary metrics, per-stock PnL, portfolio PnL per 30s, per-stock PnL over time (filtered by selected alpha)

The Alpha dropdown writes the `{{filter_alpha}}` variable, which the panel queries interpolate into the view name — e.g. `FROM alpha_101.v_alpha_{{filter_alpha}}` resolves to `v_alpha_1` … `v_alpha_54` depending on the dropdown selection. Adding Alpha #N to this app means:
1. dropping a new DDL chain into `ddl/0XX_v_features_alpha_N.sql`, optionally `0XX_v_ranks_alpha_N.sql`, `0XX_v_alpha_N.sql`, `0XX_v_backtest_alpha_N.sql`;
2. registering them in `manifest.yaml`;
3. appending `,N` to each dropdown's `inlineValues`.

No new dashboard files needed — both existing dashboards pick up the new alpha automatically.

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
  round(avg(pnl) / null_if(stddev_pop(pnl), 0), 4)         AS sharpe_per_obs,
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

### What each metric means

Each row in `v_backtest` is one **stock-bucket observation** — alpha at `t−1` paired with the return from `t−1` to `t`, multiplied to give `pnl = alpha_prev × returns`. With N stocks at the configured bucket size over T seconds, you get ≈ `N × T / bucket` observations (after the first row per stock, where `lag(alpha)` is null, is dropped by `WHERE pnl IS NOT NULL`). Every aggregate below is computed across those observations.

#### Sample size

- **`n_obs`** — number of stock-bucket observations included. `n_obs ≈ n_stocks × n_buckets`. Drives the statistical confidence of every other metric: at `n_obs = 100` the Sharpe is noise; at `n_obs = 100 000` it's an estimate worth reading.
- **`n_stocks`** — distinct `stock_id` values seen. Should match the `num_stocks` config.
- **`t_start`, `t_end`** — the earliest and latest event time included. The window's wall-clock span is `t_end − t_start`; total *bucket* count is that span divided by the configured `bucket`.

#### PnL aggregates

- **`cum_pnl = Σ pnl`** — total P&L summed across every stock-bucket. Dimensionless by default; reads as dollars if you interpret `alpha_prev` as dollars allocated per stock per bucket. This is what the dashboard's running totals report. Scale linearly to a real book size — `cum_pnl = 0.10` on alpha units means $100 on a $1 000-per-alpha-unit book.
- **`mean_pnl_per_obs = avg(pnl)`** — expected P&L *per stock-bucket*, i.e. `cum_pnl / n_obs`. The "average bet" return. On a tradable alpha this is positive and meaningfully larger than 0; on random data it sits within `±std_pnl / √n_obs` of 0.
- **`std_pnl = stddev_pop(pnl)`** — standard deviation of the per-observation P&L: how noisy each individual bet is. Roughly `|alpha| × |return|` in magnitude. Useful as the denominator for the Sharpe and as a quick "is the bet size sane" check.
- **`worst_obs`, `best_obs`** — the most negative and most positive single-observation P&L over the window. Sanity check for tail behavior: on this synthetic feed they should be ~`±1%` (`±0.5 × ±2%` per-bucket return); much larger values suggest data spikes or an upstream computation error.

#### Skill metrics

- **`sharpe_per_obs = mean_pnl / std_pnl`** — per-observation Sharpe ratio, **not annualized**. Multiply by `√(periods_per_year)` to compare with industry-quoted Sharpes:
  - 1s buckets, 24/7 trading: `× √(365 × 86 400) ≈ × 5 580`
  - 5s buckets, 24/7: `× √(365 × 17 280) ≈ × 2 500`
  - 1m buckets, 24/7: `× √(365 × 1 440) ≈ × 720`
  - 1m buckets, equity trading hours (~6.5 h/day, 252 days): `× √(252 × 6.5 × 60) ≈ × 313`

  This is the **per-observation** Sharpe — it treats each `(stock, time)` as independent. For a true **portfolio Sharpe** (one number for the whole book over time, accounting for stock-correlation within the same bucket), aggregate to per-bucket P&L first:
  ```sql
  SELECT avg(bucket_pnl) / null_if(stddev_pop(bucket_pnl), 0) AS portfolio_sharpe_per_bucket
  FROM (
    SELECT time, sum(pnl) AS bucket_pnl
    FROM alpha_101.v_backtest WHERE pnl IS NOT NULL
    GROUP BY time
  ) SETTINGS seek_to='earliest', query_mode='table'
  ```
  Portfolio Sharpe is the more standard reporting metric on a real desk; `sharpe_per_obs` is a finer-grained per-bet diagnostic.

- **`hit_rate_pct = count(pnl > 0) / count() × 100`** — % of observations where the alpha-weighted bet was profitable. Read alongside `mean_pnl`:
  - 50% on noise; >50% suggests directional skill; <50% means you should flip the sign of the alpha.
  - **Ignores magnitude**, so a 51% hit rate that misses big can still lose money. A 49% rate with skewed wins can still print positive `cum_pnl`. Always pair with mean / Sharpe; never read alone.

- **`t_stat = avg(pnl) / stddev_pop(pnl) × √n_obs`** — t-statistic on the per-observation mean P&L, i.e. the dashboard's *Edge t-stat* tile. Tests "is the mean bet return distinguishable from zero?" Algebraically equal to `sharpe_per_obs × √n_obs`. Standard reading-the-tea-leaves thresholds:

  | \|t\| | Interpretation |
  |---|---|
  | < 2 | Indistinguishable from noise |
  | **2** | Traditional 5% significance — "interesting" |
  | **3** | WorldQuant / Alphathon bar — commonly cited threshold for a "real" alpha |
  | **3.5 – 4** | Bar after multiple-testing correction when you've tried ~100 alphas (Bailey & López de Prado *deflated Sharpe*). The *101 Formulaic Alphas* paper tested 101 candidates, so the honest threshold for any single one of them lives here, not at 2. |
  | > 5 | Very strong — or a bug. Audit for look-ahead, label leakage, or survivorship before believing it. |

  Two caveats specific to this app:

  1. **Bar autocorrelation inflates `t_stat`.** The `√n_obs` factor assumes IID observations. On 1s / 5s bars the price (and so the alpha-weighted return) is heavily autocorrelated across consecutive buckets, so the *effective* sample size is much smaller than `n_obs`. The naïve t-stat above will look impressive while meaning very little. For an honest figure, either aggregate to non-overlapping daily P&L before computing t, or use a Newey-West / block-bootstrap standard error.
  2. **Synthetic data has no true alpha.** `random_market_data` is an independent random walk, so the population t-stat is zero by construction. Any large \|t\| you see on this feed is sampling noise. To actually evaluate the threshold, repoint the pipeline at real market data (e.g. the Coinbase external stream from `apps/market-data`).

### Expected outcome on synthetic data

The source is independent random ticks with no genuine predictive structure, so no alpha has an edge to exploit. A representative run over ~2 hours:

| Metric | Value |
|---|---|
| `hit_rate_pct` | ≈ 50% |
| `sharpe_per_obs` | ≈ 0 |
| `t_stat` | within ±2 most of the time (it's noise — \|t\| > 3 on this feed is a flag, not a finding) |
| `cum_pnl` | small, sign varies run-to-run |

That's the **correct** null result — it confirms the backtest math is sound. To see a real edge, point the pipeline at real market data (replace the random source with an external stream, e.g. the Coinbase WebSocket connector in `apps/market-data`).

### Caveat: alphas that operate on raw price levels are degenerate on this data

The random source assigns each stock a fixed price band (`[50, 80, 120, 200, …]` with only ±0.5% tick noise), so per-stock price ranges *never overlap*. STOCK_0's `low` is always lowest, STOCK_2's is always highest, every bucket forever. That breaks **cross-sectional rank of price levels** for:

| Alpha | Why it's degenerate here |
|---|---|
| **#3** `corr(rank(open), rank(vol), 10)` | `rank(open)` is a constant per stock → correlation between a constant series and any other series is `0/0` → mostly null `alpha_3` |
| **#4** `−ts_rank(rank(low), 9)` | `rank(low)` is a constant per stock → `ts_rank` always returns 9/9 in steady state → `alpha_4 = −1.0` always (with a brief transient `−1/9, −2/9, …` during the 9-bucket warmup) |
| **#6** `−corr(open, volume, 10)` | raw `open` ≈ stock's base price (constant + 0.5% jitter); correlation with random volume ≈ 0 → `alpha_6 ≈ 0` always |

The implementations are **correct** — they're honest about there being no information to extract when the input series is constant. On real market data where similar-cap stocks compete on rank, these alphas produce meaningful varying values.

The alphas that *do* produce meaningful varying signals on this synthetic feed are the ones operating on **returns, deltas, or intra-bar quantities** rather than raw price levels: **#1, #2, #9, #12, #22, #41, #54**. Those are the ones to watch when validating that the pipeline works end-to-end on streaming SQL.

**To make #3/#4/#6 non-degenerate without leaving synthetic data:** change `random_market_data` so all stocks share a single base price (e.g. `100.0 + rand_normal(0.0, 3.0)`) — the cross-sectional ranks then rotate randomly each bucket. This was tried and reverted to preserve the visual differentiation between stocks on the Live Prices chart; the degeneracy is a fair price for that.
