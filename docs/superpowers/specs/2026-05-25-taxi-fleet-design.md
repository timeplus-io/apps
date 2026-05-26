# taxi-fleet — design

A Timeplus demo app that ingests simulated NYC taxi telemetry from the
[`timeplus-taxi-simulator`](https://pypi.org/project/timeplus-taxi-simulator/) Python package
and surfaces real-time fleet analytics on a dashboard.

## Goals

- Demonstrate a Python streaming external stream backed by a third-party PyPI package.
- Show four classes of real-time analytics on the same feed:
  1. Live fleet map (latest position per car).
  2. Speed analytics (per-car averages, fleet-wide max, distribution).
  3. Movement/idle detection (cars stopped for ≥10s).
  4. Fleet KPIs (active cars, average speed, etc.).
- Keep config minimal so the app is one click to install and run.

## Non-goals

- Historical analytics beyond 1 hour.
- Trip detection, fare modelling, or routing — only telemetry-level signals.
- Authentication, geofencing, or alert delivery.

## Data source

`timeplus-taxi-simulator==0.1.0` exposes `taxi_simulator.stream_taxi_data(num_cars, speed_kmh, update_interval, realtime_factor, custom_routes_file)`, a Python generator that yields dicts of the shape:

```python
{
  "car_id": "car_0001",
  "time": "2026-05-25T19:00:00.123456+00:00",  # ISO-8601 UTC
  "longitude": -74.0021,
  "latitude": 40.7128,
  "speed_kmh": 58.4,
}
```

Default: 10 cars, 60 km/h base (±20%), 0.5s update interval, 5× realtime factor, default NYC routes bundled in the package.

## Package layout

```
apps/taxi-fleet/
├── Makefile
├── manifest.yaml
├── ddl/
│   ├── 001_taxi_feed.sql
│   ├── 002_taxi_positions.sql
│   ├── 003_mv_taxi_positions.sql
│   ├── 004_taxi_latest.sql
│   ├── 005_mv_taxi_latest.sql
│   ├── 006_v_fleet_kpis.sql
│   ├── 007_v_speed_per_car_1m.sql
│   ├── 008_v_speed_distribution.sql
│   └── 009_v_idle_cars.sql
└── dashboards/
    └── main.json
```

## manifest.yaml

```yaml
package_format_version: 1
id: io.timeplus.taxi-fleet
name: NYC Taxi Fleet Analytics
version: 0.1.0
author: Timeplus
description: >
  Real-time NYC taxi fleet analytics powered by the timeplus-taxi-simulator
  Python package — live map, speed analytics, idle detection, fleet KPIs.
db_name: taxi_fleet
categories:
  - analytics
  - demo

config:
  - key: num_cars
    type: integer
    required: false
    default: "10"
    description: Number of simulated taxis (1–500 recommended).
  - key: speed_kmh
    type: float
    required: false
    default: "60.0"
    description: Base vehicle speed in km/h. Each car gets ±20% variation.

python_packages:
  - timeplus-taxi-simulator>=0.1.0

resources:
  - file: ddl/001_taxi_feed.sql
    type: external_stream
    name: taxi_feed
  - file: ddl/002_taxi_positions.sql
    type: stream
    name: taxi_positions
  - file: ddl/003_mv_taxi_positions.sql
    type: materialized_view
    name: mv_taxi_positions
  - file: ddl/004_taxi_latest.sql
    type: mutable_stream
    name: taxi_latest
  - file: ddl/005_mv_taxi_latest.sql
    type: materialized_view
    name: mv_taxi_latest
  - file: ddl/006_v_fleet_kpis.sql
    type: view
    name: v_fleet_kpis
  - file: ddl/007_v_speed_per_car_1m.sql
    type: view
    name: v_speed_per_car_1m
  - file: ddl/008_v_speed_distribution.sql
    type: view
    name: v_speed_distribution
  - file: ddl/009_v_idle_cars.sql
    type: view
    name: v_idle_cars

dashboards:
  - file: dashboards/main.json
    name: Taxi Fleet
    description: Live map, speed analytics, idle detection, and fleet KPIs
```

## Data flow

```
manifest.python_packages: timeplus-taxi-simulator
   │  (installer waits for completion before any DDL)
   ▼
taxi_feed (external_stream, mode='streaming')
   │  yields typed tuple (car_id, ts, longitude, latitude, speed_kmh)
   ▼
taxi_positions (stream, TTL = 1h)         ◀── mv_taxi_positions
   │
   ├──▶ taxi_latest (mutable_stream, PK: car_id) ◀── mv_taxi_latest
   │       drives the geo panel — exactly one row per car
   │
   ├──▶ v_fleet_kpis            global single-row KPIs
   ├──▶ v_speed_per_car_1m      tumble(1m) per car
   ├──▶ v_speed_distribution    histogram buckets over a sliding window
   └──▶ v_idle_cars             cars whose max speed in last 10s < 5 km/h
```

Design decision: because the simulator emits a fixed schema, the external stream yields
**typed columns directly** (unlike the `market-data` app, which preserves an opaque JSON
payload and parses it downstream). This removes the JSON-extract MV layer.

## DDL specifications

### 001_taxi_feed.sql — external stream

```sql
CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.taxi_feed(
  car_id     string,
  ts         datetime64(3),
  longitude  float64,
  latitude   float64,
  speed_kmh  float64
)
AS $$
from taxi_simulator import stream_taxi_data
from datetime import datetime
import time

def read_taxi_stream():
    while True:
        try:
            for ev in stream_taxi_data(
                num_cars={{ .Config.num_cars }},
                speed_kmh={{ .Config.speed_kmh }},
            ):
                yield (
                    ev["car_id"],
                    datetime.fromisoformat(ev["time"].replace("Z", "+00:00")),
                    ev["longitude"],
                    ev["latitude"],
                    ev["speed_kmh"],
                )
        except Exception:
            time.sleep(2)
$$
SETTINGS type='python', mode='streaming', read_function_name='read_taxi_stream';
```

### 002_taxi_positions.sql — typed stream

```sql
CREATE STREAM IF NOT EXISTS {{ .DB }}.taxi_positions (
  car_id     string,
  ts         datetime64(3),
  longitude  float64,
  latitude   float64,
  speed_kmh  float64
)
TTL to_datetime(_tp_time) + INTERVAL 1 HOUR
SETTINGS logstore_retention_bytes = '107374182', logstore_retention_ms = '300000';
```

### 003_mv_taxi_positions.sql

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_taxi_positions
INTO {{ .DB }}.taxi_positions
AS
SELECT
  car_id,
  ts,
  longitude,
  latitude,
  speed_kmh,
  ts AS _tp_time
FROM {{ .DB }}.taxi_feed;
```

### 004_taxi_latest.sql — mutable stream

```sql
CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.taxi_latest (
  car_id     string,
  ts         datetime64(3),
  longitude  float64,
  latitude   float64,
  speed_kmh  float64
)
PRIMARY KEY car_id;
```

### 005_mv_taxi_latest.sql

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_taxi_latest
INTO {{ .DB }}.taxi_latest
AS
SELECT car_id, ts, longitude, latitude, speed_kmh
FROM {{ .DB }}.taxi_positions;
```

### 006_v_fleet_kpis.sql

```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_fleet_kpis AS
SELECT
  window_start AS time,
  count_distinct(car_id) AS active_cars,
  round(avg(speed_kmh), 1) AS avg_speed_kmh,
  round(max(speed_kmh), 1) AS max_speed_kmh,
  count() AS updates_in_window
FROM tumble({{ .DB }}.taxi_positions, 5s)
GROUP BY window_start;
```

### 007_v_speed_per_car_1m.sql

```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_speed_per_car_1m AS
SELECT
  window_start AS time,
  car_id,
  round(avg(speed_kmh), 1) AS avg_speed_kmh,
  round(max(speed_kmh), 1) AS max_speed_kmh
FROM tumble({{ .DB }}.taxi_positions, 1m)
GROUP BY window_start, car_id;
```

### 008_v_speed_distribution.sql

Bucketed histogram over a 10-second tumbling window. Buckets: 0–10, 10–20, 20–40, 40–60, 60–80, 80+ km/h.

```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_speed_distribution AS
SELECT
  window_start AS time,
  multi_if(
    speed_kmh < 10, '0-10',
    speed_kmh < 20, '10-20',
    speed_kmh < 40, '20-40',
    speed_kmh < 60, '40-60',
    speed_kmh < 80, '60-80',
    '80+'
  ) AS bucket,
  count() AS cars_in_bucket
FROM tumble({{ .DB }}.taxi_positions, 5s)
GROUP BY window_start, bucket;
```

### 009_v_idle_cars.sql

A car is "idle" if its max speed in the last 10 seconds is below 5 km/h.

```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_idle_cars AS
SELECT
  window_start AS time,
  car_id,
  round(max(speed_kmh), 1) AS max_speed_kmh,
  round(avg(speed_kmh), 1) AS avg_speed_kmh,
  any(longitude) AS longitude,
  any(latitude) AS latitude
FROM tumble({{ .DB }}.taxi_positions, 10s)
GROUP BY window_start, car_id
HAVING max(speed_kmh) < 5;
```

## Dashboard: `dashboards/main.json`

Eight panels in a grid:

1. **Header / description** — markdown panel introducing the demo.
2. **Active cars** — `singleValue` from `v_fleet_kpis`.
3. **Avg fleet speed (km/h)** — `singleValue` from `v_fleet_kpis`.
4. **Max speed (km/h)** — `singleValue` from `v_fleet_kpis`.
5. **Idle cars** — `singleValue`, count over `v_idle_cars` latest window.
6. **Live fleet map** — `chartType: "geo"` reading `table([[ .DB ]].taxi_latest)`, with `longitude`/`latitude` columns, color by `car_id`, center `[-74.0, 40.72]`, zoom `11`, `updateMode: "all"`, `updateKey: "car_id"`, `visibleColumns: ["car_id","speed_kmh"]`.
7. **Avg speed per car (1m windows)** — multi-series `line`, color by `car_id`, x-axis `time`, source `v_speed_per_car_1m`.
8. **Speed distribution** — `bar`, x = bucket, y = `cars_in_bucket`, source `v_speed_distribution`, latest window only.
9. **Idle cars list** — `table` from `v_idle_cars` (current window), columns `car_id`, `max_speed_kmh`, `longitude`, `latitude`.

## Conventions observed (from auto-memory)

- View filters in the dashboard use `time` (the aliased column), not `_tp_time`.
- Multi-series line panels set `viz_config.config.color` to the series column.
- All SQL uses `null_if`, never `nullif`.
- Manifest descriptions are quoted whenever they could contain `#`.
- `viz_config.config` fields will be chosen per-panel, not copy-pasted.

## Testing / verification

After running `make install APP=taxi-fleet`:

1. `SELECT count() FROM taxi_fleet.taxi_positions;` — increases over time.
2. `SELECT * FROM table(taxi_fleet.taxi_latest);` — returns exactly `num_cars` rows.
3. `SELECT * FROM v_fleet_kpis;` (streaming) — `active_cars` ≈ configured count.
4. `SELECT * FROM v_idle_cars;` — initially empty unless a car is between routes.
5. Open the dashboard — map shows cars moving; KPIs update; speed distribution panel renders bars.

## Open risks

- **Python package install time** — `timeplus-taxi-simulator` is ~2.3 MB and includes a routes file; first install requires `system.python_packages` to reach `status='installed'` before DDL runs. The manifest installer handles this, but cold starts may be slow on a fresh node.
- **Geo panel rendering** — confirmed `chartType: "geo"` exists in `references/dashboard-spec.md`; will live-validate the panel against a running instance during implementation.
- **`datetime.fromisoformat` on Python <3.7** — the package requires 3.7+; the simulator's ISO string ends with `+00:00`, but we also handle a trailing `Z` for safety.
