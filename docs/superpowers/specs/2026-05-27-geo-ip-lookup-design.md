# geo-ip-lookup — design

A Timeplus demo app that loads the [dbip](https://db-ip.com/db/download/ip-to-city-lite)
IPv4 → city dataset into an `IP_TRIE` dictionary and exposes an interactive
dashboard where the user types an IP and sees the resolved country/state/city/
lat/lon — both as a row and on a map.

Source material: `/Users/gangtao/Code/timeplus/demos/cases/o11y/geo_look_ups/geo.sql`.

## Goals

- Package the entire pipeline from the source `geo.sql` 1:1 — every statement
  becomes its own resource in `manifest.yaml`, one SQL statement per file.
- Demonstrate `dict_get('geo.ip_trie', cols, to_ipv4(...))` for sub-millisecond IP→geo lookups.
- Provide a dashboard that takes a user-supplied IP and renders the result on a map and in a table.
- One-click install — admin SQL (`CREATE USER` / `GRANT` / `INSERT`) runs at install via `type: system` resources.

## Non-goals

- Periodic refresh of the dbip data. Both `INSERT`s are one-shot `type: system` resources that run once at install. Operators wanting a refresh can `SYSTEM RELOAD DICTIONARY geo.ip_trie` or re-install the app.
- IPv6 lookups. The dbip IPv4 dataset only.
- Bulk-enrichment over a live stream. (A separate app or external query can `JOIN` the dictionary; this app just ships the dictionary.)

## Data source

`https://tp-solutions.s3.us-west-2.amazonaws.com/ip-location-db/dbip-city-ipv4.csv.gz`

CSV schema (matches the source `geo.sql`):

| Column | Type |
|---|---|
| `ip_range_start` | `ipv4` |
| `ip_range_end` | `ipv4` |
| `country_code` | `nullable(string)` |
| `state1` | `nullable(string)` |
| `state2` | `nullable(string)` |
| `city` | `nullable(string)` |
| `postcode` | `nullable(string)` |
| `latitude` | `float64` |
| `longitude` | `float64` |
| `timezone` | `nullable(string)` |

The dataset is ≈3M rows.

## Architecture

End-state mirrors the source SQL exactly:

```
CSV (dbip-city-ipv4.csv.gz, ≈3M rows, hosted on S3)
   │
   │  INSERT INTO dbip_city_ipv4 (type: system) at install time
   ▼
geo.dbip_city_ipv4                    mutable_stream, PK (ip_range_start, ip_range_end)
   │
   │  view re-runs over the stream, derives CIDR
   ▼
geo.v_dbip_city_ipv4_with_cidr        view (no storage)
   │
   │  INSERT INTO geoip_lookup (type: system) at install time
   ▼
geo.geoip_lookup                      mutable_stream, PK cidr
   │
   │  dictionary source: TIMEPLUS source over geoip_lookup
   ▼
geo.ip_trie                           DICTIONARY (LAYOUT IP_TRIE), LIFETIME(MIN 0 MAX 3600)
   │
   ▼
dict_get('geo.ip_trie', cols, to_ipv4('140.82.112.4'))
```

### About `type: system`

Three existing apps in this repo (`alpha-101`, `cisco-asa-ddos`, `invest-insights`)
use `type: system` for free-form SQL that doesn't fit a `CREATE …` resource type
— `INSERT`s, `SYSTEM PAUSE …`, seed data. The installer executes the file
as-is and rolls back on failure. We use it for the four non-`CREATE` statements
in `geo.sql`:

| Source statement | Resource type |
|---|---|
| `CREATE USER geolookup IDENTIFIED BY 'demo123'` | `system` |
| `GRANT SELECT ON geo.* TO geolookup` | `system` |
| `INSERT INTO dbip_city_ipv4 … FROM url(…)` | `system` |
| `INSERT INTO geoip_lookup … FROM v_…` | `system` |

This preserves the source pipeline statement-for-statement and keeps the install one-click.

## Package layout

```
apps/geo-ip-lookup/
├── Makefile
├── manifest.yaml
├── ddl/
│   ├── 001_create_user.sql                (system  — CREATE USER)
│   ├── 002_grant_select.sql               (system  — GRANT SELECT)
│   ├── 003_dbip_city_ipv4.sql             (mutable_stream)
│   ├── 004_load_dbip.sql                  (system  — INSERT FROM url)
│   ├── 005_v_dbip_city_ipv4_with_cidr.sql (view    — CIDR derivation)
│   ├── 006_geoip_lookup.sql               (mutable_stream)
│   ├── 007_populate_geoip.sql             (system  — INSERT from view)
│   └── 008_ip_trie.sql                    (dictionary)
└── dashboards/
    └── main.json
```

## manifest.yaml

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
icon: "data:image/svg+xml;base64,<generated-during-impl>"
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

## DDL — one statement per file

Every file is templated with `{{ .DB }}` (resolves to `geo`) and `{{ .Config.dict_user }}` / `{{ .Config.dict_password }}` where applicable.

### 001_create_user.sql
```sql
CREATE USER IF NOT EXISTS {{ .Config.dict_user }} IDENTIFIED BY '{{ .Config.dict_password }}';
```

### 002_grant_select.sql
```sql
GRANT SELECT ON {{ .DB }}.* TO {{ .Config.dict_user }};
```

### 003_dbip_city_ipv4.sql
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

Notes:
- `ip_range_start`/`ip_range_end` are typed `ipv4` directly (the source `INSERT` converts string CSV values with `to_ipv4(...)` into matching `ipv4` columns). Stream is mutable so re-install upserts are idempotent.

### 004_load_dbip.sql
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

Notes:
- Re-running on upgrade is safe — mutable stream PK on `(ip_range_start, ip_range_end)` upserts identical rows.
- The CSV fetch is ≈40 MB compressed, ≈3M rows. Install will block for the download + insert duration.

### 005_v_dbip_city_ipv4_with_cidr.sql
```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_dbip_city_ipv4_with_cidr
AS
WITH
  ip_range_start,
  ip_range_end,
  bit_xor(to_ipv4(ip_range_start), to_ipv4(ip_range_end))         AS xor,
  if(xor != 0, ceil(log2(xor)), 0)                                AS unmatched,
  32 - unmatched                                                  AS cidr_suffix,
  cast(bit_and(bit_not(pow(2, unmatched) - 1),
               to_ipv4(ip_range_start)), 'uint32')                AS bitand,
  to_ipv4(ipv4_num_to_string(bitand))                             AS cidr_address
SELECT
  concat(to_string(cidr_address), '/', to_string(cidr_suffix))    AS cidr,
  to_ipv4(ip_range_start)                                         AS ip_range_start,
  to_ipv4(ip_range_end)                                           AS ip_range_end,
  latitude,
  longitude,
  country_code,
  state1,
  city
FROM table({{ .DB }}.dbip_city_ipv4);
```

Notes:
- Verbatim from the source `geo.sql` definition of `v_dbip_city_ipv4_with_cidr` — only the database name is templated and `IF NOT EXISTS` is added for re-install safety.
- `table(...)` does a historical (one-shot) read of the mutable stream — required when the view feeds the next `INSERT` at install time.

### 006_geoip_lookup.sql
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

### 007_populate_geoip.sql
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

Notes:
- `coalesce(...,'')` strips `nullable()` so the dictionary attributes (non-nullable) work.
- Mutable stream PK on `cidr` makes re-runs idempotent upserts.

### 008_ip_trie.sql
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

Notes:
- Verbatim from source `geo.sql`; only DB / user / password are templated.
- `LIFETIME(MIN 0 MAX 3600)` matches the source — auto-reload at most once per hour. The INSERT only happens at install time via the `system` resource, so the dictionary's reload re-reads the same static rows from `geoip_lookup`.

## Dashboard (`dashboards/main.json`)

A single-column 12-grid layout with five panels:

| # | Panel | Type | Size | Purpose |
|---|---|---|---|---|
| 1 | About | `md` | full-width, 2 rows | What the app does, link to dbip, sample IPs to try |
| 2 | IP address | `text_input` (control) | full-width, 1 row | Bound variable `ip_address`, default `140.82.112.4` (GitHub IP) |
| 3 | Lookup result | `table` | full-width, 4 rows | Single-row `dict_get` result: country, state, city, lat, lon |
| 4 | Location | `geo` | full-width, 8 rows | Map with a single point at the resolved (lat, lon); zoom ≈ 5 |
| 5 | Dataset stats | `singleValue` × 2 | half-width each, 3 rows | Loaded element count + last-update time from `system.dictionaries` |

### Key dashboard queries

**Lookup result (`table`):**
```sql
SELECT
  dict_get('[[ .DB ]].ip_trie', 'country_code', to_ipv4('{{filter_ip_address}}')) AS country,
  dict_get('[[ .DB ]].ip_trie', 'state',        to_ipv4('{{filter_ip_address}}')) AS state,
  dict_get('[[ .DB ]].ip_trie', 'city',         to_ipv4('{{filter_ip_address}}')) AS city,
  dict_get('[[ .DB ]].ip_trie', 'latitude',     to_ipv4('{{filter_ip_address}}')) AS lat,
  dict_get('[[ .DB ]].ip_trie', 'longitude',    to_ipv4('{{filter_ip_address}}')) AS lon;
```

**Location (`geo`):** projects `latitude` / `longitude` from the same `dict_get`; `center` set to the result with Vistral's `[lat, lon]` ordering (memory `feedback_geo_center_lat_lon`).

**Dataset stats (`singleValue`):**
```sql
SELECT element_count
FROM system.dictionaries
WHERE database = '[[ .DB ]]' AND name = 'ip_trie';
```

```sql
SELECT to_string(last_successful_update_time)
FROM system.dictionaries
WHERE database = '[[ .DB ]]' AND name = 'ip_trie';
```

Per memory `feedback_md_panel_requires_query`, the markdown header uses `viz_content: "SELECT 1"` as a no-op stub.

## Testing & verification

After `make install` completes (install will block ≈30–60s while the dbip CSV downloads + INSERTs):

1. Confirm the user exists: `SELECT name FROM system.users WHERE name = 'geolookup';`
2. Confirm row counts:
   ```sql
   SELECT count() FROM table(geo.dbip_city_ipv4);   -- expect ≈3M
   SELECT count() FROM table(geo.geoip_lookup);     -- expect ≈3M
   SELECT element_count FROM system.dictionaries WHERE database='geo' AND name='ip_trie';
   ```
3. Smoke-test the documented example:
   ```sql
   SELECT dict_get('geo.ip_trie', ('country_code','latitude','longitude','city'),
                   to_ipv4('140.82.112.4'));
   ```
   Expected: US / San Francisco-ish row for GitHub.
4. Render the dashboard with the default IP — table populates, map drops a pin in San Francisco.
5. Change the IP via the text input — both table and map update.
6. Reinstall the app (`make install` again) — `CREATE … IF NOT EXISTS` is a no-op; `INSERT`s into mutable streams upsert idempotently; `CREATE USER IF NOT EXISTS` and `GRANT` re-apply cleanly. No errors.

## Known caveats

- **Install latency.** Install blocks for ≈30–60s while the dbip CSV downloads and inserts.
- **`populate_geoip` races `load_dbip` (partial data on first install).** `INSERT INTO geoip_lookup SELECT … FROM v_dbip_city_ipv4_with_cidr` (which reads `table(dbip_city_ipv4)`) is one-shot historical, but writes to `dbip_city_ipv4` propagate asynchronously. At install time only the rows visible at that moment land in `geoip_lookup` (≈1.17M of 3.15M observed). Some IPs (e.g. GitHub's `140.82.112.4`) return empty lookups until populate is re-run. **Workaround (documented in dashboard markdown):** after install completes, re-run the populate INSERT manually, then `SYSTEM RELOAD DICTIONARY geo.ip_trie`. The user accepted this defect (May 2026) rather than restructuring the pipeline.
- **Reinstall unsupported.** The `POST /apps/install` endpoint rejects a second install of the same app with `"database <db_name> already exists"` and silently un-registers the existing app record (orphaning all its resources in the underlying database). To re-deploy, drop the database manually and install fresh. The `IF NOT EXISTS` guards in DDL never get exercised at the database level.
- **Hardcoded password default.** `dict_password` defaults to `"demo123"` for demo convenience. Operators on shared/production clusters must override at install via `-F "config[dict_password]=…"` (memory `reference_tpapp_install_config`).
- **DCL behaviour.** `CREATE USER` and `GRANT` run via `type: system`. The installer must have CREATE USER and GRANT OPTION privileges; otherwise these two resources fail and the app rolls back.
- **`null_if` not `nullif`.** Per memory `feedback_nullif_not_alias`, no occurrences in this app's SQL — `coalesce` is used instead.
- **YAML `#` rule.** No `#` in any manifest name/description (memory `feedback_manifest_yaml_hash`).
- **`geo` panel `center` is `[lat, lon]`.** Memory `feedback_geo_center_lat_lon` confirmed.
