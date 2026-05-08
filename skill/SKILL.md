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
    required: true
    description: WebSocket feed URL
  - key: api_key
    type: string
    required: true
    secret: true                   # mask value in UI; stored as IsSecret
    description: API key
  - key: timeout
    type: integer
    required: false
    default: "30"
    description: Connection timeout in seconds
  - key: tls_enabled
    type: bool
    required: false
    default: "false"
    description: Enable TLS
  - key: topics
    type: list
    required: true
    description: Kafka topics (JSON array of strings, e.g. '["a","b"]')
  - key: broker_type
    type: choice
    required: true
    description: Message broker
    options:
      - kafka
      - pulsar
      - redpanda
  - key: features
    type: multi_choice
    required: false
    default: '["metrics"]'
    description: Features to enable
    options:
      - metrics
      - tracing
      - alerting

python_packages:                   # optional — installed before any DDL runs
  - json5>=0.9.6
  - websocket-client>=1.4.0

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

## DDL Template Variables

DDL files are rendered with Go `text/template` using `{{ }}` delimiters.

| Expression | Expands to |
|---|---|
| `{{ .DB }}` | The resolved database name (value of `db_name`) |
| `{{ .Config.key_name }}` | Value of config key (after defaults applied) |

**Always use dot notation for config values** — `{{ .Config.my_key }}`, never `{{ index .Config "my_key" }}`.

```sql
-- ddl/002_events.sql
CREATE STREAM IF NOT EXISTS {{ .DB }}.events (
  id       string,
  payload  string
)
TTL to_datetime(_tp_time) + INTERVAL 24 HOUR;
```

```sql
-- ddl/001_source.sql
CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.raw_feed (msg string)
SETTINGS url='{{ .Config.websocket_url }}', type='websocket';
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
| `[[ .Config.key ]]` | Config value |
| `{{filter_*}}` | Left as-is — resolved by the frontend at query time |

## File Ordering and Dependencies

Name DDL files with a numeric prefix so they execute in dependency order:

```
001_source_stream.sql            ← external streams / sources
002_target_stream.sql            ← destination streams
003_mv_extract.sql               ← materialized views (depend on streams)
004_v_aggregated.sql             ← views (depend on streams/MVs)
```

## Config Types

Seven types are supported. Omitting `type` defaults to `string`.

| Type | Stored as | Valid example | Notes |
|------|-----------|---------------|-------|
| `string` | plain string | `"localhost:9092"` | Default type |
| `integer` | decimal string | `"30"`, `"-5"` | Must be a whole number |
| `float` | decimal string | `"3.14"`, `"30"` | Decimal or whole |
| `bool` | `"true"` or `"false"` | `"true"` | No other values accepted |
| `list` | JSON array of strings | `["a","b"]` | Comma-separated strings NOT accepted |
| `choice` | string matching one option | `"kafka"` | Requires `options:` list |
| `multi_choice` | JSON array of strings, each matching an option | `["kafka","pulsar"]` | Requires `options:` list |

**`options`** — required for `choice` and `multi_choice`; lists the allowed values:

```yaml
  - key: broker_type
    type: choice
    required: true
    options:
      - kafka
      - pulsar
```

**`secret`** — only valid on `string` type; marks the value as sensitive (masked in UI, stored with `IsSecret: true`):

```yaml
  - key: api_key
    type: string
    required: true
    secret: true
    description: API secret key
```

**`default`** — always a string regardless of type, and must be a valid encoding for the declared type:

```yaml
  - key: timeout
    type: integer
    default: "30"         # valid — "30" is a legal integer encoding
  - key: features
    type: multi_choice
    default: '["metrics"]'
    options: [metrics, tracing]
```

## Config Defaults

Declared `default` values are applied automatically before template rendering. Users only need to supply required keys or keys they want to override.

```yaml
config:
  - key: retention_hours
    type: integer
    required: false
    default: "24"
    description: Stream retention in hours
```

```sql
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.retention_hours }} HOUR
```

## Common Mistakes

### Multi-statement SQL files
**Error:** `Syntax error: Multi-statements are not allowed`  
**Fix:** One SQL statement per file.

### Reserved column names
**Error:** `Column window_start is reserved`  
**Fix:** `window_start` (and `window_end`) are generated by tumble/hop. Name stream columns `time` or `ts` instead, and alias in the MV:
```sql
-- stream column: `time`
-- MV select:
SELECT window_start AS time, product_id, ...
```

### Python packages not available at DDL time
**Fix:** Declare packages in `python_packages` in the manifest — the installer installs them and waits for completion before running any DDL. Do not use `SYSTEM INSTALL PYTHON PACKAGE` as a DDL resource; it is not needed and has no rollback.

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
