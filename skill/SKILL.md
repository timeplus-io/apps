---
name: creating-timeplus-apps
description: Use when creating, packaging, or installing a Timeplus app (.tpapp) — converting existing SQL resources and dashboards into an installable app package, writing manifests, applying template variables, or debugging install failures
---

# Creating Timeplus Apps

## Overview

A Timeplus app (`.tpapp`) is a zip archive that bundles a streaming data pipeline — DDL resources (streams, views, materialized views) plus dashboards — into a single installable unit. The installer provisions everything in order and rolls back on failure.

## Directory Structure

```
my-app/
├── manifest.yaml          # required
├── ddl/
│   ├── 001_first.sql      # executed in filename order
│   ├── 002_second.sql
│   └── ...
└── dashboards/
    └── main.json          # array of panel objects
```

Package it:
```bash
cd my-app && zip -r ../my-app.tpapp manifest.yaml ddl/ dashboards/
```

Install via API:
```bash
curl -X POST http://localhost:8000/default/api/v1beta2/apps/install \
  -F "file=@my-app.tpapp"
```

## manifest.yaml

```yaml
package_format_version: 1          # must be 1
id: io.example.my-app              # reverse-domain, unique
name: My App
version: 1.0.0
author: Acme
description: What this app does.
db_name: my_app                    # ^[a-z][a-z0-9_]{0,31}$, used as-is

config:                            # optional — user-supplied parameters
  - key: websocket_url
    type: string
    required: false
    default: "wss://example.com/feed"
    description: WebSocket feed URL

resources:                         # executed in listed order
  - file: ddl/001_source.sql
    type: external_stream
    name: raw_feed
  - file: ddl/002_events.sql
    type: stream
    name: events
  - file: ddl/003_mv.sql
    type: materialized_view
    name: mv_events

dashboards:
  - file: dashboards/main.json
    name: My Dashboard
    description: Real-time view
```

### Resource types

| type | DDL verb | rolled back with |
|---|---|---|
| `stream` | `CREATE STREAM` | `DROP STREAM` |
| `external_stream` | `CREATE EXTERNAL STREAM` | `DROP STREAM` |
| `mutable_stream` | `CREATE MUTABLE STREAM` | `DROP STREAM` |
| `materialized_view` | `CREATE MATERIALIZED VIEW` | `DROP VIEW` |
| `view` | `CREATE VIEW` | `DROP VIEW` |
| `external_table` | `CREATE TABLE` | `DROP TABLE` |
| `udf` | `CREATE FUNCTION` | `DROP FUNCTION` |
| `system` | any `SYSTEM ...` statement | skipped (no rollback) |

## DDL Template Variables

DDL files are rendered with Go `text/template` using `{{ }}` delimiters.

| Expression | Expands to |
|---|---|
| `{{ .DB }}` | The resolved database name (value of `db_name`) |
| `{{ index .Config "key" }}` | Value of config key (after defaults applied) |

```sql
-- ddl/002_events.sql
CREATE STREAM IF NOT EXISTS {{ .DB }}.events (
  id       string,
  payload  string
)
TTL to_datetime(_tp_time) + INTERVAL 24 HOUR;
```

```sql
-- ddl/001_source.sql  (config key with underscore — must use index syntax)
CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.raw_feed (msg string)
SETTINGS url='{{ index .Config "websocket_url" }}', type='websocket';
```

**Use `IF NOT EXISTS` on every `CREATE`** — makes resources idempotent and safe for upgrade.

## Dashboard Template Variables

Dashboard JSON is rendered with `[[ ]]` delimiters (to avoid collision with the frontend's `{{filter_*}}` runtime variables).

```json
{
  "viz_content": "SELECT * FROM [[ .DB ]].events WHERE _tp_time > now() - {{filter_time_range}}"
}
```

| Expression | Expands to |
|---|---|
| `[[ .DB ]]` | Database name |
| `[[ index .Config "key" ]]` | Config value |
| `{{filter_*}}` | Left as-is — resolved by the frontend at query time |

## File Ordering and Dependencies

Name DDL files with a numeric prefix so they execute in dependency order:

```
001_python_package_json5.sql     ← system packages first
002_python_package_websocket.sql ← one statement per file for SYSTEM INSTALL
003_source_stream.sql            ← external streams / sources
004_target_stream.sql            ← destination streams
005_mv_extract.sql               ← materialized views (depend on streams)
006_v_aggregated.sql             ← views (depend on streams/MVs)
```

## Config Defaults

Declared `default` values are applied automatically before template rendering. Users only need to supply required keys or keys they want to override.

```yaml
config:
  - key: retention_hours
    type: string
    required: false
    default: "24"
    description: Stream retention in hours
```

```sql
TTL to_datetime(_tp_time) + INTERVAL {{ index .Config "retention_hours" }} HOUR
```

## Common Mistakes

### Multi-statement SQL files
**Error:** `Syntax error: Multi-statements are not allowed`  
**Fix:** One SQL statement per file. Split `SYSTEM INSTALL PYTHON PACKAGE` calls into separate files.

```
# ❌ 001_packages.sql
SYSTEM INSTALL PYTHON PACKAGE 'json5>=0.9.6';
SYSTEM INSTALL PYTHON PACKAGE 'websocket-client>=1.4.0';

# ✅ 001_pkg_json5.sql
SYSTEM INSTALL PYTHON PACKAGE 'json5>=0.9.6'

# ✅ 002_pkg_websocket.sql
SYSTEM INSTALL PYTHON PACKAGE 'websocket-client>=1.4.0'
```

Note: omit the trailing semicolon on `SYSTEM INSTALL` statements.

### Reserved column names
**Error:** `Column window_start is reserved`  
**Fix:** `window_start` (and `window_end`) are generated by tumble/hop. Name stream columns `time` or `ts` instead, and alias in the MV:
```sql
-- stream column: `time`
-- MV select:
SELECT window_start AS time, product_id, ...
```

### Config keys with underscores
**Fix:** Always use `index` syntax for map access — dot notation doesn't work for keys containing underscores:
```
✅ {{ index .Config "websocket_url" }}
❌ {{ .Config.websocket_url }}
```

### Python package timing
`SYSTEM INSTALL PYTHON PACKAGE` is asynchronous. Creating an external stream that imports the package immediately after may fail with `No module named 'X'`. Check installation status:
```sql
SELECT * FROM system.python_packages WHERE name = 'websocket-client'
```
Wait until `status = 'installed'` before proceeding.

### Wrong template delimiter in dashboards
**Fix:** Use `[[ .DB ]]` in dashboard JSON, not `{{ .DB }}`. The `{{ }}` delimiter is reserved for frontend filter variables like `{{filter_product}}`.

## Error Messages Include Resource Name

Install errors are wrapped with the resource name:
```
provision mv_coinbase_1s: code: 44, message: Column window_start is reserved...
```
The prefix (`provision <name>:`) tells you exactly which DDL file failed.

## Makefile Shortcut

```makefile
APP_DIR  ?= my-app
OUT      ?= $(APP_DIR).tpapp
NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default

build:
	cd $(APP_DIR) && zip -r ../$(OUT) manifest.yaml ddl/ dashboards/

install: build
	curl -X POST $(NEUTRON_URL)/$(TENANT)/api/v1beta2/apps/install -F "file=@$(OUT)"
```
