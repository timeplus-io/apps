# geo-ip-lookup — design

A Timeplus demo app that loads the [dbip](https://db-ip.com/db/download/ip-to-city-lite)
IPv4 → city dataset into an `IP_TRIE` dictionary and exposes an interactive
dashboard where the user types an IP and sees the resolved country/state/city/
lat/lon — both as a row and on a map.

Source material: `/Users/gangtao/Code/timeplus/demos/cases/o11y/geo_look_ups/geo.sql`.

## Goals

- Package the dbip city-IPv4 dataset and an `IP_TRIE` dictionary as a one-click `.tpapp`.
- Demonstrate `dict_get('geo.ip_trie', cols, to_ipv4(...))` for sub-millisecond IP→geo lookups.
- Provide a dashboard that takes a user-supplied IP and renders the result on a map and in a table.
- Keep the install minimal: 2 DDL files, no Python, no streaming source.

## Non-goals

- Periodic refresh of the dbip data. The dataset is treated as a one-time load; users who want a refresh can `SYSTEM RELOAD DICTIONARY geo.ip_trie` manually.
- IPv6 lookups. The dbip IPv4 dataset only.
- Bulk-enrichment over a live stream. (A separate app or external query can `JOIN` the dictionary; this app just ships the dictionary.)
- User/role provisioning. The dictionary's `SOURCE(TIMEPLUS(...))` requires a user with `SELECT` on the source view; we expose `dict_user` / `dict_password` as config and default to `default`/`""` (works on local Timeplus open-source). Production users must override.

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

The dataset is ~3M rows. Each lookup needs a single CIDR per row; the source's CIDR-derivation formula is preserved verbatim in the view.

## Architecture

```
url('s3://.../dbip-city-ipv4.csv.gz')        external CSV (≈3M rows)
   │
   │  view: re-runs the URL fetch on each read,
   │        derives CIDR from (ip_range_start, ip_range_end)
   ▼
geo.v_geoip               view (no storage)
   │
   │  dictionary source: TIMEPLUS source reads from the view once
   │  at first dict_get; LIFETIME(MIN 0 MAX 0) disables refresh
   ▼
geo.ip_trie               DICTIONARY (LAYOUT IP_TRIE)
   │
   ▼
dict_get('geo.ip_trie',
         ('country_code','state','city','latitude','longitude'),
         to_ipv4('140.82.112.4'))
```

Why a view (not a mutable_stream backed by a one-shot task):
- `.tpapp` install supports only `CREATE …` resources. `INSERT INTO … SELECT FROM url(…)` is not a resource type.
- A `task` schedules INSERTs but fires only at the interval boundary, so the first run is delayed by the interval. Recurring fires also contradict the "one-time" requirement.
- A `view` over `url(…)` has no storage, and the dictionary's first `LOAD` from it triggers the URL fetch + trie build once. `LIFETIME(MIN 0 MAX 0)` pins the dictionary in memory afterwards.

### Verification fallback

The dictionary syntax `SOURCE(TIMEPLUS(STREAM '<name>' …))` is documented for streams. If Timeplus rejects a view name in the `STREAM` slot at install time, the fallback (in priority order) is:

1. Switch the source to a `CLICKHOUSE` layout: `SOURCE(CLICKHOUSE(HOST 'localhost' PORT 8463 USER '…' PASSWORD '…' DB 'geo' TABLE 'v_geoip'))` — equivalent to the TIMEPLUS source but uses the generic ClickHouse-compatible interface.
2. If neither accepts a view, materialize the derived data into a `mutable_stream` populated by a `task` with `SCHEDULE INTERVAL 365 DAY`. The mutable stream's PK on `cidr` keeps repeated runs idempotent; the long interval makes the periodic re-fetch effectively never fire for demo lifetimes.

The implementation plan will install and probe option 1 first; the fallback is only taken if it fails.

## Package layout

```
apps/geo-ip-lookup/
├── Makefile
├── manifest.yaml
├── ddl/
│   ├── 001_v_geoip.sql
│   └── 002_ip_trie.sql
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
  Interactive IPv4 → city geo lookup powered by the dbip IPv4 dataset.
  Loads ≈3M ranges into an IP_TRIE dictionary for sub-millisecond
  dict_get lookups. Includes a dashboard with text input, lookup
  result table, and map.
icon: "data:image/svg+xml;base64,<TBD-during-impl>"
db_name: geo
categories:
  - observability
  - utilities
  - demo

config:
  - key: dict_user
    type: string
    required: false
    default: "default"
    description: >
      Timeplus user the IP_TRIE dictionary connects as to read its
      source view. Must have SELECT on geo.v_geoip. Defaults to
      "default" which works on local open-source Timeplus.
  - key: dict_password
    type: string
    required: false
    secret: true
    default: ""
    description: Password for dict_user. Defaults to empty.

resources:
  - file: ddl/001_v_geoip.sql
    type: view
    name: v_geoip
  - file: ddl/002_ip_trie.sql
    type: dictionary
    name: ip_trie

dashboards:
  - file: dashboards/main.json
    name: Geo IP Lookup
    description: Type an IP, see the city.
```

## DDL

### 001_v_geoip.sql

```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_geoip
AS
WITH
  bit_xor(ip_range_start, ip_range_end)                    AS xor,
  if(xor != 0, ceil(log2(xor)), 0)                         AS unmatched,
  32 - unmatched                                           AS cidr_suffix,
  cast(bit_and(bit_not(pow(2, unmatched) - 1),
               ip_range_start),
       'uint32')                                           AS cidr_int,
  ipv4_num_to_string(cidr_int)                             AS cidr_address
SELECT
  concat(cidr_address, '/', to_string(cidr_suffix))        AS cidr,
  latitude,
  longitude,
  coalesce(country_code, '')                               AS country_code,
  coalesce(state1, '')                                     AS state,
  coalesce(city, '')                                       AS city
FROM url(
  'https://tp-solutions.s3.us-west-2.amazonaws.com/ip-location-db/dbip-city-ipv4.csv.gz',
  'CSV',
  'ip_range_start ipv4, ip_range_end ipv4, country_code nullable(string), state1 nullable(string), state2 nullable(string), city nullable(string), postcode nullable(string), latitude float64, longitude float64, timezone nullable(string)'
);
```

Notes:
- The view contains the CIDR derivation that lived in `v_dbip_city_ipv4_with_cidr` in the source — fused with the URL read so there is no intermediate stream.
- `coalesce(... '')` strips `nullable()` from the string columns because `IP_TRIE` dictionary attributes must be non-nullable.
- The view re-fetches the CSV on every read; the dictionary's first load triggers that and caches the trie.

### 002_ip_trie.sql

```sql
CREATE DICTIONARY IF NOT EXISTS {{ .DB }}.ip_trie
(
  cidr          string,
  latitude      float64,
  longitude     float64,
  country_code  string,
  state         string,
  city          string
)
PRIMARY KEY cidr
SOURCE(TIMEPLUS(
  STREAM 'v_geoip'
  USER '{{ .Config.dict_user }}'
  PASSWORD '{{ .Config.dict_password }}'
))
LIFETIME(MIN 0 MAX 0)
LAYOUT(IP_TRIE);
```

Notes:
- `LIFETIME(MIN 0 MAX 0)` = load once, never auto-refresh. Matches the "no refresh" requirement.
- Operators who do want a refresh can run `SYSTEM RELOAD DICTIONARY geo.ip_trie` ad-hoc.
- If the view-as-source approach fails at install (see "Verification fallback" above), this file is what changes — same dictionary contract, different `SOURCE(...)` clause.

## Dashboard (`dashboards/main.json`)

A single-column 12-grid layout with five panels:

| # | Panel | Type | Size | Purpose |
|---|---|---|---|---|
| 1 | About | `md` | full-width, 2 rows | What the app does, "first lookup may take a minute while the trie builds", link to dbip |
| 2 | IP address | `text_input` (control) | full-width, 1 row | Bound variable `ip_address`, default `140.82.112.4` (a GitHub IP) |
| 3 | Lookup result | `table` | full-width, 4 rows | Single-row `dict_get` result with columns country_code, state, city, latitude, longitude |
| 4 | Location | `geo` | full-width, 8 rows | Map with a single point at the resolved (lat, lon); zoom set to ≈5 |
| 5 | Dictionary status | `singleValue` ×2 in a row | half-width each, 3 rows | Loaded element count + last-update time from `system.dictionaries` |

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

**Location (`geo`):** same select with `latitude`/`longitude` columns; `center` set per the lookup result (Vistral's `[lat, lon]` ordering — see memory `feedback_geo_center_lat_lon`).

**Dictionary status (`singleValue`):**
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

Per memory `feedback_md_panel_requires_query`, the markdown panel uses `viz_content: "SELECT 1"` as a no-op stub. Per memory `feedback_dashboard_ui_renders_templates`, no Sprig expressions are needed in this dashboard, so UI round-trip is safe.

## Testing & verification

After `make install`:

1. Wait for the dictionary to load — first `dict_get` against `geo.ip_trie` takes ≈30–60s while the CSV downloads and the trie builds. Subsequent calls are sub-ms.
2. Confirm row count in the dictionary:
   ```sql
   SELECT element_count FROM system.dictionaries
   WHERE database = 'geo' AND name = 'ip_trie';
   ```
   Expected: a few million.
3. Smoke-test the documented example:
   ```sql
   SELECT dict_get('geo.ip_trie', ('country_code','latitude','longitude','city'),
                   to_ipv4('140.82.112.4'));
   ```
   Expected: a US, San Francisco-ish row for GitHub.
4. Render the dashboard with the default IP — table must populate, map must drop a pin in San Francisco.
5. Change the IP via the text input — both table and map must update.
6. Reinstall the app (`make install` again) — every `CREATE … IF NOT EXISTS` must be a no-op. No "already exists" errors.

## Known caveats

- **First lookup is slow.** The dictionary is lazily loaded; the first query triggers a ~3M-row CSV pull from S3. Documented in the dashboard's markdown header.
- **`default`/empty password defaults.** Works on local open-source Timeplus; Timeplus Cloud users must override `dict_user`/`dict_password` at install time.
- **`null_if` not `nullif`.** Per memory `feedback_nullif_not_alias`, no occurrences in this app's SQL — `coalesce` is used instead.
- **YAML `#` rule.** No `#` in any manifest name/description (memory `feedback_manifest_yaml_hash`).
- **`geo` panel `center` is `[lat, lon]`.** Memory `feedback_geo_center_lat_lon` confirmed.
