# OCSF Demo App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `apps/ocsf/` Timeplus app that ingests synthetic OCSF security events from the `timeplus-ocsf-simulator` Python package and surfaces real-time threat-detection analytics in a dashboard.

**Architecture:** Python streaming `external_stream` calls `ocsf_simulator.stream_ocsf_events`, yielding `(raw, class_uid, generated_at)` tuples. An MV ingests into a regular `ocsf_events(raw, class_uid)` stream with TTL. Four flatten views (auth/network/process/security finding) project nested JSON fields into typed columns. A single dashboard renders ~14 panels grouped by event class.

**Tech Stack:** Timeplus (Proton SQL), Go `text/template` DDL, Python streaming function, `timeplus-ocsf-simulator` (PyPI), Vistral dashboard JSON.

**Spec:** `docs/superpowers/specs/2026-05-28-ocsf-demo-app-design.md`

---

## Conventions used by this plan

**Project root:** `/Users/gangtao/Code/timeplus/apps`

**Verification HTTP endpoints (assumes Timeplus runs on localhost):**

- Install:  `POST http://localhost:8000/default/api/v1beta2/apps/install` (multipart: `file=@<path>.tpapp`)
- Delete:   `DELETE http://localhost:8000/default/api/v1beta2/apps/io.timeplus.ocsf`
- Ad-hoc SQL: `POST http://localhost:8123/?default_format=PrettyCompact` with HTTP basic auth `proton:proton@t+` and SQL in the request body. Append `SETTINGS query_mode = 'table'` to terminate streaming queries.

**Helper command** used in every verification step:

```bash
sql() { echo "$1" | curl -s -u 'proton:proton@t+' --data-binary @- 'http://localhost:8123/?default_format=PrettyCompact'; }
```

Run this once at the start of each shell session, or paste the equivalent inline.

**Reinstall pattern:** the install endpoint rejects an already-installed app. Between tasks, run:

```bash
curl -s -X DELETE http://localhost:8000/default/api/v1beta2/apps/io.timeplus.ocsf
make build install APP=ocsf
```

If DELETE returns a 404 but the database survives (a known quirk in this Timeplus version), drop it manually:

```bash
sql "DROP DATABASE IF EXISTS ocsf"
```

then reinstall.

**Commit cadence:** one commit per task. Use Conventional Commits with an `ocsf:` scope.

---

## Pre-flight: Task 0 — Verify simulator package signature

This is the only risky inference in the spec. Confirm it before writing the external_stream.

**Files:** none (local check only)

- [ ] **Step 1: Install the simulator into a throwaway venv**

```bash
cd /tmp && python3 -m venv ocsf-check && source ocsf-check/bin/activate
pip install timeplus-ocsf-simulator
```

- [ ] **Step 2: Inspect the public API**

```bash
python3 - <<'PY'
import ocsf_simulator, inspect, pkgutil
print("module file:", ocsf_simulator.__file__)
print("exports:", [n for n in dir(ocsf_simulator) if not n.startswith("_")])
for name in ("stream_ocsf_events", "JSONSchemaFaker"):
    if hasattr(ocsf_simulator, name):
        obj = getattr(ocsf_simulator, name)
        try:
            print(name, "signature:", inspect.signature(obj))
        except (TypeError, ValueError):
            print(name, "type:", type(obj).__name__)
PY
```

Expected: a signature for `stream_ocsf_events` listing keyword arguments. Confirm that the keyword names used in the spec — `event_classes`, `interval`, `batch_size`, `ocsf_version` — exist. If any differ, write them down; you will need to adjust the external_stream in Task 2.

- [ ] **Step 3: Run a tiny sample to confirm event shape**

```bash
python3 - <<'PY'
from ocsf_simulator import stream_ocsf_events
import itertools, json
for ev in itertools.islice(stream_ocsf_events(event_classes=[3002], interval=0.1, batch_size=1), 1):
    print(json.dumps(ev)[:400])
    print("has class_uid:", "class_uid" in ev)
PY
```

Expected: one JSON line containing `class_uid: 3002` and OCSF-shaped nested fields.

- [ ] **Step 4: Clean up**

```bash
deactivate && rm -rf /tmp/ocsf-check
```

- [ ] **Step 5: Record findings in the plan (no commit yet — local notes file)**

If signature differs, write a one-line note to `/tmp/ocsf-sig.txt` like:

```
stream_ocsf_events(classes=..., delay=..., n=..., schema_version=...)
```

You will use this in Task 2 to keep the keyword names correct. No git commit yet.

---

## Task 1 — Scaffold the app directory

**Files:**
- Create: `apps/ocsf/Makefile`
- Create: `apps/ocsf/manifest.yaml`
- Create: `apps/ocsf/ddl/.gitkeep`
- Create: `apps/ocsf/dashboards/.gitkeep`

- [ ] **Step 1: Create the directory tree**

```bash
cd /Users/gangtao/Code/timeplus/apps
mkdir -p apps/ocsf/ddl apps/ocsf/dashboards
touch apps/ocsf/ddl/.gitkeep apps/ocsf/dashboards/.gitkeep
```

- [ ] **Step 2: Write the Makefile (copy from market-data, change APP_NAME)**

Content of `apps/ocsf/Makefile`:

```make
APP_NAME    ?= ocsf
OUT         ?= $(APP_NAME).tpapp

NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default

.PHONY: build install

build:
	zip -r $(OUT) manifest.yaml ddl/ dashboards/

install: build
	curl -X POST $(NEUTRON_URL)/$(TENANT)/api/v1beta2/apps/install -F "file=@$(OUT)"
```

- [ ] **Step 3: Write a manifest skeleton with no resources yet**

Content of `apps/ocsf/manifest.yaml`:

```yaml
package_format_version: 1
id: io.timeplus.ocsf
name: OCSF Security Event Analytics
version: 1.0.0
author: Timeplus
icon: "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA0OCA0OCI+PGRlZnM+PGxpbmVhckdyYWRpZW50IGlkPSJiZyIgeDE9IjAiIHkxPSIwIiB4Mj0iNDgiIHkyPSI0OCIgZ3JhZGllbnRVbml0cz0idXNlclNwYWNlT25Vc2UiPjxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiNENTNGOEMiLz48c3RvcCBvZmZzZXQ9IjEwMCUiIHN0b3AtY29sb3I9IiM5RjJCQzAiLz48L2xpbmVhckdyYWRpZW50PjwvZGVmcz48cmVjdCB3aWR0aD0iNDgiIGhlaWdodD0iNDgiIHJ4PSIxMSIgZmlsbD0idXJsKCNiZykiLz48cGF0aCBkPSJNMjQgMTAgTDM2IDE0Ljc1IFYyNCBDMzYgMzEgMzAuNSAzNyAyNCAzOSBDMTcuNSAzNyAxMiAzMSAxMiAyNCBWMTQuNzUgWiIgc3Ryb2tlPSJ3aGl0ZSIgc3Ryb2tlLXdpZHRoPSIxLjUiIHN0cm9rZS1saW5lam9pbj0icm91bmQiIGZpbGw9Im5vbmUiLz48Y2lyY2xlIGN4PSIyNCIgY3k9IjI0IiByPSI0LjUiIHN0cm9rZT0id2hpdGUiIHN0cm9rZS13aWR0aD0iMS41IiBmaWxsPSJub25lIi8+PGNpcmNsZSBjeD0iMjQiIGN5PSIyNCIgcj0iMS42IiBmaWxsPSJ3aGl0ZSIvPjwvc3ZnPg=="
description: >
  Real-time OCSF (Open Cybersecurity Schema Framework) event analytics.
  Generates synthetic security events (Authentication, Network, Process,
  Security Finding) via the timeplus-ocsf-simulator, flattens nested JSON
  into typed views, and surfaces threat-detection panels in a dashboard.
db_name: ocsf
categories:
  - security
  - observability
  - demo

python_packages:
  - timeplus-ocsf-simulator

config:
  - key: event_classes
    type: string
    required: false
    default: "1007,2001,3002,4001"
    description: >
      Comma-separated OCSF class UIDs to generate. Defaults to all four
      classes flattened by this app: Process (1007), Security Finding (2001),
      Authentication (3002), Network Activity (4001).
  - key: interval_seconds
    type: string
    required: false
    default: "0.1"
    description: >
      Seconds between events emitted by the simulator (parsed as float).
      The function is a per-event iterator; 0.1 = ~10 events/sec.
  - key: ocsf_version
    type: string
    required: false
    default: "1.1.0"
    description: OCSF schema version to generate.
  - key: retention_hours
    type: integer
    required: false
    default: "24"
    description: TTL for the ocsf_events stream in hours.

resources: []

dashboards: []
```

(The icon is a small shield-with-eye SVG; feel free to swap later.)

- [ ] **Step 4: Verify build succeeds even with no resources**

```bash
cd /Users/gangtao/Code/timeplus/apps && make build APP=ocsf
```

Expected: `apps/ocsf/ocsf.tpapp` is created. (Don't install yet — empty resources list will install fine but is pointless.)

- [ ] **Step 5: Commit**

```bash
cd /Users/gangtao/Code/timeplus/apps
git add apps/ocsf/Makefile apps/ocsf/manifest.yaml apps/ocsf/ddl/.gitkeep apps/ocsf/dashboards/.gitkeep
git commit -m "ocsf: scaffold app directory and manifest skeleton"
```

Do NOT commit `apps/ocsf/ocsf.tpapp` — add it to a `.gitignore` if necessary (check the existing `.gitignore` first):

```bash
grep -q "\.tpapp" .gitignore || echo "*.tpapp" >> .gitignore
git add .gitignore && git diff --cached --quiet || git commit -m "gitignore: ignore .tpapp build artifacts"
```

---

## Task 2 — External stream calling the simulator

**Files:**
- Create: `apps/ocsf/ddl/001_ocsf_events_source.sql`
- Modify: `apps/ocsf/manifest.yaml` (append to `resources:`)

- [ ] **Step 1: Write `apps/ocsf/ddl/001_ocsf_events_source.sql`**

```sql
CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.ocsf_events_source (
  raw           string,
  class_uid     uint32,
  generated_at  datetime64(3)
)
AS $$
import json
import time
from datetime import datetime
from ocsf_simulator import stream_ocsf_events

def read_ocsf_events():
    classes = [int(x) for x in "{{ .Config.event_classes }}".split(",") if x.strip()]
    interval = float("{{ .Config.interval_seconds }}")
    version = "{{ .Config.ocsf_version }}"

    while True:
        try:
            for event in stream_ocsf_events(
                event_classes=classes,
                interval=interval,
                ocsf_version=version,
            ):
                yield (
                    json.dumps(event),
                    int(event.get("class_uid", 0)),
                    datetime.utcnow(),
                )
        except Exception:
            time.sleep(5)
$$
SETTINGS type='python', mode='streaming', read_function_name='read_ocsf_events';
```

**Task 0 finding applied:** `batch_size` removed (no such kwarg in the installed simulator). The function is a per-event iterator; throughput is controlled by `interval` alone. Events include a `_simulator` metadata key which we keep in the JSON `raw` column as-is. Keep the column tuple shape `(raw_json, class_uid, generated_at)`.

- [ ] **Step 2: Append the resource to `apps/ocsf/manifest.yaml`**

Change `resources: []` to:

```yaml
resources:
  - file: ddl/001_ocsf_events_source.sql
    type: external_stream
    name: ocsf_events_source
```

- [ ] **Step 3: Build and install**

```bash
cd /Users/gangtao/Code/timeplus/apps
curl -s -X DELETE http://localhost:8000/default/api/v1beta2/apps/io.timeplus.ocsf || true
echo "DROP DATABASE IF EXISTS ocsf" | curl -s -u 'proton:proton@t+' --data-binary @- 'http://localhost:8123/?default_format=PrettyCompact'
make build install APP=ocsf
```

Expected: install response includes the app id. If install fails with `No module named 'ocsf_simulator'`, wait 30s for Python package install and try the install once more (the package install is async).

- [ ] **Step 4: Verify the source stream exists**

```bash
sql() { echo "$1" | curl -s -u 'proton:proton@t+' --data-binary @- 'http://localhost:8123/?default_format=PrettyCompact'; }
sql "SHOW STREAMS FROM ocsf"
```

Expected: `ocsf_events_source` appears in the output.

- [ ] **Step 5: Verify rows flow**

Wait ~10 seconds, then:

```bash
sql "SELECT raw, class_uid FROM ocsf.ocsf_events_source LIMIT 3 SETTINGS query_mode = 'table'"
```

Expected: 3 rows, each with a JSON `raw` and a non-zero `class_uid` in {1007, 2001, 3002, 4001}.

If you get `Python script execution error: ...` instead, the simulator keyword names were wrong. Re-run Task 0 step 2, fix `001_ocsf_events_source.sql`, and retry from Task 2 step 3.

- [ ] **Step 6: Commit**

```bash
git add apps/ocsf/ddl/001_ocsf_events_source.sql apps/ocsf/manifest.yaml
git commit -m "ocsf: add external_stream reading from timeplus-ocsf-simulator"
```

---

## Task 3 — Ingest stream + MV

**Files:**
- Create: `apps/ocsf/ddl/002_ocsf_events.sql`
- Create: `apps/ocsf/ddl/003_mv_ocsf_events_ingest.sql`
- Modify: `apps/ocsf/manifest.yaml`

- [ ] **Step 1: Write `apps/ocsf/ddl/002_ocsf_events.sql`**

```sql
CREATE STREAM IF NOT EXISTS {{ .DB }}.ocsf_events (
  raw       string,
  class_uid uint32
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.retention_hours }} HOUR;
```

- [ ] **Step 2: Write `apps/ocsf/ddl/003_mv_ocsf_events_ingest.sql`**

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_ocsf_events_ingest
INTO {{ .DB }}.ocsf_events AS
SELECT raw, class_uid
FROM {{ .DB }}.ocsf_events_source;
```

- [ ] **Step 3: Append both resources to `apps/ocsf/manifest.yaml`**

Under `resources:`:

```yaml
  - file: ddl/002_ocsf_events.sql
    type: stream
    name: ocsf_events
  - file: ddl/003_mv_ocsf_events_ingest.sql
    type: materialized_view
    name: mv_ocsf_events_ingest
```

- [ ] **Step 4: Reinstall**

```bash
cd /Users/gangtao/Code/timeplus/apps
curl -s -X DELETE http://localhost:8000/default/api/v1beta2/apps/io.timeplus.ocsf || true
sql "DROP DATABASE IF EXISTS ocsf"
make build install APP=ocsf
```

- [ ] **Step 5: Verify rows land in `ocsf_events`**

Wait ~30 seconds (cold start + first events):

```bash
sql "SELECT class_uid, count() FROM ocsf.ocsf_events GROUP BY class_uid SETTINGS query_mode='table'"
```

Expected: 4 rows for class_uids 1007, 2001, 3002, 4001 with positive counts.

- [ ] **Step 6: Commit**

```bash
git add apps/ocsf/ddl/002_ocsf_events.sql apps/ocsf/ddl/003_mv_ocsf_events_ingest.sql apps/ocsf/manifest.yaml
git commit -m "ocsf: persist events into stream via ingest MV"
```

---

## Task 4 — Authentication flatten view (3002)

**Files:**
- Create: `apps/ocsf/ddl/004_v_ocsf_authentication_flatten.sql`
- Modify: `apps/ocsf/manifest.yaml`

**Source to copy from:** `/Users/gangtao/Code/timeplus/demos/cases/ocsf/extraction.sql`, the `CREATE VIEW ocsf.v_ocsf_authentication_flatten` block (lines 11–23 in that file). It is one massive `SELECT` with hundreds of `json_extract_*` calls; copy it verbatim and apply the edits below.

- [ ] **Step 1: Copy the auth view into the new file**

```bash
cp /dev/null /Users/gangtao/Code/timeplus/apps/apps/ocsf/ddl/004_v_ocsf_authentication_flatten.sql
```

Open the source file and copy the `CREATE VIEW ocsf.v_ocsf_authentication_flatten AS SELECT ... ;` block into the new file.

- [ ] **Step 2: Apply the three mechanical edits**

Inside the new file:

1. Replace `CREATE VIEW ocsf.v_ocsf_authentication_flatten` → `CREATE VIEW IF NOT EXISTS {{ .DB }}.v_ocsf_authentication_flatten`.
2. Replace `FROM\n      ocsf.ocsf_events` (or wherever the source table appears) → `FROM\n      {{ .DB }}.ocsf_events`.
3. Replace `(json_value(raw, '$.\`class_uid\`') = '3002')` → `class_uid = 3002`. The surrounding `AND (_tp_time > earliest_timestamp())` clause stays.

After edits, the file starts with:

```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_ocsf_authentication_flatten
AS
SELECT
  _tp_time, activity_id, category_uid, class_uid, severity_id, event_time, ...
```

and ends with:

```sql
    FROM
      {{ .DB }}.ocsf_events
    WHERE
      class_uid = 3002 AND (_tp_time > earliest_timestamp())
  );
```

- [ ] **Step 3: Append to manifest**

```yaml
  - file: ddl/004_v_ocsf_authentication_flatten.sql
    type: view
    name: v_ocsf_authentication_flatten
```

- [ ] **Step 4: Reinstall**

```bash
cd /Users/gangtao/Code/timeplus/apps
curl -s -X DELETE http://localhost:8000/default/api/v1beta2/apps/io.timeplus.ocsf || true
sql "DROP DATABASE IF EXISTS ocsf"
make build install APP=ocsf
```

- [ ] **Step 5: Verify the view returns rows with parsed fields**

Wait ~30 seconds:

```bash
sql "SELECT user_name, status, src_endpoint_ip, src_location_country FROM ocsf.v_ocsf_authentication_flatten LIMIT 3 SETTINGS query_mode='table'"
```

Expected: 3 rows with non-empty `user_name` and a `status` of `Success` or `Failure`.

If install fails with `Multi-statements are not allowed`, the file has more than one `;`-terminated statement — re-check the copy.

- [ ] **Step 6: Commit**

```bash
git add apps/ocsf/ddl/004_v_ocsf_authentication_flatten.sql apps/ocsf/manifest.yaml
git commit -m "ocsf: add authentication (3002) flatten view"
```

---

## Task 5 — Network Activity flatten view (4001)

**Files:**
- Create: `apps/ocsf/ddl/005_v_ocsf_network_activity_flatten.sql`
- Modify: `apps/ocsf/manifest.yaml`

**Source to copy:** the `CREATE VIEW ocsf.v_ocsf_network_activity_flatten` block in `demos/cases/ocsf/extraction.sql` (around lines 26–33). This is the simpler one — a single `SELECT` without a subquery.

- [ ] **Step 1: Copy the network view into the new file**

- [ ] **Step 2: Apply the three mechanical edits**

1. `CREATE VIEW ocsf.v_ocsf_network_activity_flatten` → `CREATE VIEW IF NOT EXISTS {{ .DB }}.v_ocsf_network_activity_flatten`.
2. `FROM\n  ocsf.ocsf_events` → `FROM\n  {{ .DB }}.ocsf_events`.
3. `(json_value(raw, '$.\`class_uid\`') = '4001')` → `class_uid = 4001`. Keep the `AND (_tp_time > earliest_timestamp())` clause.

- [ ] **Step 3: Append to manifest**

```yaml
  - file: ddl/005_v_ocsf_network_activity_flatten.sql
    type: view
    name: v_ocsf_network_activity_flatten
```

- [ ] **Step 4: Reinstall**

```bash
cd /Users/gangtao/Code/timeplus/apps
curl -s -X DELETE http://localhost:8000/default/api/v1beta2/apps/io.timeplus.ocsf || true
sql "DROP DATABASE IF EXISTS ocsf"
make build install APP=ocsf
```

- [ ] **Step 5: Verify**

```bash
sql "SELECT src_ip, dst_ip, protocol_name, traffic_bytes FROM ocsf.v_ocsf_network_activity_flatten LIMIT 3 SETTINGS query_mode='table'"
```

Expected: 3 rows with IPs and protocol names like `TCP`/`UDP`.

- [ ] **Step 6: Commit**

```bash
git add apps/ocsf/ddl/005_v_ocsf_network_activity_flatten.sql apps/ocsf/manifest.yaml
git commit -m "ocsf: add network activity (4001) flatten view"
```

---

## Task 6 — Process Activity flatten view (1007)

**Files:**
- Create: `apps/ocsf/ddl/006_v_ocsf_process_activity_flatten.sql`
- Modify: `apps/ocsf/manifest.yaml`

**Source:** the `CREATE VIEW ocsf.v_ocsf_process_activity_flatten` block in `demos/cases/ocsf/extraction.sql` (around lines 35–42). Single `SELECT`, no subquery.

- [ ] **Step 1: Copy the process view into the new file**

- [ ] **Step 2: Apply the three mechanical edits**

1. `CREATE VIEW ocsf.v_ocsf_process_activity_flatten` → `CREATE VIEW IF NOT EXISTS {{ .DB }}.v_ocsf_process_activity_flatten`.
2. `FROM\n  ocsf.ocsf_events` → `FROM\n  {{ .DB }}.ocsf_events`.
3. `(json_value(raw, '$.\`class_uid\`') = '1007')` → `class_uid = 1007`. Keep `AND (_tp_time > earliest_timestamp())`.

- [ ] **Step 3: Append to manifest**

```yaml
  - file: ddl/006_v_ocsf_process_activity_flatten.sql
    type: view
    name: v_ocsf_process_activity_flatten
```

- [ ] **Step 4: Reinstall**

```bash
cd /Users/gangtao/Code/timeplus/apps
curl -s -X DELETE http://localhost:8000/default/api/v1beta2/apps/io.timeplus.ocsf || true
sql "DROP DATABASE IF EXISTS ocsf"
make build install APP=ocsf
```

- [ ] **Step 5: Verify**

```bash
sql "SELECT device_hostname, process_name, process_user_name, activity_name FROM ocsf.v_ocsf_process_activity_flatten LIMIT 3 SETTINGS query_mode='table'"
```

Expected: 3 rows with non-empty hostname and process name.

- [ ] **Step 6: Commit**

```bash
git add apps/ocsf/ddl/006_v_ocsf_process_activity_flatten.sql apps/ocsf/manifest.yaml
git commit -m "ocsf: add process activity (1007) flatten view"
```

---

## Task 7 — Security Finding flatten view (2001)

**Files:**
- Create: `apps/ocsf/ddl/007_v_ocsf_security_finding_flatten.sql`
- Modify: `apps/ocsf/manifest.yaml`

**Source:** the `CREATE VIEW ocsf.v_ocsf_security_finding_flatten` block in `demos/cases/ocsf/extraction.sql` (around lines 44–56). This one is wrapped in a subquery just like the auth view.

- [ ] **Step 1: Copy the security finding view into the new file**

- [ ] **Step 2: Apply the three mechanical edits**

1. `CREATE VIEW ocsf.v_ocsf_security_finding_flatten` → `CREATE VIEW IF NOT EXISTS {{ .DB }}.v_ocsf_security_finding_flatten`.
2. `FROM\n      ocsf.ocsf_events` (inside the subquery) → `FROM\n      {{ .DB }}.ocsf_events`.
3. `(json_value(raw, '$.\`class_uid\`') = '2001')` → `class_uid = 2001`. Keep `AND (_tp_time > earliest_timestamp())`.

- [ ] **Step 3: Append to manifest**

```yaml
  - file: ddl/007_v_ocsf_security_finding_flatten.sql
    type: view
    name: v_ocsf_security_finding_flatten
```

- [ ] **Step 4: Reinstall**

```bash
cd /Users/gangtao/Code/timeplus/apps
curl -s -X DELETE http://localhost:8000/default/api/v1beta2/apps/io.timeplus.ocsf || true
sql "DROP DATABASE IF EXISTS ocsf"
make build install APP=ocsf
```

- [ ] **Step 5: Verify**

```bash
sql "SELECT severity, malware_classification, malware_name, finding_title FROM ocsf.v_ocsf_security_finding_flatten LIMIT 3 SETTINGS query_mode='table'"
```

Expected: 3 rows with a severity in {Low, Medium, High, Critical}.

- [ ] **Step 6: Commit**

```bash
git add apps/ocsf/ddl/007_v_ocsf_security_finding_flatten.sql apps/ocsf/manifest.yaml
git commit -m "ocsf: add security finding (2001) flatten view"
```

---

## Task 8 — Dashboard JSON

**Files:**
- Create: `apps/ocsf/dashboards/main.json`
- Modify: `apps/ocsf/manifest.yaml`

This is the largest task. Use `apps/cisco-asa-ddos/dashboards/main.json` as a structural template (panel shape, layout grid). Copy that file first, then replace its panels with the 15 panels below.

- [ ] **Step 1: Copy the cisco-asa-ddos dashboard as a starting skeleton**

```bash
cp apps/cisco-asa-ddos/dashboards/main.json apps/ocsf/dashboards/main.json
```

Then strip every panel from the `panels` array, keeping the outer dashboard structure (name, description, layout settings, etc.).

- [ ] **Step 2: Add the header strip — 4 "single value" / metric panels at the top**

For each panel below, append an entry to the dashboard's `panels` array. Each entry follows the cisco-asa-ddos panel structure: `id`, `title`, `chartType`, `viz_content` (SQL), `viz_config`, and a `layout` block with `x`, `y`, `w`, `h`. Grid is 24 wide; rows have `h=4` for metrics, `h=8` for charts/tables.

Panel A: **Events / sec (last 1m)** — at (x=0, y=0, w=6, h=4)
```sql
SELECT count() / 60.0 AS events_per_sec
FROM ocsf.ocsf_events
WHERE _tp_time > now() - 1m
SETTINGS query_mode='table'
```

Panel B: **Auth failures (5m)** — (6, 0, 6, 4)
```sql
SELECT count() AS failures
FROM ocsf.v_ocsf_authentication_flatten
WHERE status = 'Failure' AND _tp_time > now() - 5m
SETTINGS query_mode='table'
```

Panel C: **High+Critical findings (5m)** — (12, 0, 6, 4)
```sql
SELECT count() AS findings
FROM ocsf.v_ocsf_security_finding_flatten
WHERE severity IN ('High','Critical') AND _tp_time > now() - 5m
SETTINGS query_mode='table'
```

Panel D: **Active source IPs (5m)** — (18, 0, 6, 4)
```sql
SELECT count(DISTINCT src_endpoint_ip) AS unique_sources
FROM ocsf.v_ocsf_authentication_flatten
WHERE _tp_time > now() - 5m
SETTINGS query_mode='table'
```

Use `chartType: "metric"` (or whatever the cisco app uses for single-value panels — copy that shape exactly).

- [ ] **Step 3: Authentication section (y=4 row)**

Panel E: **Failed vs Successful auths/min** — line chart, (0, 4, 12, 8)
```sql
SELECT window_start AS time, status, count() AS auths
FROM tumble(ocsf.v_ocsf_authentication_flatten, 1m)
GROUP BY window_start, status
```
Required `viz_config.config.color: "status"` (per project memory — multi-series needs color).

Panel F: **Top failed sources (15m)** — table, (12, 4, 6, 8)
```sql
SELECT src_endpoint_ip, src_location_country, count() AS failed
FROM ocsf.v_ocsf_authentication_flatten
WHERE status = 'Failure' AND _tp_time > now() - 15m
GROUP BY src_endpoint_ip, src_location_country
ORDER BY failed DESC
LIMIT 10
SETTINGS query_mode='table'
```

Panel G: **Brute-force candidates (5m)** — table, (18, 4, 6, 8)
```sql
SELECT window_start AS time, user_name, src_endpoint_ip, count() AS failures
FROM tumble(ocsf.v_ocsf_authentication_flatten, 5m)
WHERE status = 'Failure'
GROUP BY window_start, user_name, src_endpoint_ip
HAVING failures >= 3
ORDER BY window_start DESC
LIMIT 20
```

- [ ] **Step 4: Network section (y=12 row)**

Panel H: **Bytes by protocol** — line chart, (0, 12, 12, 8)
```sql
SELECT window_start AS time, protocol_name, sum(traffic_bytes) AS bytes
FROM tumble(ocsf.v_ocsf_network_activity_flatten, 1m)
GROUP BY window_start, protocol_name
```
`viz_config.config.color: "protocol_name"`.

Panel I: **High-severity events (15m)** — table, (12, 12, 6, 8)
```sql
SELECT _tp_time AS time, src_ip, dst_ip, protocol_name, severity, traffic_bytes
FROM ocsf.v_ocsf_network_activity_flatten
WHERE severity IN ('High','Critical') AND _tp_time > now() - 15m
ORDER BY _tp_time DESC
LIMIT 20
SETTINGS query_mode='table'
```

Panel J: **Scanning candidates (2m)** — table, (18, 12, 6, 8)
```sql
SELECT window_start AS time, src_ip, count() AS attempts, count(DISTINCT dst_ip) AS targets
FROM tumble(ocsf.v_ocsf_network_activity_flatten, 2m)
GROUP BY window_start, src_ip
HAVING attempts >= 20 AND targets >= 10
ORDER BY window_start DESC
LIMIT 20
```

- [ ] **Step 5: Process section (y=20 row)**

Panel K: **Process creates/min** — line chart, (0, 20, 12, 8)
```sql
SELECT window_start AS time, count() AS creates
FROM tumble(ocsf.v_ocsf_process_activity_flatten, 1m)
WHERE activity_name = 'Create'
GROUP BY window_start
```

Panel L: **Suspicious command lines (15m)** — table, (12, 20, 6, 8)
```sql
SELECT _tp_time AS time, device_hostname, process_name, process_cmd_line, process_user_name
FROM ocsf.v_ocsf_process_activity_flatten
WHERE (
  process_cmd_line LIKE '%powershell%ExecutionPolicy Bypass%'
  OR process_cmd_line LIKE '%cmd.exe /c%'
  OR process_cmd_line LIKE '%rundll32%'
  OR process_name IN ('psexec.exe', 'mimikatz.exe', 'procdump.exe')
) AND _tp_time > now() - 15m
ORDER BY _tp_time DESC
LIMIT 20
SETTINGS query_mode='table'
```

Panel M: **Privilege-mismatch events (15m)** — table, (18, 20, 6, 8)
```sql
SELECT _tp_time AS time, device_hostname, process_name, process_user_type, actor_user_type
FROM ocsf.v_ocsf_process_activity_flatten
WHERE process_user_type != actor_user_type
  AND (process_user_type = 'Admin' OR actor_user_type = 'Admin')
  AND _tp_time > now() - 15m
ORDER BY _tp_time DESC
LIMIT 20
SETTINGS query_mode='table'
```

- [ ] **Step 6: Security Findings section (y=28 row)**

Panel N: **Critical+High findings/min** — line chart, (0, 28, 12, 8)
```sql
SELECT window_start AS time, severity, count() AS findings
FROM tumble(ocsf.v_ocsf_security_finding_flatten, 1m)
WHERE severity IN ('Critical','High')
GROUP BY window_start, severity
```
`viz_config.config.color: "severity"`.

Panel O: **Malware by classification (15m)** — table, (12, 28, 6, 8)
```sql
SELECT malware_classification, count() AS detections, count(DISTINCT resource_name) AS resources
FROM ocsf.v_ocsf_security_finding_flatten
WHERE malware_name IS NOT NULL AND _tp_time > now() - 15m
GROUP BY malware_classification
ORDER BY detections DESC
SETTINGS query_mode='table'
```

Panel P: **Top finding titles (15m)** — table, (18, 28, 6, 8)
```sql
SELECT finding_title, count() AS occurrences, max(severity) AS max_severity
FROM ocsf.v_ocsf_security_finding_flatten
WHERE _tp_time > now() - 15m
GROUP BY finding_title
ORDER BY occurrences DESC
LIMIT 10
SETTINGS query_mode='table'
```

- [ ] **Step 7: About panel at the bottom (y=36 row, full width markdown)**

Panel Q: (0, 36, 24, 6), `chartType: "text"`, `viz_content: "SELECT 1"` (per project memory — markdown panels need a non-empty stub query).

Markdown body in `viz_config.config.markdown` (or wherever the cisco-asa-ddos markdown panel stores it — match its shape exactly):

```markdown
### OCSF Security Event Analytics

Real-time analytics over the [Open Cybersecurity Schema Framework](https://schema.ocsf.io/)
event stream emitted by the [`timeplus-ocsf-simulator`](https://pypi.org/project/timeplus-ocsf-simulator/) package.

Four event classes are flattened and surfaced above: **Authentication (3002)**,
**Network Activity (4001)**, **Process Activity (1007)**, and **Security Finding (2001)**.

> Heads-up: the simulator generates random IPs and user names for each event,
> so cross-class correlations (e.g. linking an authentication failure to a
> subsequent suspicious process by IP) will not match. Each section above is
> self-contained per class.
```

- [ ] **Step 8: Register the dashboard in the manifest**

```yaml
dashboards:
  - file: dashboards/main.json
    name: OCSF Security Events
    description: Real-time authentication, network, process, and security-finding analytics
```

- [ ] **Step 9: Reinstall**

```bash
cd /Users/gangtao/Code/timeplus/apps
curl -s -X DELETE http://localhost:8000/default/api/v1beta2/apps/io.timeplus.ocsf || true
sql "DROP DATABASE IF EXISTS ocsf"
make build install APP=ocsf
```

- [ ] **Step 10: Validate each panel query individually**

For each of the 16 panel queries (A–Q minus the markdown one), run it via the `sql` helper and confirm it returns rows (or empty, but no error). Example:

```bash
sql "SELECT window_start AS time, status, count() AS auths FROM tumble(ocsf.v_ocsf_authentication_flatten, 1m) GROUP BY window_start, status SETTINGS query_mode='table'"
```

If any query errors, fix the SQL in the dashboard JSON and reinstall.

- [ ] **Step 11: Open the dashboard in a browser and visually verify**

Navigate to `http://localhost:8000/default` → Dashboards → "OCSF Security Events". Confirm:
- All 17 panels render without "loading…" hangs.
- Multi-series line charts (Panel E, H, N) show one series per status/protocol/severity (not collapsed to a single line).
- Tables show rows within ~60s after the install.
- The About markdown renders as text, not as a spinner.

If a line chart collapses to a single series, re-check that `viz_config.config.color` points at the correct column name. The dashboard UI may persist rendered template values — if you edit via the UI, run `git diff HEAD apps/ocsf/dashboards/main.json` and restore the source.

- [ ] **Step 12: Commit**

```bash
git add apps/ocsf/dashboards/main.json apps/ocsf/manifest.yaml
git commit -m "ocsf: add dashboard with per-class security analytics panels"
```

---

## Task 9 — README

**Files:**
- Create: `apps/ocsf/README.md`

- [ ] **Step 1: Write `apps/ocsf/README.md`** mirroring the style of `apps/market-data/readme.md`:

```markdown
# OCSF Security Event Analytics

Real-time analytics over [OCSF](https://schema.ocsf.io/) events generated by
[`timeplus-ocsf-simulator`](https://pypi.org/project/timeplus-ocsf-simulator/).

## Install

```bash
make build install APP=ocsf
# or directly
curl -X POST http://localhost:8000/default/api/v1beta2/apps/install \
  -F "file=@apps/ocsf/ocsf.tpapp"
```

## What it builds

- `ocsf.ocsf_events_source` — Python external stream calling the simulator
- `ocsf.ocsf_events` — typed stream `(raw, class_uid)` with configurable TTL
- Four flatten views: `v_ocsf_authentication_flatten` (3002),
  `v_ocsf_network_activity_flatten` (4001),
  `v_ocsf_process_activity_flatten` (1007),
  `v_ocsf_security_finding_flatten` (2001)
- One dashboard with ~16 panels grouped by event class

## Config

| Key | Default | Notes |
|---|---|---|
| `event_classes` | `1007,2001,3002,4001` | comma-separated OCSF class UIDs |
| `interval_seconds` | `1.0` | simulator batch cadence (float) |
| `batch_size` | `10` | events per batch |
| `ocsf_version` | `1.1.0` | OCSF schema version |
| `retention_hours` | `24` | TTL for `ocsf_events` |

## Notes

- Simulator data is random per event; cross-class joins by IP/user will not
  correlate. Each dashboard section is self-contained.
- Python package install is async; the external_stream's Python generator
  has a reconnect loop that tolerates the initial race.
```

- [ ] **Step 2: Commit**

```bash
git add apps/ocsf/README.md
git commit -m "ocsf: add README"
```

---

## Final verification

- [ ] **Step 1: Fresh-install smoke test**

```bash
cd /Users/gangtao/Code/timeplus/apps
curl -s -X DELETE http://localhost:8000/default/api/v1beta2/apps/io.timeplus.ocsf || true
sql "DROP DATABASE IF EXISTS ocsf"
make build install APP=ocsf
```

Wait 60 seconds.

- [ ] **Step 2: Run the install-completeness check**

```bash
sql "SHOW STREAMS FROM ocsf SETTINGS query_mode='table'"
sql "SHOW VIEWS FROM ocsf SETTINGS query_mode='table'"
sql "SELECT class_uid, count() FROM ocsf.ocsf_events GROUP BY class_uid SETTINGS query_mode='table'"
```

Expected:
- Streams: `ocsf_events_source`, `ocsf_events`
- Views: `mv_ocsf_events_ingest` and all four `v_ocsf_*_flatten` views
- Per-class counts: all four UIDs present with positive counts

- [ ] **Step 3: Visual dashboard check**

Open `http://localhost:8000/default` → Dashboards → "OCSF Security Events". All 17 panels render with data within 60s.

- [ ] **Step 4: PR-ready check**

```bash
git log --oneline feature/39-ocsf-demo ^main
```

Expected: a small series of `ocsf: ...` commits (one per task) plus the spec commit.
