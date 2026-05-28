# geo-ip-lookup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `geo-ip-lookup` Timeplus app — an installable `.tpapp` that loads the dbip IPv4 → city dataset into an `IP_TRIE` dictionary and exposes an interactive lookup dashboard.

**Architecture:** Mirrors the source `/Users/gangtao/Code/timeplus/demos/cases/o11y/geo_look_ups/geo.sql` 1:1 — 8 SQL statements, one per file. Non-`CREATE` statements (`CREATE USER`, `GRANT`, `INSERT`) use `type: system` resources to run at install time. Dashboard provides a text input bound to `dict_get('geo.ip_trie', ...)` calls, with a table view and a map view.

**Tech Stack:** Timeplus `.tpapp` packaging (zip archive: `manifest.yaml` + `ddl/*.sql` + `dashboards/*.json`), Go `text/template` for DDL templating, Vistral grammar (via dashboard JSON) for visualization. No Python, no streaming source.

**Spec:** `docs/superpowers/specs/2026-05-27-geo-ip-lookup-design.md`

---

## File Structure

Everything new lives under `apps/geo-ip-lookup/`. The root `Makefile` and `registry/` index get one new entry each.

```
apps/geo-ip-lookup/
├── Makefile                       # delegates to root pattern; OUT=geo-ip-lookup.tpapp
├── manifest.yaml                  # 8 resources, 2 config keys, 1 dashboard
├── ddl/
│   ├── 001_create_user.sql        # system  — CREATE USER (templated user/password)
│   ├── 002_grant_select.sql       # system  — GRANT SELECT on the DB
│   ├── 003_dbip_city_ipv4.sql     # mutable_stream — raw dbip rows, PK (ip_range_start, ip_range_end)
│   ├── 004_load_dbip.sql          # system  — INSERT … FROM url(s3-csv)
│   ├── 005_v_dbip_city_ipv4_with_cidr.sql  # view — CIDR derivation
│   ├── 006_geoip_lookup.sql       # mutable_stream — cidr → geo, PK cidr
│   ├── 007_populate_geoip.sql     # system  — INSERT … FROM view, coalesces nullables
│   └── 008_ip_trie.sql            # dictionary — IP_TRIE layout sourced from geoip_lookup
└── dashboards/
    └── main.json                  # 5 panels: md header, text_input, result table, geo map, stats
```

**Touched outside the new directory:**
- `Makefile` (root) — append `geo-ip-lookup` to the `APPS` list so `build-all`/`install-all` pick it up.

---

## Task 1: Scaffold the app directory and Makefile

**Files:**
- Create: `apps/geo-ip-lookup/Makefile`
- Create: `apps/geo-ip-lookup/ddl/` (directory)
- Create: `apps/geo-ip-lookup/dashboards/` (directory)

- [ ] **Step 1: Create the directory structure**

```bash
mkdir -p apps/geo-ip-lookup/ddl apps/geo-ip-lookup/dashboards
```

- [ ] **Step 2: Write the per-app Makefile**

Identical pattern to `apps/taxi-fleet/Makefile`. Path: `apps/geo-ip-lookup/Makefile`

```makefile
APP_NAME    ?= geo-ip-lookup
OUT         ?= $(APP_NAME).tpapp

NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default

.PHONY: build install

build:
	zip -r $(OUT) manifest.yaml ddl/ dashboards/

install: build
	curl -X POST $(NEUTRON_URL)/$(TENANT)/api/v1beta2/apps/install -F "file=@$(OUT)"
```

- [ ] **Step 3: Verify the layout**

Run: `ls -la apps/geo-ip-lookup/`
Expected:
```
Makefile
ddl/
dashboards/
```

- [ ] **Step 4: Commit**

```bash
git add apps/geo-ip-lookup/Makefile
git commit -m "geo-ip-lookup: scaffold app directory and Makefile"
```

---

## Task 2: Write DDL files (8 SQL statements, one per file)

**Files:**
- Create: `apps/geo-ip-lookup/ddl/001_create_user.sql` through `008_ip_trie.sql`

- [ ] **Step 1: Write `001_create_user.sql`**

```sql
CREATE USER IF NOT EXISTS {{ .Config.dict_user }} IDENTIFIED BY '{{ .Config.dict_password }}';
```

- [ ] **Step 2: Write `002_grant_select.sql`**

```sql
GRANT SELECT ON {{ .DB }}.* TO {{ .Config.dict_user }};
```

- [ ] **Step 3: Write `003_dbip_city_ipv4.sql`**

```sql
CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.dbip_city_ipv4
(
  `ip_range_start` ipv4,
  `ip_range_end`   ipv4,
  `country_code`   nullable(string),
  `state1`         nullable(string),
  `state2`         nullable(string),
  `city`           nullable(string),
  `postcode`       nullable(string),
  `latitude`       float64,
  `longitude`      float64,
  `timezone`       nullable(string)
)
PRIMARY KEY (ip_range_start, ip_range_end);
```

- [ ] **Step 4: Write `004_load_dbip.sql`**

```sql
INSERT INTO {{ .DB }}.dbip_city_ipv4
  (ip_range_start, ip_range_end, country_code, state1, state2, city, postcode, latitude, longitude, timezone)
SELECT
  to_ipv4(ip_range_start),
  to_ipv4(ip_range_end),
  country_code, state1, state2, city, postcode, latitude, longitude, timezone
FROM url(
  'https://tp-solutions.s3.us-west-2.amazonaws.com/ip-location-db/dbip-city-ipv4.csv.gz',
  'CSV',
  'ip_range_start ipv4, ip_range_end ipv4, country_code nullable(string), state1 nullable(string), state2 nullable(string), city nullable(string), postcode nullable(string), latitude float64, longitude float64, timezone nullable(string)'
);
```

- [ ] **Step 5: Write `005_v_dbip_city_ipv4_with_cidr.sql`**

```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_dbip_city_ipv4_with_cidr
AS
WITH
  ip_range_start,
  ip_range_end,
  bit_xor(to_ipv4(ip_range_start), to_ipv4(ip_range_end))      AS xor,
  if(xor != 0, ceil(log2(xor)), 0)                             AS unmatched,
  32 - unmatched                                               AS cidr_suffix,
  cast(bit_and(bit_not(pow(2, unmatched) - 1),
               to_ipv4(ip_range_start)), 'uint32')             AS bitand,
  to_ipv4(ipv4_num_to_string(bitand))                          AS cidr_address
SELECT
  concat(to_string(cidr_address), '/', to_string(cidr_suffix)) AS cidr,
  to_ipv4(ip_range_start)                                      AS ip_range_start,
  to_ipv4(ip_range_end)                                        AS ip_range_end,
  latitude,
  longitude,
  country_code,
  state1,
  city
FROM table({{ .DB }}.dbip_city_ipv4);
```

- [ ] **Step 6: Write `006_geoip_lookup.sql`**

```sql
CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.geoip_lookup
(
  `cidr`         string,
  `latitude`     float64,
  `longitude`    float64,
  `country_code` string,
  `state`        string,
  `city`         string
)
PRIMARY KEY cidr;
```

- [ ] **Step 7: Write `007_populate_geoip.sql`**

```sql
INSERT INTO {{ .DB }}.geoip_lookup (cidr, latitude, longitude, country_code, state, city)
SELECT
  cidr,
  latitude,
  longitude,
  coalesce(country_code, '') AS country_code,
  coalesce(state1,       '') AS state,
  coalesce(city,         '') AS city
FROM {{ .DB }}.v_dbip_city_ipv4_with_cidr;
```

- [ ] **Step 8: Write `008_ip_trie.sql`**

```sql
CREATE DICTIONARY IF NOT EXISTS {{ .DB }}.ip_trie
(
  `cidr`         string,
  `latitude`     float64,
  `longitude`    float64,
  `country_code` string,
  `state`        string,
  `city`         string
)
PRIMARY KEY cidr
SOURCE(TIMEPLUS(
  STREAM   'geoip_lookup'
  USER     '{{ .Config.dict_user }}'
  PASSWORD '{{ .Config.dict_password }}'
))
LIFETIME(MIN 0 MAX 3600)
LAYOUT(IP_TRIE);
```

- [ ] **Step 9: Sanity-check filenames**

Run: `ls apps/geo-ip-lookup/ddl/`
Expected (sorted):
```
001_create_user.sql
002_grant_select.sql
003_dbip_city_ipv4.sql
004_load_dbip.sql
005_v_dbip_city_ipv4_with_cidr.sql
006_geoip_lookup.sql
007_populate_geoip.sql
008_ip_trie.sql
```

- [ ] **Step 10: Commit**

```bash
git add apps/geo-ip-lookup/ddl/
git commit -m "geo-ip-lookup: add 8 DDL files mirroring source geo.sql"
```

---

## Task 3: Generate the app icon (SVG → base64 data URI)

**Files:**
- Create (temporary): `/tmp/geo-ip-lookup-icon.svg`
- Capture the data URI string for embedding in `manifest.yaml` (Task 4)

The icon should follow the canonical Timeplus style from `skill/SKILL.md`: 48×48 viewBox, rounded square with pink→purple gradient, white symbol. Use a globe with a pin / target reticle to represent "IP → geo location."

- [ ] **Step 1: Write the SVG file**

Path: `/tmp/geo-ip-lookup-icon.svg`

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="48" y2="48" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#D53F8C"/>
      <stop offset="100%" stop-color="#9F2BC0"/>
    </linearGradient>
  </defs>
  <rect width="48" height="48" rx="11" fill="url(#bg)"/>
  <circle cx="22" cy="22" r="9" fill="none" stroke="white" stroke-width="1.5"/>
  <path d="M 13 22 L 31 22" stroke="white" stroke-width="1.2" fill="none" opacity="0.9"/>
  <path d="M 22 13 C 17 17, 17 27, 22 31 C 27 27, 27 17, 22 13 Z" stroke="white" stroke-width="1.2" fill="none" opacity="0.9"/>
  <path d="M 32 26 C 32 30, 28 35, 28 35 C 28 35, 24 30, 24 26 C 24 23.8, 25.8 22, 28 22 C 30.2 22, 32 23.8, 32 26 Z" fill="white"/>
  <circle cx="28" cy="26" r="1.6" fill="#9F2BC0"/>
</svg>
```

- [ ] **Step 2: Generate the base64 data URI**

Run:
```bash
echo "data:image/svg+xml;base64,$(base64 -i /tmp/geo-ip-lookup-icon.svg | tr -d '\n')"
```

Expected output: a single line beginning with `data:image/svg+xml;base64,PHN2ZyB...`. Copy this string for Task 4. Save it to a scratch file if the terminal will scroll away:

```bash
echo "data:image/svg+xml;base64,$(base64 -i /tmp/geo-ip-lookup-icon.svg | tr -d '\n')" > /tmp/geo-ip-lookup-icon-uri.txt
```

(No commit yet — the icon string lives in `manifest.yaml`, written in Task 4.)

---

## Task 4: Write manifest.yaml

**Files:**
- Create: `apps/geo-ip-lookup/manifest.yaml`

- [ ] **Step 1: Write the manifest**

Replace `<ICON_DATA_URI>` with the string from Task 3 Step 2.

```yaml
package_format_version: 1
id: io.timeplus.geo-ip-lookup
name: Geo IP Lookup
version: 0.1.0
author: Timeplus
description: >
  Interactive IPv4 to city geo lookup powered by the dbip IPv4 dataset.
  Loads ~3M ranges into an IP_TRIE dictionary for sub-millisecond
  dict_get lookups. Includes a dashboard with text input, lookup
  result table, and map.
icon: "<ICON_DATA_URI>"
db_name: geo
categories:
  - observability
  - utilities
  - demo

config:
  - key: dict_user
    type: string
    required: false
    default: "geolookup"
    description: >
      Timeplus user that the IP_TRIE dictionary connects as to read its
      source stream. The app creates this user at install via a
      type:system resource. Override only if you need a different name.
  - key: dict_password
    type: string
    required: false
    secret: true
    default: "demo123"
    description: Password for dict_user. Used in both CREATE USER and the dictionary source.

resources:
  - file: ddl/001_create_user.sql
    type: system
    name: create_geolookup_user
  - file: ddl/002_grant_select.sql
    type: system
    name: grant_select_geolookup
  - file: ddl/003_dbip_city_ipv4.sql
    type: mutable_stream
    name: dbip_city_ipv4
  - file: ddl/004_load_dbip.sql
    type: system
    name: load_dbip
  - file: ddl/005_v_dbip_city_ipv4_with_cidr.sql
    type: view
    name: v_dbip_city_ipv4_with_cidr
  - file: ddl/006_geoip_lookup.sql
    type: mutable_stream
    name: geoip_lookup
  - file: ddl/007_populate_geoip.sql
    type: system
    name: populate_geoip
  - file: ddl/008_ip_trie.sql
    type: dictionary
    name: ip_trie

dashboards:
  - file: dashboards/main.json
    name: Geo IP Lookup
    description: Type an IP, see the city.
```

- [ ] **Step 2: Validate the YAML parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('apps/geo-ip-lookup/manifest.yaml'))"`
Expected: no output, exit 0. Any error here means the icon line or a quoted field is malformed.

- [ ] **Step 3: Confirm no unquoted `#` in name/description fields**

Run: `grep -nE "^\s*(name|description):" apps/geo-ip-lookup/manifest.yaml | grep -v ">" | grep "#"`
Expected: no output. (Memory `feedback_manifest_yaml_hash` — YAML treats `#` as comment start in unquoted scalars.)

- [ ] **Step 4: Commit**

```bash
git add apps/geo-ip-lookup/manifest.yaml
git commit -m "geo-ip-lookup: add manifest.yaml with 8 resources and 2 config keys"
```

---

## Task 5: Write the dashboard JSON

**Files:**
- Create: `apps/geo-ip-lookup/dashboards/main.json`

Five panels on a 12-column grid:

| # | id | Panel | Type | Position |
|---|---|---|---|---|
| 1 | `geo-md-header` | About | `md` | x=0 y=0 w=12 h=2 |
| 2 | `geo-input-ip` | IP address | `text_input` (control) | x=0 y=2 w=12 h=1 |
| 3 | `geo-result-table` | Lookup result | `table` | x=0 y=3 w=12 h=4 |
| 4 | `geo-map` | Location | `geo` | x=0 y=7 w=12 h=8 |
| 5a | `geo-stats-count` | Loaded rows | `singleValue` | x=0 y=15 w=6 h=3 |
| 5b | `geo-stats-time` | Last update | `singleValue` | x=6 y=15 w=6 h=3 |

- [ ] **Step 1: Write `dashboards/main.json`**

```json
[
  {
    "id": "geo-md-header",
    "title": "About",
    "description": "",
    "position": { "x": 0, "y": 0, "w": 12, "h": 2, "nextX": 12, "nextY": 1 },
    "viz_type": "chart",
    "viz_content": "SELECT 1",
    "viz_config": {
      "chartType": "md",
      "config": {
        "content": "# Geo IP Lookup\n\nType any IPv4 address in the input below to look it up in the dbip city-IPv4 dataset. The lookup uses an `IP_TRIE` dictionary for sub-millisecond response.\n\nTry: `140.82.112.4` (GitHub), `8.8.8.8` (Google DNS), `1.1.1.1` (Cloudflare DNS), `52.94.236.248` (AWS).\n\n_First lookup after install can take ~30s while the trie loads ~3M ranges; subsequent lookups are instant._",
        "updateMode": "all",
        "updateKey": ""
      }
    }
  },
  {
    "id": "geo-input-ip",
    "title": "IP address",
    "description": "",
    "position": { "x": 0, "y": 2, "w": 12, "h": 1, "nextX": 12, "nextY": 3 },
    "viz_type": "control",
    "viz_content": "",
    "viz_config": {
      "controlType": "text_input",
      "config": {
        "variable": "ip_address",
        "defaultValue": "140.82.112.4",
        "placeholder": "Enter an IPv4 address"
      }
    }
  },
  {
    "id": "geo-result-table",
    "title": "Lookup result",
    "description": "",
    "position": { "x": 0, "y": 3, "w": 12, "h": 4, "nextX": 12, "nextY": 7 },
    "viz_type": "chart",
    "viz_content": "SELECT dict_get('[[ .DB ]].ip_trie', 'country_code', to_ipv4('{{filter_ip_address}}')) AS country, dict_get('[[ .DB ]].ip_trie', 'state', to_ipv4('{{filter_ip_address}}')) AS state, dict_get('[[ .DB ]].ip_trie', 'city', to_ipv4('{{filter_ip_address}}')) AS city, dict_get('[[ .DB ]].ip_trie', 'latitude', to_ipv4('{{filter_ip_address}}')) AS latitude, dict_get('[[ .DB ]].ip_trie', 'longitude', to_ipv4('{{filter_ip_address}}')) AS longitude",
    "viz_config": {
      "chartType": "table",
      "config": {
        "updateMode": "all",
        "updateKey": ""
      }
    }
  },
  {
    "id": "geo-map",
    "title": "Location",
    "description": "",
    "position": { "x": 0, "y": 7, "w": 12, "h": 8, "nextX": 12, "nextY": 15 },
    "viz_type": "chart",
    "viz_content": "SELECT '{{filter_ip_address}}' AS ip, dict_get('[[ .DB ]].ip_trie', 'latitude', to_ipv4('{{filter_ip_address}}')) AS latitude, dict_get('[[ .DB ]].ip_trie', 'longitude', to_ipv4('{{filter_ip_address}}')) AS longitude, dict_get('[[ .DB ]].ip_trie', 'city', to_ipv4('{{filter_ip_address}}')) AS city, dict_get('[[ .DB ]].ip_trie', 'country_code', to_ipv4('{{filter_ip_address}}')) AS country",
    "viz_config": {
      "chartType": "geo",
      "config": {
        "longitude": "longitude",
        "latitude": "latitude",
        "color": "ip",
        "updateMode": "all",
        "updateKey": "",
        "visibleColumns": ["ip", "city", "country"],
        "opacity": 0.9,
        "zoom": 4,
        "center": [20, 0],
        "size": { "key": "", "value": 10, "range": [6, 14] }
      }
    }
  },
  {
    "id": "geo-stats-count",
    "title": "Loaded ranges",
    "description": "",
    "position": { "x": 0, "y": 15, "w": 6, "h": 3, "nextX": 6, "nextY": 18 },
    "viz_type": "chart",
    "viz_content": "SELECT element_count FROM system.dictionaries WHERE database = '[[ .DB ]]' AND name = 'ip_trie'",
    "viz_config": {
      "chartType": "singleValue",
      "config": {
        "value": "element_count",
        "color": "blue",
        "sparkline": false,
        "delta": false,
        "fontSize": 56,
        "fractionDigits": 0,
        "unit": { "position": "right", "value": " CIDRs" },
        "updateMode": "all"
      }
    }
  },
  {
    "id": "geo-stats-time",
    "title": "Dictionary status",
    "description": "",
    "position": { "x": 6, "y": 15, "w": 6, "h": 3, "nextX": 12, "nextY": 18 },
    "viz_type": "chart",
    "viz_content": "SELECT status FROM system.dictionaries WHERE database = '[[ .DB ]]' AND name = 'ip_trie'",
    "viz_config": {
      "chartType": "singleValue",
      "config": {
        "value": "status",
        "color": "green",
        "sparkline": false,
        "delta": false,
        "fontSize": 32,
        "fractionDigits": 0,
        "unit": { "position": "right", "value": "" },
        "updateMode": "all"
      }
    }
  }
]
```

- [ ] **Step 2: Validate JSON parses**

Run: `python3 -c "import json; json.load(open('apps/geo-ip-lookup/dashboards/main.json'))"`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add apps/geo-ip-lookup/dashboards/main.json
git commit -m "geo-ip-lookup: add dashboard with IP input, result table, map, stats"
```

---

## Task 6: Build, install, and verify end-to-end

This task assumes a running local Timeplus at `http://localhost:8000`. If unavailable, stop after Step 1 (build) and resume Steps 2+ when Timeplus is up.

- [ ] **Step 1: Build the `.tpapp` package**

Run: `make build APP=geo-ip-lookup`
Expected: `apps/geo-ip-lookup/geo-ip-lookup.tpapp` produced.

Verify zip contents:
```bash
unzip -l apps/geo-ip-lookup/geo-ip-lookup.tpapp
```
Expected entries:
```
manifest.yaml
ddl/001_create_user.sql … ddl/008_ip_trie.sql   (8 files)
dashboards/main.json
```

- [ ] **Step 2: Install the app**

Run: `make install APP=geo-ip-lookup`
Expected: HTTP 200 with `"status": "installed"` (or equivalent success body). Install blocks ≈30–60s while the dbip CSV downloads (≈40 MB compressed) and `INSERT`s run.

Common failure modes:
- `provision create_geolookup_user: Not enough privileges` — installer lacks `CREATE USER` privilege. The user must run Timeplus as a privileged account or pre-create `geolookup`. Document and abort.
- `provision load_dbip: Cannot resolve host` — no network access to S3. Retry with network connectivity.
- `provision <name>: …` — the failing resource name pinpoints the file; fix and re-run.

- [ ] **Step 3: Verify the geolookup user exists**

In the Timeplus SQL console:
```sql
SELECT name FROM system.users WHERE name = 'geolookup';
```
Expected: one row.

- [ ] **Step 4: Verify dbip_city_ipv4 loaded**

```sql
SELECT count() FROM table(geo.dbip_city_ipv4);
```
Expected: a few million (≈3M, exact depends on dbip snapshot).

- [ ] **Step 5: Verify the CIDR view returns rows**

```sql
SELECT cidr, country_code, state1, city, latitude, longitude
FROM geo.v_dbip_city_ipv4_with_cidr
LIMIT 5;
```
Expected: 5 rows with non-empty `cidr` like `1.0.0.0/24`.

- [ ] **Step 6: Verify geoip_lookup populated**

```sql
SELECT count() FROM table(geo.geoip_lookup);
```
Expected: same magnitude as `dbip_city_ipv4` (≈3M).

- [ ] **Step 7: Smoke-test the dictionary lookup**

```sql
SELECT dict_get('geo.ip_trie', ('country_code','latitude','longitude','city'),
                to_ipv4('140.82.112.4'));
```
Expected: tuple like `('US', 37.7..., -122.4..., 'San Francisco')` (GitHub's IP).

First call takes ≈30–60s while the dictionary builds the trie. Re-run to confirm sub-millisecond response.

- [ ] **Step 8: Verify dictionary status**

```sql
SELECT name, element_count, status FROM system.dictionaries
WHERE database = 'geo' AND name = 'ip_trie';
```
Expected: `element_count` ≈ 3M, `status = 'LOADED'`.

- [ ] **Step 9: Open the dashboard in the Timeplus UI**

Navigate to `http://localhost:8000/default/dashboards` and open "Geo IP Lookup".

Verify each panel:
1. **About** — markdown renders, sample IPs listed.
2. **IP address** — text input shows `140.82.112.4` as default.
3. **Lookup result** — one-row table: `country = "US"`, `city = "San Francisco"` (or nearby), `latitude` ≈ 37.7, `longitude` ≈ -122.4.
4. **Location** — map drops a pin in the SF Bay area; tooltip shows the IP, city, country.
5. **Loaded ranges** — ≈3M.
6. **Dictionary status** — `LOADED`.

- [ ] **Step 10: Test interactivity**

Change the text input to each of these and verify both the table and map update:

| IP | Expected city | Expected country |
|---|---|---|
| `8.8.8.8` | Mountain View (or similar) | US |
| `1.1.1.1` | Brisbane or Los Angeles (Cloudflare anycast — any plausible result is fine) | US / AU |
| `203.0.113.1` | empty / `""` (TEST-NET-3, reserved range) | empty |

The third case verifies fallback behavior when the IP isn't in the dataset.

- [ ] **Step 11: Check for UI round-trip damage to the dashboard**

Per memory `feedback_dashboard_ui_renders_templates`, UI edits can replace `[[ ]]` Sprig expressions with rendered values. Run:
```bash
git diff HEAD apps/geo-ip-lookup/dashboards/main.json
```
Expected: no diff (you didn't edit via the UI). If a diff shows up, restore any lost `[[ .DB ]]` expressions before continuing.

(No commit in this task — verification only.)

---

## Task 7: Idempotency check — install twice in a row

- [ ] **Step 1: Reinstall the app without changes**

Run: `make install APP=geo-ip-lookup`
Expected: HTTP 200 / `installed`. No "already exists" errors on any resource.

- [ ] **Step 2: Verify the user count didn't grow**

```sql
SELECT count() FROM system.users WHERE name = 'geolookup';
```
Expected: 1.

- [ ] **Step 3: Verify the dictionary still works**

```sql
SELECT dict_get('geo.ip_trie', 'city', to_ipv4('140.82.112.4'));
```
Expected: same San Francisco result.

(No commit — verification only.)

---

## Task 8: Register in the root Makefile

**Files:**
- Modify: `Makefile` (repo root)

- [ ] **Step 1: Add `geo-ip-lookup` to the `APPS` list**

Open `Makefile` and find the line:

```makefile
APPS        := market-data github cep game-feature-pipeline hacker-news invest-insights cisco-asa-ddos bluesky aws-cost taxi-fleet
```

Append `geo-ip-lookup`:

```makefile
APPS        := market-data github cep game-feature-pipeline hacker-news invest-insights cisco-asa-ddos bluesky aws-cost taxi-fleet geo-ip-lookup
```

- [ ] **Step 2: Verify `build-all` includes the new app**

Run: `make -n build-all | grep geo-ip-lookup`
Expected: at least one line referencing `apps/geo-ip-lookup`.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "geo-ip-lookup: register in root Makefile APPS list"
```

---

## Task 9: Cleanup and final review

- [ ] **Step 1: Remove the built artifact from git tracking (if accidentally committed)**

Run: `git ls-files | grep geo-ip-lookup.tpapp`
Expected: no output. If the `.tpapp` was committed, remove it:

```bash
git rm --cached apps/geo-ip-lookup/geo-ip-lookup.tpapp
git commit -m "geo-ip-lookup: untrack built .tpapp artifact"
```

Confirm the parent `.gitignore` (if any) already ignores `*.tpapp`:
```bash
grep -n tpapp .gitignore
```
If not, add it:
```bash
echo "*.tpapp" >> .gitignore
git add .gitignore
git commit -m "ignore built .tpapp artifacts"
```

- [ ] **Step 2: Final tree check**

Run: `find apps/geo-ip-lookup -type f | sort`
Expected exactly these tracked files:
```
apps/geo-ip-lookup/Makefile
apps/geo-ip-lookup/dashboards/main.json
apps/geo-ip-lookup/ddl/001_create_user.sql
apps/geo-ip-lookup/ddl/002_grant_select.sql
apps/geo-ip-lookup/ddl/003_dbip_city_ipv4.sql
apps/geo-ip-lookup/ddl/004_load_dbip.sql
apps/geo-ip-lookup/ddl/005_v_dbip_city_ipv4_with_cidr.sql
apps/geo-ip-lookup/ddl/006_geoip_lookup.sql
apps/geo-ip-lookup/ddl/007_populate_geoip.sql
apps/geo-ip-lookup/ddl/008_ip_trie.sql
apps/geo-ip-lookup/manifest.yaml
```
Plus possibly `apps/geo-ip-lookup/geo-ip-lookup.tpapp` (the build output — should be ignored).

- [ ] **Step 3: Show recent commits**

Run: `git log --oneline -10`
Expected: the 5 commits from this plan (scaffold, DDL, manifest, dashboard, root Makefile).

- [ ] **Step 4: Push the branch**

The user will push manually. Don't `git push` without their request.

---

## Definition of Done

- All files in the "Final tree check" exist and are committed.
- `make install APP=geo-ip-lookup` succeeds against a local Timeplus.
- Dashboard renders all 5 panels; changing the IP input updates the result table and map.
- Reinstall is a no-op (no "already exists" or duplicate-row errors).
- Root Makefile lists `geo-ip-lookup` in the `APPS` variable.
