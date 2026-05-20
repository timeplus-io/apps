# Alpha 101 Demo — Design

**Status:** Approved
**Date:** 2026-05-20
**Branch:** `feature/24-alpha-101-demo`

## Goal

Implement WorldQuant **Alpha #1** from the *101 Formulaic Alphas* paper as a self-contained Timeplus app. The app demonstrates how to translate a traditionally daily-bar, cross-sectional alpha into a real-time streaming pipeline using tumble windows + `lag`/`lags` + array functions.

**WQ Alpha #1:**

```
rank(Ts_ArgMax(SignedPower((returns < 0 ? stddev(returns, 20) : close), 2.), 5)) - 0.5
```

## Scope

- Self-contained `.tpapp` package at `apps/alpha-101/`.
- Synthetic data — no external feeds, no API keys.
- One alpha (Alpha #1) end-to-end. Additional alphas can be added as sibling views later.
- A minimal dashboard for live inspection.

Out of scope: backtesting framework, additional alphas, parameter sweeps, deployment automation.

## Architecture

```
random_market_data (CREATE RANDOM STREAM, eps=100)
        │   columns: time, stock_id, price
        ▼
mv_market_data ─────────► market_data           (append-only stream, 1h TTL)
                                │
                                ▼  tumble(1s) GROUP BY window_start, stock_id
                          v_bars_1s             (time, stock_id, close)
                                │
                                ▼  PARTITION BY stock_id + lags
                          v_features            (returns, sigma_ret_20, signed_power)
                                │
                                ▼  lags(signed_power, 0, 4) → 5-element array
                          v_ts_argmax_5         (ts_argmax 1..5)
                                │
                                ▼  tumble(1s) GROUP BY window_start (cross-sectional)
                          v_alpha_1             (alpha_1 = rank/N - 0.5)
```

**Configuration:** 10 simulated stocks (STOCK_0 .. STOCK_9), 1-second bars, 20-bar rolling stddev, 5-bar argmax window. All hardcoded; no `config` parameters for the demo.

## Components

### 1. `random_market_data` — random source

```sql
CREATE RANDOM STREAM IF NOT EXISTS {{ .DB }}.random_market_data
(
  `time`     datetime64(3, 'UTC') DEFAULT now64(3, 'UTC'),
  `stock_id` string DEFAULT 'STOCK_' || to_string(rand(0) % 10),
  `price`    float64 DEFAULT round(
    array_element(
      [50.0, 80.0, 120.0, 200.0, 350.0, 500.0, 750.0, 1000.0, 1500.0, 2500.0],
      (rand(0) % 10) + 1
    ) * (1 + rand_normal(0.0, 0.005)),
    4)
)
SETTINGS eps = 100;
```

Same `rand(0)` seed couples `stock_id` with the base-price index — each stock gets a stable base price; `rand_normal` adds ±0.5% Gaussian noise per tick.

### 2. `market_data` — persistent append-only stream

```sql
CREATE STREAM IF NOT EXISTS {{ .DB }}.market_data
(
  `time`     datetime64(3, 'UTC'),
  `stock_id` string,
  `price`    float64
)
PARTITION BY to_start_of_hour(_tp_time)
TTL to_datetime(_tp_time) + INTERVAL 1 HOUR
SETTINGS logstore_retention_ms = '3600000';
```

### 3. `mv_market_data` — pipe random into persistent stream

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_market_data
INTO {{ .DB }}.market_data AS
SELECT time, stock_id, price
FROM {{ .DB }}.random_market_data;
```

### 4. `v_bars_1s` — 1-second OHLC-style tumble (close only)

```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_bars_1s AS
SELECT
  window_start AS time,
  stock_id,
  latest(price) AS close
FROM tumble({{ .DB }}.market_data, 1s)
GROUP BY window_start, stock_id;
```

### 5. `v_features` — returns, 20-bar return stddev, signed-power

```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_features AS
SELECT
  time,
  stock_id,
  close,
  returns,
  sigma_ret_20,
  cond,
  sign(cond) * cond * cond AS signed_power
FROM (
  SELECT
    time,
    stock_id,
    close,
    (close - array_element(lags(close, 1, 1), 1))
      / nullif(array_element(lags(close, 1, 1), 1), 0)             AS returns,
    array_stddev_pop(
      array_map(i ->
        (array_element(lags(close, i, i), 1)
         - array_element(lags(close, i + 1, i + 1), 1))
        / nullif(array_element(lags(close, i + 1, i + 1), 1), 0),
        range(0, 20))
    )                                                              AS sigma_ret_20,
    if(returns < 0, sigma_ret_20, close)                           AS cond
  FROM {{ .DB }}.v_bars_1s
  PARTITION BY stock_id
);
```

**Risk:** the `array_map(i -> lags(close, i, i), range(0, 20))` pattern relies on `lags` accepting a row-level integer argument. If `lags` requires constant lag offsets, fall back to materializing a single `lags(close, 0, 20)` array and computing returns inside `array_map` over that array. Will be validated live before locking the syntax.

### 6. `v_ts_argmax_5` — position of max in last 5 signed-power values

```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_ts_argmax_5 AS
SELECT
  time,
  stock_id,
  signed_power,
  sp5,
  array_first_index(x -> x = array_max(sp5), sp5) AS ts_argmax
FROM (
  SELECT
    time,
    stock_id,
    signed_power,
    lags(signed_power, 0, 4) AS sp5
  FROM {{ .DB }}.v_features
  PARTITION BY stock_id
);
```

`ts_argmax ∈ {1..5}` — index 1 is the most recent bucket per the `lags` convention.

### 7. `v_alpha_1` — cross-sectional rank − 0.5

```sql
CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_1 AS
WITH ranked AS (
  SELECT
    window_start AS time,
    array_sort(p -> p.2, group_array((stock_id, ts_argmax))) AS sorted_pairs,
    length(group_array(stock_id))                            AS n
  FROM tumble({{ .DB }}.v_ts_argmax_5, 1s)
  GROUP BY window_start
)
SELECT
  time,
  sorted_pairs[idx].1                AS stock_id,
  cast(idx, 'float64') / n - 0.5     AS alpha_1
FROM ranked
ARRAY JOIN array_enumerate(sorted_pairs) AS idx;
```

The tumble re-bucketizes per-stock per-second features into per-second cross-sectional groups; `array_sort` orders by `ts_argmax`; `ARRAY JOIN array_enumerate(sorted_pairs)` fans the sorted list back into one row per stock with rank index. `alpha_1` ∈ [-0.4, 0.5] for N=10.

**Risk:** this is the highest-risk syntax in the design. Failure modes to validate against the running Timeplus:

- `array_sort(lambda, array_of_tuples)` may need explicit `arraySort`-style naming.
- `ARRAY JOIN array_enumerate(sorted_pairs) AS idx` may need an explicit unnested column.
- Cross-stock tumble emission timing — should emit on window-close, but if it delays we may need `EMIT AFTER WATERMARK AND DELAY 0s` or `EMIT ON UPDATE`.

A short live-validation pass before locking each file is part of the implementation plan.

## Data flow & timing

- t=0..2s: pipeline warms up (no `lags` history → `returns` is null → `sigma_ret_20` is null).
- t≈20s: `sigma_ret_20` becomes non-null (20-bar rolling stddev populated).
- t≈25s: `ts_argmax` stabilizes (5-bar argmax populated).
- Steady state: every second, `v_alpha_1` emits 10 rows (one per stock) with alpha in `{-0.45, -0.35, ..., 0.45, 0.55}` (10 distinct rank levels minus 0.5).

## Packaging

```
apps/alpha-101/
├── Makefile               # APP_NAME ?= alpha-101 (copy of market-data pattern)
├── manifest.yaml          # id: io.timeplus.alpha-101, db_name: alpha_101
├── ddl/
│   ├── 001_random_market_data.sql
│   ├── 002_market_data.sql
│   ├── 003_mv_market_data.sql
│   ├── 004_v_bars_1s.sql
│   ├── 005_v_features.sql
│   ├── 006_v_ts_argmax_5.sql
│   └── 007_v_alpha_1.sql
└── dashboards/
    └── main.json
```

**manifest.yaml essentials:**

- `package_format_version: 1`
- `id: io.timeplus.alpha-101`
- `name: "Realtime Alpha 101"`
- `db_name: alpha_101`
- `description: "Streaming demo of WorldQuant Alpha #1 over a synthetic 10-stock market data feed."`
- `categories: [analytics, finance, demo]`
- No `python_packages`, no `config`.
- `resources:` lists all 7 DDL files with `type` in the correct dependency order.
- `dashboards:` lists `main.json`.

## Dashboard

`dashboards/main.json` — three panels:

1. **Live prices** — line chart, `SELECT time, stock_id, close FROM v_bars_1s` (multi-series by stock_id, last 5 minutes).
2. **Alpha #1 leaderboard (latest)** — table, `SELECT time, stock_id, alpha_1 FROM v_alpha_1 ORDER BY alpha_1 DESC LIMIT 10 BY time`.
3. **Alpha #1 over time** — line chart, `SELECT time, stock_id, alpha_1 FROM v_alpha_1` (multi-series, last 5 minutes).

## Validation

The user-running Timeplus is reachable at `http://localhost:8000` via the ClickHouse-compatible HTTP interface using `proton` / `proton@t+`. The implementation plan will:

1. Smoke each DDL file via `curl` against the running instance — confirm syntax compiles before bundling.
2. After provisioning, run short bounded queries (`SELECT * FROM table(market_data) LIMIT 20`) and time-limited streams to verify each view emits the expected shape.
3. Verify alpha values are in `[-0.5, 0.5]` and that there are N distinct ranks per second.

## Risks & open questions

| Risk | Mitigation |
|------|-----------|
| `lags(x, i, i)` with non-constant `i` may not be allowed | Fallback: single `lags(close, 0, 20)` → compute returns inside `array_map` over that array |
| `array_sort` lambda + tuple ordering syntax | Live-validate; fall back to subquery + `groupArraySorted` if needed |
| `ARRAY JOIN array_enumerate(...)` fan-out emission timing | If laggy, add `EMIT AFTER WATERMARK AND DELAY 0s` |
| `latest(price)` may return arbitrary winner under concurrent ticks | Acceptable for the demo; production would use last-by-event-time |
| Random stream is "active only during query" — does the MV keep it warm? | Tested pattern in `RANDOM_STREAMS.md` confirms MV → persistent stream works |

## Future work (not in this slice)

- Add more Alpha 101 formulas as sibling views (Alpha #6, #41, #54 are good candidates once `volume` is added).
- Extend simulator with volume + bid/ask if more alphas are added.
- Aggregate composite alpha view that averages selected signals.
