# OCSF Demo App — Design

**Date:** 2026-05-28
**Status:** Approved — ready for implementation plan
**Target path:** `apps/ocsf/`

## Goal

Add a new `.tpapp` to this repo that demonstrates real-time OCSF (Open
Cybersecurity Schema Framework) event analytics on Timeplus. The app should be
self-contained: a single `make install` produces a live security analytics
dashboard with no external services required other than a Python package pulled
from PyPI.

## Source material

- **Simulator:** [`timeplus-ocsf-simulator`](https://pypi.org/project/timeplus-ocsf-simulator/)
  on PyPI. Provides `stream_ocsf_events(...)`, a Python generator that yields
  OCSF JSON events. Also exposes an `ocsf-sim` CLI (unused here).
- **Reference SQL:** `/Users/gangtao/Code/timeplus/demos/cases/ocsf/` —
  `source.sql`, `extraction.sql`, `analysis.sql`, `sequence_analysis.sql`.
  We adopt the source stream shape and the four flatten views verbatim
  (with mechanical edits), and translate a subset of `analysis.sql` queries
  into dashboard panels.
- **App patterns to mirror:**
  - `apps/market-data/` — Python streaming `external_stream` pattern.
  - `apps/cisco-asa-ddos/` — security-themed demo, manifest config knobs.

## Non-goals (v1)

- No webhook alerts. Pure observability.
- No cross-schema (auth↔process↔network) correlation queries — the simulator
  emits random IPs/users that do not join across classes.
- No sequence analysis (`LAG`/`LAGS`) queries shipped as resources. Can be
  added later if users ask.
- No File System Activity (1001) events.

## Architecture

```
SYSTEM INSTALL PYTHON PACKAGE timeplus-ocsf-simulator   (async)
  └── ocsf_events_source                          (external_stream)
        │  Python generator yields:
        │    raw string, class_uid uint32, generated_at datetime64(3)
        │
        ├──→ ocsf_events                          (stream, TTL = retention_hours)
        │       columns: raw string, class_uid uint32
        │       fed by: mv_ocsf_events_ingest
        │
        ├──→ v_ocsf_authentication_flatten        (view, class_uid = 3002)
        ├──→ v_ocsf_network_activity_flatten      (view, class_uid = 4001)
        ├──→ v_ocsf_process_activity_flatten      (view, class_uid = 1007)
        └──→ v_ocsf_security_finding_flatten      (view, class_uid = 2001)
```

**Why an intermediate `ocsf_events` stream and not flatten-views-on-the-source?**

1. The external_stream is bound to the running Python generator. If the simulator
   restarts (package reinstall, container restart), the source halts; a regular
   stream keeps history under TTL.
2. Dashboard queries hit the stream rather than triggering the Python generator
   per panel.
3. `_tp_time` and the standard tail/replay semantics work as expected.

**Why carry `class_uid` as a top-level `uint32` column?**

The reference flatten views all begin with `WHERE json_value(raw, '$.class_uid') = 'NNNN'`.
By extracting `class_uid` at ingest time, the WHERE clauses become typed integer
comparisons (`class_uid = 3002`), which are cheaper and clearer.

## Package layout

```
apps/ocsf/
├── Makefile                       # copy of market-data's, APP_NAME=ocsf
├── manifest.yaml
├── ddl/
│   ├── 001_ocsf_events_source.sql            # external_stream + Python generator
│   ├── 002_ocsf_events.sql                   # stream
│   ├── 003_mv_ocsf_events_ingest.sql         # MV source → stream
│   ├── 004_v_ocsf_authentication_flatten.sql
│   ├── 005_v_ocsf_network_activity_flatten.sql
│   ├── 006_v_ocsf_process_activity_flatten.sql
│   └── 007_v_ocsf_security_finding_flatten.sql
└── dashboards/
    └── main.json
```

## manifest.yaml

```yaml
package_format_version: 1
id: io.timeplus.ocsf
name: OCSF Security Event Analytics
version: 1.0.0
author: Timeplus
icon: "data:image/svg+xml;base64,<base64-encoded-shield-svg>"   # chosen at implementation time; cisco-asa-ddos icon is the closest precedent
description: >
  Real-time OCSF (Open Cybersecurity Schema Framework) event analytics.
  Generates synthetic security events (Authentication, Network, Process,
  Security Finding) via the timeplus-ocsf-simulator, flattens nested JSON
  into typed views, and surfaces threat-detection panels in a dashboard.
db_name: ocsf
categories: [security, observability, demo]

python_packages:
  - timeplus-ocsf-simulator>=0.1.0   # exact lower bound resolved at implementation time against the latest PyPI release

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
    default: "1.0"
    description: Seconds between batches emitted by the simulator.
  - key: batch_size
    type: integer
    required: false
    default: "10"
    description: Number of events per batch.
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

resources:
  - { file: ddl/001_ocsf_events_source.sql,            type: external_stream,    name: ocsf_events_source }
  - { file: ddl/002_ocsf_events.sql,                   type: stream,             name: ocsf_events }
  - { file: ddl/003_mv_ocsf_events_ingest.sql,         type: materialized_view,  name: mv_ocsf_events_ingest }
  - { file: ddl/004_v_ocsf_authentication_flatten.sql, type: view,               name: v_ocsf_authentication_flatten }
  - { file: ddl/005_v_ocsf_network_activity_flatten.sql, type: view,             name: v_ocsf_network_activity_flatten }
  - { file: ddl/006_v_ocsf_process_activity_flatten.sql, type: view,             name: v_ocsf_process_activity_flatten }
  - { file: ddl/007_v_ocsf_security_finding_flatten.sql, type: view,             name: v_ocsf_security_finding_flatten }

dashboards:
  - file: dashboards/main.json
    name: OCSF Security Events
    description: Real-time authentication, network, process, and security-finding analytics
```

## Resource details

### `001_ocsf_events_source.sql`

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
    batch_size = int("{{ .Config.batch_size }}")
    version = "{{ .Config.ocsf_version }}"

    while True:
        try:
            for event in stream_ocsf_events(
                event_classes=classes,
                interval=interval,
                batch_size=batch_size,
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

**Implementation caveat:** the exact `stream_ocsf_events` keyword names are
inferred from the PyPI page. During implementation, verify against the
installed package (e.g. `python -c "import inspect, ocsf_simulator; print(inspect.signature(ocsf_simulator.stream_ocsf_events))"`).
If the signature differs, fix this single file.

### `002_ocsf_events.sql`

```sql
CREATE STREAM IF NOT EXISTS {{ .DB }}.ocsf_events (
  raw       string,
  class_uid uint32
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.retention_hours }} HOUR;
```

### `003_mv_ocsf_events_ingest.sql`

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_ocsf_events_ingest
INTO {{ .DB }}.ocsf_events AS
SELECT raw, class_uid
FROM {{ .DB }}.ocsf_events_source;
```

### `004`–`007` flatten views

Copied verbatim from `demos/cases/ocsf/extraction.sql`, with three mechanical
edits per file:

1. `ocsf.v_*` → `{{ .DB }}.v_*`; source table `ocsf.ocsf_events` → `{{ .DB }}.ocsf_events`.
2. `WHERE (json_value(raw, '$.class_uid') = 'NNNN') AND (_tp_time > earliest_timestamp())`
   becomes `WHERE class_uid = NNNN AND _tp_time > earliest_timestamp()`.
3. `CREATE VIEW` → `CREATE VIEW IF NOT EXISTS`.

No column-name or JSON-path changes — anyone copy-pasting queries from
`demos/cases/ocsf/analysis.sql` should get the same field names back.

## Dashboard (`dashboards/main.json`)

Single dashboard, four sections, ~14 panels.

**Header strip (4 markdown/counter panels):**
- Events / sec — last 1m, all classes
- Auth failures — last 5m
- High+Critical findings — last 5m
- Active source IPs — distinct, last 5m

**Authentication (3002):**
- Time series: failed vs successful auths/min (1m tumble, multi-series, `color: status`)
- Table: top failed sources — `src_endpoint_ip`, `src_location_country`, count, last 15m
- Table: brute-force candidates — user + src_ip with ≥3 failures in a 5m tumble

**Network (4001):**
- Time series: bytes in/out per minute by protocol (`color: protocol_name`)
- Table: high-severity events — src→dst, bytes, severity
- Table: scanning candidates — src_ip with ≥20 connections to ≥10 distinct dst_ip in 2m tumble

**Process (1007):**
- Time series: process creates/min
- Table: suspicious command lines — filter set from `analysis.sql` #10
  (`powershell%ExecutionPolicy Bypass`, `cmd.exe /c`, `rundll32`, `psexec.exe`, `mimikatz.exe`, `procdump.exe`)
- Table: privilege-mismatch events (`process_user_type != actor_user_type`)

**Security Finding (2001):**
- Time series: critical+high findings/min
- Table: malware by classification — count, distinct resources
- Table: top finding titles

**About panel (markdown):** one-paragraph OCSF + simulator description with a
note that cross-schema joins by IP/user will not correlate (random data).
`viz_content: "SELECT 1"` per the memory rule.

**Panel conventions** (from project memory):
- Multi-series line/area panels MUST set `viz_config.config.color` to the
  series column name.
- Filters use `_tp_time` (the flatten views preserve it — they don't alias
  `window_start AS time`).
- Markdown panels use `chartType: "text"` with `viz_content: "SELECT 1"`.
- Any text-input controls (none planned for v1) use `chartType: "text"`,
  not `"text_input"`.

## Install flow & user-visible behavior

1. `make install APP=ocsf` builds `ocsf.tpapp` and POSTs to
   `${NEUTRON_URL}/${TENANT}/api/v1beta2/apps/install`.
2. Neutron triggers `SYSTEM INSTALL PYTHON PACKAGE timeplus-ocsf-simulator`
   (async — may take 10–30s).
3. Resources are provisioned in numeric order. The external_stream may fail
   to start once if it races the Python install; its `while True` retry loop
   reconnects.
4. Within ~30s, the dashboard begins populating.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| `stream_ocsf_events` signature differs from inference | Verify locally before writing 001; one-file fix |
| Python package install race | `while True` reconnect loop in the generator |
| Reference SQL uses `extension_name` etc. that the simulator's current version omits | Flatten views return NULL for missing JSON paths — non-fatal; panels filter on populated fields only |
| Random data prevents auth↔process correlation | Documented in About panel; cross-schema views omitted by design |
| Empty `viz_content` on markdown panel leaves panel stuck loading | Memory rule applied: use `SELECT 1` |

## Out-of-scope (deferrable)

- File System Activity (1001) class + flatten view
- Sequence analysis views (`LAG`/`LAGS` patterns from `sequence_analysis.sql`)
- Webhook alerting (UDF + ALERT resource)
- A `SYSTEM PAUSE` switch for the generator
