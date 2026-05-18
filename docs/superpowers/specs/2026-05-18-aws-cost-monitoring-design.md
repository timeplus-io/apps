# AWS Resource Usage & Cost Realtime Monitoring — Design

**Date:** 2026-05-18
**App id:** `io.timeplus.aws-cost`
**Directory:** `apps/aws-cost/`
**Package output:** `apps/aws-cost/aws-cost.tpapp`

## 1. Goal

A Timeplus app that continuously monitors AWS resource inventory across user-configured regions and services, joins live resource snapshots with current AWS pricing, and surfaces realtime spend — broken down by service, region, and **creator** — on a dashboard.

In scope for v1: EC2 instances, EBS volumes, S3 buckets, across one or more regions.

## 2. Architecture

```
python_packages: boto3
  ├── aws_resource_poller (external_stream, Python, mode='streaming')
  │     emits one row per resource per poll cycle, all regions × services
  │       └── mv_resource_inventory → aws_resources (append-only stream, 7d TTL)
  │
  └── aws_price_poller (external_stream, Python, mode='streaming')
        emits AWS Pricing API records (slow refresh)
          └── mv_prices → aws_prices (mutable_stream,
                                       PK=(service,region,resource_type,unit))

aws_resources  ⋈  aws_prices         (streaming JOIN: stream ⋈ mutable)
   └── v_resource_cost_now           per-resource hourly + monthly cost
        ├── v_cost_by_creator
        ├── v_cost_by_service_region
        ├── v_top_expensive
        └── mv_cost_1m → aws_cost_1m  1-minute total spend rate (30d TTL)
```

## 3. Resource poller

**External stream `aws_resource_poller`** — `type='python', mode='streaming'`.

```sql
CREATE EXTERNAL STREAM {{ .DB }}.aws_resource_poller (
  service        string,    -- 'ec2' | 'ebs' | 's3'
  region         string,
  resource_id    string,    -- i-…, vol-…, bucket name
  resource_type  string,    -- 'm5.large', 'gp3', 'STANDARD'
  state          string,    -- 'running', 'in-use', 'available', etc.
  size_units     float64,   -- 1.0 for instance-hour, GB for gb-month
  unit           string,    -- 'instance-hour' | 'gb-month'
  tags_json      string,    -- raw tags JSON
  creator        string,    -- resolved per logic below
  snapshot_ts    datetime64(3),
  raw_payload    string
) AS $$ ... $$
SETTINGS type='python', mode='streaming', read_function_name='poll_aws';
```

**Python loop** (single generator — Timeplus streaming functions run as one process):

```
config (from .Config):
  AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  regions, services, poll_interval_seconds

loop forever:
  for region in regions:
    if "ec2" in services: ec2.describe_instances → yield rows
    if "ebs" in services: ec2.describe_volumes   → yield rows
  if "s3"  in services:
    s3.list_buckets (global) + CloudWatch BucketSizeBytes
    (us-east-1, daily metric) → yield rows
  sleep(poll_interval_seconds)
```

**Per-region try/except** so one bad region does not stop the others.

**Size/unit normalization:**
- EC2 instances: `size_units=1.0`, `unit='instance-hour'`
- EBS volumes:   `size_units=<size_gb>`, `unit='gb-month'`
- S3 buckets:    `size_units=<bytes/1e9>`, `unit='gb-month'`, `resource_type=<storage class>`

### 3.1 Creator resolution

```python
def resolve_creator(resource_id, tags, region, cache, cloudtrail):
    # 1. Tag check (case-insensitive)
    for k in ("CreatedBy","Owner","creator","owner","created_by"):
        if k in tags: return tags[k]
    # 2. Cache hit
    if resource_id in cache: return cache[resource_id]
    # 3. CloudTrail LookupEvents — best-effort, swallow throttles
    try:
        evt = cloudtrail.lookup_events(
            LookupAttributes=[{"AttributeKey":"ResourceName","AttributeValue":resource_id}],
            MaxResults=1)
        creator = evt["Events"][0].get("Username","unknown")
    except Exception:
        creator = "unknown"
    cache[resource_id] = creator      # cache even "unknown"
    return creator
```

In-memory dict; grows with distinct resource_ids. Acceptable for thousands of resources; LRU cap can be added later if needed.

### 3.2 `aws_resources` append-only stream

```sql
CREATE STREAM {{ .DB }}.aws_resources (
  service, region, resource_id, resource_type, state,
  size_units float64, unit string, tags_json string,
  creator string, snapshot_ts datetime64(3)
) TTL to_datetime(snapshot_ts) + INTERVAL 7 DAY;
```

`mv_resource_inventory` SELECTs all columns (minus `raw_payload`) FROM `aws_resource_poller` INTO `aws_resources`.

## 4. Price poller

**External stream `aws_price_poller`** — same Python streaming pattern, slow loop.

```sql
CREATE EXTERNAL STREAM {{ .DB }}.aws_price_poller (
  service, region, resource_type, unit string,
  hourly_usd float64,
  effective_ts datetime64(3),
  raw_payload string
) AS $$ ... $$
SETTINGS type='python', mode='streaming', read_function_name='poll_prices';
```

**API notes:**
- AWS Pricing API endpoints only in `us-east-1` and `ap-south-1`. Client is pinned there regardless of monitored regions.
- Filter products with `TermType=OnDemand`, `tenancy=Shared`, OS=`Linux`, `preInstalledSw=NA`, `capacitystatus=Used`.
- Pricing API uses location names (`"US East (N. Virginia)"`) — Python keeps a built-in code↔location map.
- All prices normalized to **hourly USD**: monthly per-GB rates divided by 730.

**Loop:**

```
loop forever:
  for region in monitored_regions:
    if "ec2" in services:
      for instance_type in observed_instance_types_so_far:   # discovered set
        yield row("ec2", region, instance_type, "instance-hour", hourly_usd)
    if "ebs" in services:
      for vol_type in ("gp3","gp2","io2","st1","sc1"):
        yield row("ebs", region, vol_type, "gb-month", monthly/730.0)
    if "s3" in services:
      for tier in ("Standard","Standard-IA","Glacier"):
        yield row("s3", region, tier, "gb-month", monthly/730.0)
  sleep(price_refresh_hours * 3600)   # default 6h
```

EC2 instance types are fetched on demand: the poller maintains an in-memory set of (region, instance_type) it has seen, populated by sniffing `aws_resources` is not possible from inside a streaming function — instead, the poller iterates a curated whitelist of common families (`t3.*`, `m5.*`, `c5.*`, `r5.*`, `t4g.*`, `m6i.*`, `c6i.*`, `r6i.*`). Misses produce `NULL hourly_cost_usd` in the join, surfaced as a "missing price" indicator on the dashboard.

### 4.1 `aws_prices` mutable_stream

```sql
CREATE MUTABLE STREAM {{ .DB }}.aws_prices (
  service        string,
  region         string,
  resource_type  string,
  unit           string,
  hourly_usd     float64,
  effective_ts   datetime64(3),
  PRIMARY KEY (service, region, resource_type, unit)
);
```

`mv_prices` reads `aws_price_poller` and inserts into `aws_prices`; the mutable_stream upserts on PK.

## 5. Cost join + views

### 5.1 `v_resource_cost_now` — the spine

Streaming join between the append-only stream and the mutable_stream **directly** — no `table()` wrapper, because we want realtime join semantics (each new resource snapshot joins against the current price row for its key).

```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_resource_cost_now AS
SELECT
  r._tp_time                            AS ts,
  r.service, r.region, r.resource_id, r.resource_type, r.state,
  r.size_units, r.unit, r.creator, r.tags_json,
  p.hourly_usd                          AS unit_hourly_usd,
  r.size_units * p.hourly_usd           AS hourly_cost_usd,
  r.size_units * p.hourly_usd * 730     AS monthly_cost_usd
FROM {{ .DB }}.aws_resources AS r
LEFT JOIN {{ .DB }}.aws_prices AS p
  ON  r.service       = p.service
  AND r.region        = p.region
  AND r.resource_type = p.resource_type
  AND r.unit          = p.unit;
```

`LEFT JOIN` so a missing price still emits the resource with `NULL` cost. Downstream views filter `WHERE p.hourly_usd IS NOT NULL` when summing.

`table()` is reserved for future historical/batch views (daily roll-ups, ad-hoc retro queries).

### 5.2 Roll-up views

All filter `WHERE _tp_time > now() - 2m` so the dashboard sums **only the latest poll cycle**, not every snapshot in the 7-day retention window.

```sql
-- v_cost_by_creator
SELECT creator,
       sum(hourly_cost_usd)  AS hourly_usd,
       sum(monthly_cost_usd) AS monthly_usd,
       count()               AS resources
FROM {{ .DB }}.v_resource_cost_now
WHERE _tp_time > now() - 2m
  AND state IN ('running','in-use')
GROUP BY creator
EMIT ON UPDATE WITH DELAY 5s;

-- v_cost_by_service_region
SELECT service, region,
       sum(hourly_cost_usd) AS hourly_usd, count() AS resources
FROM {{ .DB }}.v_resource_cost_now
WHERE _tp_time > now() - 2m
GROUP BY service, region
EMIT ON UPDATE WITH DELAY 5s;

-- v_top_expensive
SELECT resource_id, service, region, resource_type, creator,
       hourly_cost_usd, monthly_cost_usd
FROM {{ .DB }}.v_resource_cost_now
WHERE _tp_time > now() - 2m
ORDER BY hourly_cost_usd DESC
LIMIT 20;
```

### 5.3 `aws_cost_1m` — total spend rate over time

```sql
CREATE STREAM {{ .DB }}.aws_cost_1m (
  time              datetime64(3),
  total_hourly_usd  float64,
  resource_count    uint32
) TTL to_datetime(time) + INTERVAL 30 DAY;

CREATE MATERIALIZED VIEW {{ .DB }}.mv_cost_1m INTO {{ .DB }}.aws_cost_1m AS
SELECT tumble_start(_tp_time, 1m) AS time,
       sum(hourly_cost_usd)       AS total_hourly_usd,
       count()                    AS resource_count
FROM {{ .DB }}.v_resource_cost_now
WHERE state IN ('running','in-use')
GROUP BY tumble(_tp_time, 1m);
```

## 6. Config (`manifest.yaml`)

```yaml
config:
  - key: aws_access_key_id
    type: string
    required: true
    secret: true
    description: AWS access key ID for the IAM principal used to poll resources.
  - key: aws_secret_access_key
    type: string
    required: true
    secret: true
    description: AWS secret access key.
  - key: regions
    type: list
    required: true
    default: '["us-east-1","us-west-2"]'
    description: AWS regions to monitor.
  - key: services
    type: multi_choice
    required: false
    default: '["ec2","ebs","s3"]'
    options: [ec2, ebs, s3]
    description: Which AWS services to monitor.
  - key: poll_interval_seconds
    type: integer
    required: false
    default: "60"
    description: How often to re-scan resources, in seconds.
  - key: price_refresh_hours
    type: integer
    required: false
    default: "6"
    description: How often to re-fetch the AWS Pricing API.

python_packages:
  - boto3>=1.34.0
```

Required IAM permissions (documented in the app description):
`ec2:DescribeInstances`, `ec2:DescribeVolumes`, `s3:ListAllMyBuckets`,
`cloudwatch:GetMetricStatistics`, `cloudtrail:LookupEvents`,
`pricing:GetProducts`.

## 7. Dashboard

`dashboards/main.json` — 12-column grid, 6 panels:

| Panel | Type | Source | Notes |
|---|---|---|---|
| Total spend rate (USD/hr) | `singleValue` | `aws_cost_1m` latest | Headline |
| Monthly projection | `singleValue` | latest × 730 | Sticker-shock |
| Hourly cost over time | `line` | `aws_cost_1m` | 30d retention |
| Cost by service × region | `bar` (stacked) | `v_cost_by_service_region` | EMIT ON UPDATE |
| Cost by creator | `bar` (horizontal) | `v_cost_by_creator` | Who's spending |
| Top 20 expensive resources | `table` | `v_top_expensive` | Drill-down |

```
┌──────────────┬──────────────┐
│ Total $/hr   │ Proj. $/mo   │   h=2
├──────────────┴──────────────┤
│ Hourly cost over time       │   h=4
├──────────────┬──────────────┤
│ Cost by svc× │ Cost by      │   h=4
│ region       │ creator      │
├──────────────┴──────────────┤
│ Top 20 expensive resources  │   h=6
└─────────────────────────────┘
```

## 8. File layout & resource order

```
apps/aws-cost/
├── Makefile
├── manifest.yaml
├── ddl/
│   ├── 001_aws_resource_poller.sql        external_stream
│   ├── 002_aws_resources.sql              stream
│   ├── 003_mv_resource_inventory.sql      materialized_view
│   ├── 004_aws_price_poller.sql           external_stream
│   ├── 005_aws_prices.sql                 mutable_stream
│   ├── 006_mv_prices.sql                  materialized_view
│   ├── 007_v_resource_cost_now.sql        view
│   ├── 008_v_cost_by_creator.sql          view
│   ├── 009_v_cost_by_service_region.sql   view
│   ├── 010_v_top_expensive.sql            view
│   ├── 011_aws_cost_1m.sql                stream
│   └── 012_mv_cost_1m.sql                 materialized_view
└── dashboards/
    └── main.json
```

## 9. Out of scope (v1)

- CloudTrail/EventBridge near-realtime change detection (poller-only).
- RDS, Lambda, ELB, NAT — config schema is extensible, easy to add later.
- Reserved Instance / Savings Plan amortization — On-Demand prices only.
- Spot pricing — On-Demand only.
- Multi-account / cross-account roles — single IAM principal.
- Alerts (e.g. "creator X exceeded $Y/hr") — future, via `alert` resource.

## 10. Risks & open questions

- **Pricing API instance-type coverage**: the curated whitelist will miss exotic types. Missing prices appear as NULL in the join, visible in the dashboard but not summed. Acceptable for v1.
- **CloudTrail rate limits**: `LookupEvents` is 2 RPS. Cache absorbs most pressure; cold start on a large account may take time to fully resolve creators. The cache stores "unknown" too, so we don't retry endlessly.
- **S3 BucketSizeBytes is daily**: S3 cost will lag by up to 24 hours; documented in the dashboard panel description.
- **Single-region Python process**: boto3 clients are created per region inside the loop. Sequential, not parallel — keeps the function single-generator. Acceptable while region count is small (< 10).
