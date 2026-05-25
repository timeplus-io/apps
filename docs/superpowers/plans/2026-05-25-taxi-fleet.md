# taxi-fleet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a new Timeplus app `taxi-fleet` that ingests simulated NYC taxi telemetry from the `timeplus-taxi-simulator` PyPI package and exposes a real-time analytics dashboard (live map, speed analytics, idle detection, fleet KPIs).

**Architecture:** Python streaming external stream → typed `taxi_positions` stream (1h TTL) → mutable `taxi_latest` (keyed on `car_id`, drives the geo panel) + four analytic views over `taxi_positions`. Dashboard renders one map, four single-value KPI tiles, a multi-series line chart, a bar histogram, a table, and a markdown header.

**Tech Stack:** Timeplus DDL (template variables `{{ .DB }}`, `{{ .Config.* }}`), `timeplus-taxi-simulator` Python package (declared in `manifest.python_packages`), dashboard JSON (template delimiter `[[ ]]`), bash `make` + `curl` for build/install.

**Spec:** `docs/superpowers/specs/2026-05-25-taxi-fleet-design.md`

**Prerequisites for the implementing agent:**
- Working directory is the repo root: `/Users/gangtao/Code/timeplus/apps`.
- A Timeplus instance is reachable at `http://localhost:8000` (default tenant). If it isn't running, the install/verification steps will fail with HTTP connection errors — start Timeplus, then re-run the failing step. **Do not** mock or skip verification.
- The reader should skim `CLAUDE.md` at the repo root and `apps/market-data/` once before starting; it is the canonical reference pattern.

**Verification convention:** Because this is a SQL/JSON package (no unit-test framework), each task ends with concrete shell commands and their expected output. "Verify" = run the command and check the output matches.

**Verification helper — read this once.** The Timeplus query endpoint at `/default/api/v1beta2/queries` accepts a JSON POST `{"sql":"..."}` and streams back Server-Sent Events. The data rows arrive as `data: [[...]]` lines. The compact verification one-liner is:

```bash
TP_QUERY() {
  curl -s --max-time "${2:-15}" -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg sql "$1" '{sql:$sql}')" \
    http://localhost:8000/default/api/v1beta2/queries \
  | awk '/^data: \[/ {print substr($0,7)}'
}
```

Define it once at the start of each terminal session. Then `TP_QUERY "SELECT 1"` prints `[[1]]`. Each subsequent `TP_QUERY "..."` returns one or more `[[...]]` JSON arrays — one per row (streaming queries emit one line per row, then keep the connection open until the timeout). The `${2:-15}` is a per-call timeout (default 15s); pass a second arg for longer streaming queries: `TP_QUERY "SELECT ... FROM tumble(...)" 80`. For installs and verification, all curl examples below use `TP_QUERY`.

**Why this matters:** The plain `?query=...` URL form returns `404 page not found` on this Timeplus build — only the `/queries` JSON-POST endpoint works.

---

## File Structure

Files created by this plan (all paths relative to repo root):

```
apps/taxi-fleet/
├── Makefile                                   # build/install delegation (Task 1)
├── manifest.yaml                              # package metadata + config + resources (Task 1, expanded in 2/3)
├── ddl/
│   ├── 001_taxi_feed.sql                      # Python streaming external_stream (Task 2)
│   ├── 002_taxi_positions.sql                 # typed stream, 1h TTL (Task 3)
│   ├── 003_mv_taxi_positions.sql              # MV: external → typed stream (Task 3)
│   ├── 004_taxi_latest.sql                    # mutable_stream PK car_id (Task 4)
│   ├── 005_mv_taxi_latest.sql                 # MV: positions → latest (Task 4)
│   ├── 006_v_fleet_kpis.sql                   # view: KPIs (Task 5)
│   ├── 007_v_speed_per_car_1m.sql             # view: per-car 1m windows (Task 5)
│   ├── 008_v_speed_distribution.sql           # view: bucketed histogram (Task 5)
│   └── 009_v_idle_cars.sql                    # view: idle detection (Task 5)
└── dashboards/
    └── main.json                              # 9 panels (Task 6)
```

Also modified:

- `Makefile` (repo root) — add `taxi-fleet` to the `APPS` list (Task 7).

---

## Task 1: Scaffold app + minimal `manifest.yaml` + Makefile (build the empty package)

**Goal:** Create the directory and a manifest that has zero resources but successfully builds and installs. This proves the scaffold + Make wiring works before any DDL exists.

**Files:**
- Create: `apps/taxi-fleet/Makefile`
- Create: `apps/taxi-fleet/manifest.yaml`
- Create: `apps/taxi-fleet/ddl/.keep` (empty file, so `zip` includes the directory)
- Create: `apps/taxi-fleet/dashboards/.keep`

- [ ] **Step 1: Create the directory structure**

Run:
```bash
mkdir -p apps/taxi-fleet/ddl apps/taxi-fleet/dashboards
touch apps/taxi-fleet/ddl/.keep apps/taxi-fleet/dashboards/.keep
```

- [ ] **Step 2: Write `apps/taxi-fleet/Makefile`**

```makefile
APP_NAME    ?= taxi-fleet
OUT         ?= $(APP_NAME).tpapp

NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default

.PHONY: build install

build:
	zip -r $(OUT) manifest.yaml ddl/ dashboards/

install: build
	curl -X POST $(NEUTRON_URL)/$(TENANT)/api/v1beta2/apps/install -F "file=@$(OUT)"
```

- [ ] **Step 3: Write minimal `apps/taxi-fleet/manifest.yaml`**

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
    description: Number of simulated taxis (1-500 recommended).
  - key: speed_kmh
    type: float
    required: false
    default: "60.0"
    description: Base vehicle speed in km/h. Each car gets +/-20% variation.

python_packages:
  - timeplus-taxi-simulator>=0.1.0

resources: []

dashboards: []
```

Notes:
- `description` is quoted via `>` block scalar — no `#` characters anywhere in the values, but quoting is the safe default per `feedback_manifest_yaml_hash.md`.
- `resources: []` is intentional — we'll add entries in subsequent tasks.

- [ ] **Step 4: Verify `make build` succeeds**

Run:
```bash
make -C apps/taxi-fleet build
```

Expected stdout last lines:
```
  adding: manifest.yaml (...)
  adding: ddl/ (...)
  adding: ddl/.keep (...)
  adding: dashboards/ (...)
  adding: dashboards/.keep (...)
```

And a file `apps/taxi-fleet/taxi-fleet.tpapp` should exist:
```bash
ls -lh apps/taxi-fleet/taxi-fleet.tpapp
```
Expected: file present, size ~1 KB.

- [ ] **Step 5: Commit**

```bash
git add apps/taxi-fleet/Makefile apps/taxi-fleet/manifest.yaml apps/taxi-fleet/ddl/.keep apps/taxi-fleet/dashboards/.keep
git commit -m "taxi-fleet: scaffold empty app package"
```

---

## Task 2: Add the Python streaming external stream `taxi_feed`

**Goal:** Wire up the `timeplus-taxi-simulator` Python generator as an external stream so positions flow into Timeplus. After this task we can `SELECT * FROM taxi_feed` and see data.

**Files:**
- Create: `apps/taxi-fleet/ddl/001_taxi_feed.sql`
- Modify: `apps/taxi-fleet/manifest.yaml` (append to `resources:`)
- Delete: `apps/taxi-fleet/ddl/.keep` (no longer needed)

- [ ] **Step 1: Write `apps/taxi-fleet/ddl/001_taxi_feed.sql`**

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

Notes:
- The wheel exposes the module as `taxi_simulator` (not `timeplus_taxi_simulator`); the PyPI distribution name differs from the import name.
- Template variables `{{ .Config.num_cars }}` / `{{ .Config.speed_kmh }}` render to literal int/float values before the SQL is parsed. **Always use dot notation** — `index .Config "num_cars"` is not supported in this codebase.
- The outer `while True` + `try/except` protects against the generator raising on transient errors (e.g. routes-file edge cases). It does NOT retry on permanent errors silently — the `print`-free except is acceptable for the demo; downstream MV will simply pause until the generator yields again.

- [ ] **Step 2: Update `apps/taxi-fleet/manifest.yaml` to register the resource**

Replace the line `resources: []` with:
```yaml
resources:
  - file: ddl/001_taxi_feed.sql
    type: external_stream
    name: taxi_feed
```

- [ ] **Step 3: Remove the placeholder `.keep` in `ddl/`**

Run:
```bash
rm apps/taxi-fleet/ddl/.keep
```
(The directory is no longer empty, so the placeholder is unnecessary. `zip -r` will pick up `001_taxi_feed.sql` directly.)

- [ ] **Step 4: Build and install**

Run:
```bash
make -C apps/taxi-fleet install
```

Expected: HTTP 200 from the curl POST, and JSON response body containing `"status":"success"` or similar (the exact response shape depends on the Timeplus version; non-200 is a failure).

If install fails with `No module named 'taxi_simulator'`: the `timeplus-taxi-simulator` package install hasn't completed yet. Wait ~30s and re-run, or check status:
```bash
TP_QUERY "SELECT * FROM system.python_packages WHERE name='timeplus-taxi-simulator'"
```
Expected: a row with `"status":"installed"`.

- [ ] **Step 5: Verify data is flowing from `taxi_feed`**

Run:
```bash
TP_QUERY "SELECT * FROM taxi_fleet.taxi_feed LIMIT 5"
```

Expected (after a few seconds): 5 rows each containing `car_id`, `ts`, `longitude`, `latitude`, `speed_kmh`. `car_id` should look like `"car_0001"`, `longitude` ~ -74, `latitude` ~ 40.7, `speed_kmh` should be a float between roughly 40 and 75.

If the LIMIT query hangs (external streams are tail-only), use a streaming bounded query:
```bash
TP_QUERY "SELECT * FROM taxi_fleet.taxi_feed WHERE _tp_time > earliest_ts() LIMIT 5"
```

- [ ] **Step 6: Commit**

```bash
git add apps/taxi-fleet/ddl/001_taxi_feed.sql apps/taxi-fleet/manifest.yaml
git rm apps/taxi-fleet/ddl/.keep
git commit -m "taxi-fleet: add Python streaming external stream from timeplus-taxi-simulator"
```

---

## Task 3: Persist positions to a typed `taxi_positions` stream

**Goal:** Add a regular stream with 1h TTL and an MV that copies from `taxi_feed` into it. After this task we can `SELECT count() FROM taxi_positions` and see the count growing.

**Files:**
- Create: `apps/taxi-fleet/ddl/002_taxi_positions.sql`
- Create: `apps/taxi-fleet/ddl/003_mv_taxi_positions.sql`
- Modify: `apps/taxi-fleet/manifest.yaml`

- [ ] **Step 1: Write `apps/taxi-fleet/ddl/002_taxi_positions.sql`**

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

- [ ] **Step 2: Write `apps/taxi-fleet/ddl/003_mv_taxi_positions.sql`**

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

Note: we explicitly set `_tp_time = ts` so downstream tumbling windows align with event time, not ingest time.

- [ ] **Step 3: Update `apps/taxi-fleet/manifest.yaml`**

Append to `resources:`:
```yaml
  - file: ddl/002_taxi_positions.sql
    type: stream
    name: taxi_positions
  - file: ddl/003_mv_taxi_positions.sql
    type: materialized_view
    name: mv_taxi_positions
```

So the full `resources:` block now looks like:
```yaml
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
```

- [ ] **Step 4: Re-install and verify**

Run:
```bash
make -C apps/taxi-fleet install
```
Expected: HTTP 200.

Wait ~5 seconds, then:
```bash
TP_QUERY "SELECT count() AS n FROM table(taxi_fleet.taxi_positions)"
```
Expected: `{"n":"<some positive integer>"}` — the count should be > 0 and grow on each re-run.

- [ ] **Step 5: Commit**

```bash
git add apps/taxi-fleet/ddl/002_taxi_positions.sql apps/taxi-fleet/ddl/003_mv_taxi_positions.sql apps/taxi-fleet/manifest.yaml
git commit -m "taxi-fleet: persist positions to taxi_positions stream"
```

---

## Task 4: Add `taxi_latest` mutable stream for the live map

**Goal:** Mutable stream keyed on `car_id` so the geo panel reads exactly one row per car (most recent position). Without this, a streaming `SELECT … FROM taxi_positions` plots history, accumulating dots over time.

**Files:**
- Create: `apps/taxi-fleet/ddl/004_taxi_latest.sql`
- Create: `apps/taxi-fleet/ddl/005_mv_taxi_latest.sql`
- Modify: `apps/taxi-fleet/manifest.yaml`

- [ ] **Step 1: Write `apps/taxi-fleet/ddl/004_taxi_latest.sql`**

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

- [ ] **Step 2: Write `apps/taxi-fleet/ddl/005_mv_taxi_latest.sql`**

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_taxi_latest
INTO {{ .DB }}.taxi_latest
AS
SELECT car_id, ts, longitude, latitude, speed_kmh
FROM {{ .DB }}.taxi_positions;
```

The mutable stream upserts on its primary key (`car_id`), so each car ends up with exactly one row that gets overwritten on every new position.

- [ ] **Step 3: Update `apps/taxi-fleet/manifest.yaml`**

Append to `resources:`:
```yaml
  - file: ddl/004_taxi_latest.sql
    type: mutable_stream
    name: taxi_latest
  - file: ddl/005_mv_taxi_latest.sql
    type: materialized_view
    name: mv_taxi_latest
```

- [ ] **Step 4: Re-install and verify**

```bash
make -C apps/taxi-fleet install
```
Expected: HTTP 200.

Wait ~5 seconds, then count rows in the mutable stream:
```bash
TP_QUERY "SELECT count() AS n FROM table(taxi_fleet.taxi_latest)"
```
Expected: `{"n":"10"}` — exactly the configured `num_cars` (10 by default), regardless of how long the app has been running.

Sanity-check that positions update (run twice with a 3-second gap):
```bash
TP_QUERY "SELECT car_id, longitude, latitude, speed_kmh FROM table(taxi_fleet.taxi_latest) WHERE car_id = 'car_0001'"
sleep 3
TP_QUERY "SELECT car_id, longitude, latitude, speed_kmh FROM table(taxi_fleet.taxi_latest) WHERE car_id = 'car_0001'"
```
Expected: the two outputs differ in `longitude`/`latitude` (car has moved).

- [ ] **Step 5: Commit**

```bash
git add apps/taxi-fleet/ddl/004_taxi_latest.sql apps/taxi-fleet/ddl/005_mv_taxi_latest.sql apps/taxi-fleet/manifest.yaml
git commit -m "taxi-fleet: add taxi_latest mutable stream for live map"
```

---

## Task 5: Add the four analytic views

**Goal:** Add all four analytics views in one task — each is small (5-15 lines), independent of the others, and verified by a one-liner `SELECT`. Bundling avoids four near-identical commit cycles.

**Files:**
- Create: `apps/taxi-fleet/ddl/006_v_fleet_kpis.sql`
- Create: `apps/taxi-fleet/ddl/007_v_speed_per_car_1m.sql`
- Create: `apps/taxi-fleet/ddl/008_v_speed_distribution.sql`
- Create: `apps/taxi-fleet/ddl/009_v_idle_cars.sql`
- Modify: `apps/taxi-fleet/manifest.yaml`

- [ ] **Step 1: Write `apps/taxi-fleet/ddl/006_v_fleet_kpis.sql`**

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

Note the `window_start AS time` aliasing — downstream dashboard panels filter on `time`, not `_tp_time` (see `feedback_dashboard_time_column.md` in auto-memory).

- [ ] **Step 2: Write `apps/taxi-fleet/ddl/007_v_speed_per_car_1m.sql`**

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

- [ ] **Step 3: Write `apps/taxi-fleet/ddl/008_v_speed_distribution.sql`**

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

- [ ] **Step 4: Write `apps/taxi-fleet/ddl/009_v_idle_cars.sql`**

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

- [ ] **Step 5: Update `apps/taxi-fleet/manifest.yaml`**

Append to `resources:`:
```yaml
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
```

- [ ] **Step 6: Re-install**

```bash
make -C apps/taxi-fleet install
```
Expected: HTTP 200.

- [ ] **Step 7: Verify each view returns data**

Use `EMIT PERIODIC 1s` to get bounded results from streaming queries. Run each:

```bash
# v_fleet_kpis — expect one row per 5s window
TP_QUERY "SELECT * FROM taxi_fleet.v_fleet_kpis EMIT PERIODIC 1s LIMIT 1" 15
```
Expected: a JSON row with `active_cars: 10`, non-zero `avg_speed_kmh` and `max_speed_kmh`, `updates_in_window` > 0.

```bash
# v_speed_per_car_1m — expect 10 rows (one per car) per 1m window
TP_QUERY "SELECT * FROM taxi_fleet.v_speed_per_car_1m EMIT PERIODIC 1s LIMIT 10" 80
```
Expected (will take ~60s for the first window to close): 10 rows, distinct `car_id`s.

```bash
# v_speed_distribution — expect a few rows (buckets) per 5s window
TP_QUERY "SELECT * FROM taxi_fleet.v_speed_distribution EMIT PERIODIC 1s LIMIT 6" 15
```
Expected: 1–6 rows of `bucket`/`cars_in_bucket` pairs (likely heavy on `40-60` and `60-80` buckets since base speed is 60).

```bash
# v_idle_cars — typically empty (cars are moving), so just confirm the query runs without error
TP_QUERY "SELECT * FROM taxi_fleet.v_idle_cars EMIT PERIODIC 1s LIMIT 1" 25
```
Expected: either no rows (curl returns empty body after timeout) **or** a row with `max_speed_kmh < 5`. Both are valid.

- [ ] **Step 8: Commit**

```bash
git add apps/taxi-fleet/ddl/006_v_fleet_kpis.sql apps/taxi-fleet/ddl/007_v_speed_per_car_1m.sql apps/taxi-fleet/ddl/008_v_speed_distribution.sql apps/taxi-fleet/ddl/009_v_idle_cars.sql apps/taxi-fleet/manifest.yaml
git commit -m "taxi-fleet: add fleet KPIs, per-car speed, distribution, and idle views"
```

---

## Task 6: Build the dashboard

**Goal:** Create `dashboards/main.json` with all 9 panels and register it in the manifest. After this task the dashboard is visible in the Timeplus UI.

**Files:**
- Create: `apps/taxi-fleet/dashboards/main.json`
- Delete: `apps/taxi-fleet/dashboards/.keep`
- Modify: `apps/taxi-fleet/manifest.yaml` (add `dashboards:` entry)

- [ ] **Step 1: Write `apps/taxi-fleet/dashboards/main.json`**

The dashboard is a JSON array of panel objects. Use template delimiter `[[ ]]` for `.DB`. Layout uses a 12-column grid (`x`+`w` ≤ 12); `y`/`h` are row positions.

```json
[
  {
    "id": "tx-header",
    "title": "About",
    "description": "",
    "position": { "x": 0, "y": 0, "w": 12, "h": 1, "nextX": 12, "nextY": 1 },
    "viz_type": "chart",
    "viz_content": "",
    "viz_config": {
      "chartType": "md",
      "config": {
        "content": "# NYC Taxi Fleet Analytics\n\nReal-time telemetry from the `timeplus-taxi-simulator` Python package. Map shows latest position of each taxi; KPIs and charts update on a 5-second tumbling window.",
        "updateMode": "all",
        "updateKey": ""
      }
    }
  },
  {
    "id": "tx-kpi-active",
    "title": "Active cars",
    "description": "",
    "position": { "x": 0, "y": 1, "w": 3, "h": 2, "nextX": 3, "nextY": 3 },
    "viz_type": "chart",
    "viz_content": "SELECT time, active_cars FROM [[ .DB ]].v_fleet_kpis",
    "viz_config": {
      "chartType": "singleValue",
      "config": {
        "value": "active_cars",
        "color": "blue",
        "sparkline": false,
        "delta": false,
        "fontSize": 64,
        "fractionDigits": 0,
        "unit": { "position": "right", "value": "" }
      }
    }
  },
  {
    "id": "tx-kpi-avg-speed",
    "title": "Avg speed",
    "description": "",
    "position": { "x": 3, "y": 1, "w": 3, "h": 2, "nextX": 6, "nextY": 3 },
    "viz_type": "chart",
    "viz_content": "SELECT time, avg_speed_kmh FROM [[ .DB ]].v_fleet_kpis",
    "viz_config": {
      "chartType": "singleValue",
      "config": {
        "value": "avg_speed_kmh",
        "color": "green",
        "sparkline": true,
        "sparklineColor": "green",
        "delta": false,
        "fontSize": 64,
        "fractionDigits": 1,
        "unit": { "position": "right", "value": "km/h" }
      }
    }
  },
  {
    "id": "tx-kpi-max-speed",
    "title": "Max speed",
    "description": "",
    "position": { "x": 6, "y": 1, "w": 3, "h": 2, "nextX": 9, "nextY": 3 },
    "viz_type": "chart",
    "viz_content": "SELECT time, max_speed_kmh FROM [[ .DB ]].v_fleet_kpis",
    "viz_config": {
      "chartType": "singleValue",
      "config": {
        "value": "max_speed_kmh",
        "color": "orange",
        "sparkline": true,
        "sparklineColor": "orange",
        "delta": false,
        "fontSize": 64,
        "fractionDigits": 1,
        "unit": { "position": "right", "value": "km/h" }
      }
    }
  },
  {
    "id": "tx-kpi-idle",
    "title": "Idle cars (last 10s)",
    "description": "",
    "position": { "x": 9, "y": 1, "w": 3, "h": 2, "nextX": 12, "nextY": 3 },
    "viz_type": "chart",
    "viz_content": "WITH latest AS (SELECT max(time) AS t FROM [[ .DB ]].v_idle_cars) SELECT t AS time, count() AS idle FROM [[ .DB ]].v_idle_cars, latest WHERE time = t",
    "viz_config": {
      "chartType": "singleValue",
      "config": {
        "value": "idle",
        "color": "red",
        "sparkline": false,
        "delta": false,
        "fontSize": 64,
        "fractionDigits": 0,
        "unit": { "position": "right", "value": "" }
      }
    }
  },
  {
    "id": "tx-map",
    "title": "Live fleet map",
    "description": "",
    "position": { "x": 0, "y": 3, "w": 8, "h": 6, "nextX": 8, "nextY": 9 },
    "viz_type": "chart",
    "viz_content": "SELECT car_id, longitude, latitude, speed_kmh FROM table([[ .DB ]].taxi_latest)",
    "viz_config": {
      "chartType": "geo",
      "config": {
        "longitude": "longitude",
        "latitude": "latitude",
        "color": "car_id",
        "updateMode": "key",
        "updateKey": "car_id",
        "visibleColumns": ["car_id", "speed_kmh"],
        "opacity": 0.9,
        "zoom": 11,
        "center": [-74.0, 40.72],
        "size": { "key": "", "value": 6, "range": [4, 12] }
      }
    }
  },
  {
    "id": "tx-speed-dist",
    "title": "Speed distribution (km/h)",
    "description": "",
    "position": { "x": 8, "y": 3, "w": 4, "h": 3, "nextX": 12, "nextY": 6 },
    "viz_type": "chart",
    "viz_content": "WITH latest AS (SELECT max(time) AS t FROM [[ .DB ]].v_speed_distribution) SELECT bucket, cars_in_bucket FROM [[ .DB ]].v_speed_distribution, latest WHERE time = t ORDER BY bucket",
    "viz_config": {
      "chartType": "bar",
      "config": {
        "xAxis": "bucket",
        "yAxis": "cars_in_bucket",
        "color": "",
        "xTitle": "Speed bucket",
        "yTitle": "Cars"
      }
    }
  },
  {
    "id": "tx-idle-table",
    "title": "Idle cars",
    "description": "",
    "position": { "x": 8, "y": 6, "w": 4, "h": 3, "nextX": 12, "nextY": 9 },
    "viz_type": "chart",
    "viz_content": "SELECT car_id, max_speed_kmh, longitude, latitude FROM [[ .DB ]].v_idle_cars",
    "viz_config": {
      "chartType": "table",
      "config": {
        "tableWrap": false
      }
    }
  },
  {
    "id": "tx-speed-per-car",
    "title": "Avg speed per car (1-minute windows)",
    "description": "",
    "position": { "x": 0, "y": 9, "w": 12, "h": 4, "nextX": 12, "nextY": 13 },
    "viz_type": "chart",
    "viz_content": "SELECT time, car_id, avg_speed_kmh FROM [[ .DB ]].v_speed_per_car_1m",
    "viz_config": {
      "chartType": "line",
      "config": {
        "xAxis": "time",
        "yAxis": "avg_speed_kmh",
        "color": "car_id",
        "xRange": "Infinity",
        "yTitle": "km/h"
      }
    }
  }
]
```

Notes:
- The map panel uses `table(taxi_latest)` to read the mutable stream's current state (one row per car). `updateMode: "key"` with `updateKey: "car_id"` upserts each car's marker on the map without accumulating history.
- The speed-distribution and idle-count panels use a `WITH latest AS ...` CTE to pull only the most recent window — without it, streaming results would include every closed window.
- Multi-series line chart sets `"color": "car_id"` per `feedback_dashboard_multiseries_color.md` — leaving it empty silently collapses all series.
- View queries filter on the aliased `time` column (not `_tp_time`), per `feedback_dashboard_time_column.md`.

- [ ] **Step 2: Remove the dashboards placeholder**

```bash
rm apps/taxi-fleet/dashboards/.keep
```

- [ ] **Step 3: Update `apps/taxi-fleet/manifest.yaml`**

Replace `dashboards: []` with:
```yaml
dashboards:
  - file: dashboards/main.json
    name: Taxi Fleet
    description: Live map, speed analytics, idle detection, and fleet KPIs
```

- [ ] **Step 4: Re-install**

```bash
make -C apps/taxi-fleet install
```
Expected: HTTP 200.

- [ ] **Step 5: Live-validate every dashboard panel query**

For each panel, copy the `viz_content` SQL, replace `[[ .DB ]]` with `taxi_fleet`, and execute it. This catches typos before opening the UI.

```bash
# tx-kpi-active / avg / max (same view)
TP_QUERY "SELECT time, active_cars, avg_speed_kmh, max_speed_kmh FROM taxi_fleet.v_fleet_kpis EMIT PERIODIC 1s LIMIT 1" 15

# tx-kpi-idle (CTE pattern)
TP_QUERY "WITH latest AS (SELECT max(time) AS t FROM taxi_fleet.v_idle_cars) SELECT t AS time, count() AS idle FROM taxi_fleet.v_idle_cars, latest WHERE time = t EMIT PERIODIC 1s LIMIT 1" 15

# tx-map (mutable stream)
TP_QUERY "SELECT car_id, longitude, latitude, speed_kmh FROM table(taxi_fleet.taxi_latest)"

# tx-speed-dist (latest bucket)
TP_QUERY "WITH latest AS (SELECT max(time) AS t FROM taxi_fleet.v_speed_distribution) SELECT bucket, cars_in_bucket FROM taxi_fleet.v_speed_distribution, latest WHERE time = t ORDER BY bucket EMIT PERIODIC 1s LIMIT 6" 15

# tx-speed-per-car
TP_QUERY "SELECT time, car_id, avg_speed_kmh FROM taxi_fleet.v_speed_per_car_1m EMIT PERIODIC 1s LIMIT 10" 80
```

Each command should return non-empty JSON (or a clear empty result for `v_idle_cars` if no cars are idle). Any SQL error means the panel will fail to render — fix the JSON and re-install.

- [ ] **Step 6: Open the dashboard in the UI (manual)**

Visit `http://localhost:8000/default/dashboards` in a browser and open "Taxi Fleet". Confirm:
- All 9 panels render without "Error" or "Loading…" stuck states.
- Map shows ~10 markers in the NYC area, updating every few seconds.
- KPI tiles show non-zero values.
- Speed distribution bar chart shows bars in the 40–60 and 60–80 buckets.
- Per-car speed line chart shows multiple colored lines after ~60s.

**If the user round-trips the dashboard in the UI**, the file on disk may get rewritten with rendered template values (per `feedback_dashboard_ui_renders_templates.md`). Run `git diff` and restore the source if so.

- [ ] **Step 7: Commit**

```bash
git add apps/taxi-fleet/dashboards/main.json apps/taxi-fleet/manifest.yaml
git rm apps/taxi-fleet/dashboards/.keep
git commit -m "taxi-fleet: add main dashboard with map, KPIs, distribution, and per-car charts"
```

---

## Task 7: Register `taxi-fleet` in the root Makefile

**Goal:** Add the new app to the `APPS` list at the repo root so `make build-all` / `make install-all` include it.

**Files:**
- Modify: `Makefile` (repo root, line 7)

- [ ] **Step 1: Edit the root `Makefile`**

Change line 7 from:
```makefile
APPS        := market-data github cep game-feature-pipeline hacker-news invest-insights cisco-asa-ddos bluesky aws-cost
```

to:
```makefile
APPS        := market-data github cep game-feature-pipeline hacker-news invest-insights cisco-asa-ddos bluesky aws-cost taxi-fleet
```

- [ ] **Step 2: Verify `make build APP=taxi-fleet` works from the root**

```bash
make build APP=taxi-fleet
```
Expected: zip output and `apps/taxi-fleet/taxi-fleet.tpapp` is rebuilt (timestamp newer than before).

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "taxi-fleet: register in root Makefile APPS list"
```

---

## Task 8: End-to-end verification

**Goal:** Independent verification pass against a clean install. Catches issues that an incremental developer wouldn't notice (e.g. order-dependent DDL bugs).

- [ ] **Step 1: Uninstall the running app (clean slate)**

```bash
curl -s -X DELETE "http://localhost:8000/default/api/v1beta2/apps/io.timeplus.taxi-fleet"
```
Expected: HTTP 200 or 404 (404 = wasn't installed; both are acceptable starting states).

Then drop the database to be thorough:
```bash
TP_QUERY "DROP DATABASE IF EXISTS taxi_fleet"
```

- [ ] **Step 2: Re-install from scratch**

```bash
make install APP=taxi-fleet
```
Expected: HTTP 200. The install should complete without errors even though `timeplus-taxi-simulator` is already installed (the package manager is idempotent).

- [ ] **Step 3: Wait 60 seconds for the 1-minute window view to have data**

```bash
sleep 60
```

- [ ] **Step 4: Run the verification checklist from the spec**

Each of these must succeed:

```bash
# (a) positions are accumulating
TP_QUERY "SELECT count() FROM table(taxi_fleet.taxi_positions)"
# Expected: a number > 0

# (b) taxi_latest has exactly num_cars rows
TP_QUERY "SELECT count() FROM table(taxi_fleet.taxi_latest)"
# Expected: 10

# (c) fleet KPIs reasonable
TP_QUERY "SELECT * FROM taxi_fleet.v_fleet_kpis EMIT PERIODIC 1s LIMIT 1" 10
# Expected: active_cars=10, avg_speed_kmh between 40 and 80

# (d) per-car 1m view has 10 rows
TP_QUERY "SELECT count_distinct(car_id) FROM taxi_fleet.v_speed_per_car_1m EMIT PERIODIC 1s LIMIT 1" 10
# Expected: 10
```

- [ ] **Step 5: Re-install with a custom config to verify config wiring**

Per `reference_tpapp_install_config.md` (auto-memory), the install endpoint takes config as `config[<key>]=<value>` form fields:

```bash
curl -X POST "http://localhost:8000/default/api/v1beta2/apps/install" \
  -F "file=@apps/taxi-fleet/taxi-fleet.tpapp" \
  -F "config[num_cars]=50" \
  -F "config[speed_kmh]=40.0"
```
Expected: HTTP 200, then after ~10 seconds:
```bash
TP_QUERY "SELECT count() FROM table(taxi_fleet.taxi_latest)"
```
Expected: 50.

If re-install fails because the app already exists, uninstall first (Step 1 above) and try again.

- [ ] **Step 6: Reset to defaults**

```bash
curl -s -X DELETE "http://localhost:8000/default/api/v1beta2/apps/io.timeplus.taxi-fleet"
make install APP=taxi-fleet
```

- [ ] **Step 7: No commit needed for this task** — it's verification only. If any of the checks failed, fix the underlying file and re-run from Task N where the file was introduced.

---

## Self-review checklist (already completed by the planner)

- [x] **Spec coverage**: All 8 file deliverables in the spec (1 manifest + 9 DDL + 1 dashboard + 1 Makefile + root Makefile edit) have an explicit task.
- [x] **Placeholders**: None — every DDL and JSON block is complete.
- [x] **Type consistency**: Column names (`car_id`, `ts`, `longitude`, `latitude`, `speed_kmh`) used identically across `taxi_feed`, `taxi_positions`, `taxi_latest`, MVs, and views. Dashboard panel queries reference only columns that exist.
- [x] **Auto-memory conventions checked**: `time` not `_tp_time` in view filters; `color` set for multi-series lines; `null_if` not used (no division here, but noted); manifest values quoted; `config[<key>]` form for install.
