# AWS Cost Monitoring App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Timeplus app (`apps/aws-cost/`) that polls AWS for resource inventory and pricing, joins them in realtime, and visualizes spend by service/region/creator on a dashboard.

**Architecture:** Two Python streaming external_streams (resource poller, price poller) feed an append-only stream and a mutable_stream; a streaming `LEFT JOIN` view computes per-resource cost; roll-up views and a 1-minute MV drive a 6-panel dashboard.

**Tech Stack:** Timeplus SQL (streams, mutable_stream, materialized_view, view), Go `text/template` DDL templating, Python `boto3`, dashboard JSON.

**Spec:** `docs/superpowers/specs/2026-05-18-aws-cost-monitoring-design.md`

**Testing model:** This repo has no unit-test framework — apps are validated by building the `.tpapp` and installing it into a running Timeplus at `localhost:8000`. Each task ends with `make install` (or `make build` for steps that can't yet install) and an explicit verification check.

---

## Task 1: Scaffold the app directory, manifest, and Makefile

**Files:**
- Create: `apps/aws-cost/Makefile`
- Create: `apps/aws-cost/manifest.yaml`
- Create: `apps/aws-cost/ddl/.gitkeep`
- Create: `apps/aws-cost/dashboards/.gitkeep`

- [ ] **Step 1.1: Create directory structure**

```bash
mkdir -p apps/aws-cost/ddl apps/aws-cost/dashboards
touch apps/aws-cost/ddl/.gitkeep apps/aws-cost/dashboards/.gitkeep
```

- [ ] **Step 1.2: Create `apps/aws-cost/Makefile`**

```makefile
APP_NAME    ?= aws-cost
OUT         ?= $(APP_NAME).tpapp

NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default

.PHONY: build install clean

build:
	rm -f $(OUT)
	zip -r $(OUT) manifest.yaml ddl/ dashboards/

install: build
	curl -X POST $(NEUTRON_URL)/$(TENANT)/api/v1beta2/apps/install -F "file=@$(OUT)"

clean:
	rm -f $(OUT)
```

- [ ] **Step 1.3: Create `apps/aws-cost/manifest.yaml`** (resources list initially empty — populated as DDL files are added)

```yaml
package_format_version: 1
id: io.timeplus.aws-cost
name: AWS Resource Cost Monitor
version: 0.1.0
author: Timeplus
description: >
  Realtime AWS resource usage and cost monitoring. Polls EC2 instances,
  EBS volumes, and S3 buckets across configured regions, joins live
  inventory with AWS On-Demand pricing, and breaks down hourly spend by
  service, region, and creator. Requires an IAM principal with:
  ec2:DescribeInstances, ec2:DescribeVolumes, s3:ListAllMyBuckets,
  cloudwatch:GetMetricStatistics, cloudtrail:LookupEvents,
  pricing:GetProducts.
db_name: aws_cost
categories:
  - observability
  - finops

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
    options:
      - ec2
      - ebs
      - s3
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

resources: []

dashboards: []
```

- [ ] **Step 1.4: Verify `make build` succeeds**

Run:
```bash
cd apps/aws-cost && make build
```
Expected: produces `apps/aws-cost/aws-cost.tpapp`, no errors. (Install will fail at this stage because resources list is empty and no DDL exists — that's expected; we wire it up in Task 2.)

- [ ] **Step 1.5: Commit**

```bash
git add apps/aws-cost/
git commit -m "aws-cost: scaffold app directory, manifest, Makefile"
```

---

## Task 2: Resource poller (external_stream → MV → append-only stream)

This task introduces the inventory polling spine. After it lands, installing the app makes resources start flowing into `aws_resources`.

**Files:**
- Create: `apps/aws-cost/ddl/001_aws_resource_poller.sql`
- Create: `apps/aws-cost/ddl/002_aws_resources.sql`
- Create: `apps/aws-cost/ddl/003_mv_resource_inventory.sql`
- Modify: `apps/aws-cost/manifest.yaml` (append to `resources:`)

- [ ] **Step 2.1: Create `ddl/001_aws_resource_poller.sql`**

```sql
CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.aws_resource_poller (
  service        string,
  region         string,
  resource_id    string,
  resource_type  string,
  state          string,
  size_units     float64,
  unit           string,
  tags_json      string,
  creator        string,
  snapshot_ts    datetime64(3),
  raw_payload    string
)
AS $$
import boto3
import json
import time
from datetime import datetime, timezone

AWS_ACCESS_KEY_ID = "{{ .Config.aws_access_key_id }}"
AWS_SECRET_ACCESS_KEY = "{{ .Config.aws_secret_access_key }}"
REGIONS = {{ .Config.regions }}
SERVICES = {{ .Config.services }}
POLL_INTERVAL = {{ .Config.poll_interval_seconds }}

TAG_KEYS = ("CreatedBy", "Owner", "creator", "owner", "created_by")

def _tags_to_dict(tag_list):
    if not tag_list:
        return {}
    return {t.get("Key", ""): t.get("Value", "") for t in tag_list}

def _resolve_creator(resource_id, tags, cloudtrail_client, cache):
    for k in TAG_KEYS:
        if k in tags and tags[k]:
            return tags[k]
    if resource_id in cache:
        return cache[resource_id]
    creator = "unknown"
    try:
        evt = cloudtrail_client.lookup_events(
            LookupAttributes=[
                {"AttributeKey": "ResourceName", "AttributeValue": resource_id}
            ],
            MaxResults=1,
        )
        events = evt.get("Events", [])
        if events:
            creator = events[0].get("Username") or "unknown"
    except Exception:
        creator = "unknown"
    cache[resource_id] = creator
    return creator

def _poll_ec2(region, ec2, cloudtrail, cache):
    rows = []
    try:
        paginator = ec2.get_paginator("describe_instances")
        for page in paginator.paginate():
            for res in page.get("Reservations", []):
                for inst in res.get("Instances", []):
                    tags = _tags_to_dict(inst.get("Tags"))
                    rid = inst.get("InstanceId", "")
                    rows.append((
                        "ec2",
                        region,
                        rid,
                        inst.get("InstanceType", ""),
                        (inst.get("State") or {}).get("Name", ""),
                        1.0,
                        "instance-hour",
                        json.dumps(tags),
                        _resolve_creator(rid, tags, cloudtrail, cache),
                        datetime.now(timezone.utc),
                        json.dumps(inst, default=str),
                    ))
    except Exception as e:
        print(f"[aws-cost] ec2 {region} error: {e}")
    return rows

def _poll_ebs(region, ec2, cloudtrail, cache):
    rows = []
    try:
        paginator = ec2.get_paginator("describe_volumes")
        for page in paginator.paginate():
            for vol in page.get("Volumes", []):
                tags = _tags_to_dict(vol.get("Tags"))
                rid = vol.get("VolumeId", "")
                rows.append((
                    "ebs",
                    region,
                    rid,
                    vol.get("VolumeType", ""),
                    vol.get("State", ""),
                    float(vol.get("Size", 0)),
                    "gb-month",
                    json.dumps(tags),
                    _resolve_creator(rid, tags, cloudtrail, cache),
                    datetime.now(timezone.utc),
                    json.dumps(vol, default=str),
                ))
    except Exception as e:
        print(f"[aws-cost] ebs {region} error: {e}")
    return rows

def _poll_s3(s3, cw_us_east_1, cloudtrail, cache):
    rows = []
    try:
        buckets = s3.list_buckets().get("Buckets", [])
        for b in buckets:
            name = b.get("Name", "")
            try:
                loc = s3.get_bucket_location(Bucket=name).get("LocationConstraint") or "us-east-1"
            except Exception:
                loc = "us-east-1"
            try:
                tag_resp = s3.get_bucket_tagging(Bucket=name)
                tags = _tags_to_dict(tag_resp.get("TagSet"))
            except Exception:
                tags = {}
            try:
                m = cw_us_east_1.get_metric_statistics(
                    Namespace="AWS/S3",
                    MetricName="BucketSizeBytes",
                    Dimensions=[
                        {"Name": "BucketName", "Value": name},
                        {"Name": "StorageType", "Value": "StandardStorage"},
                    ],
                    StartTime=datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0),
                    EndTime=datetime.now(timezone.utc),
                    Period=86400,
                    Statistics=["Average"],
                )
                points = m.get("Datapoints", [])
                bytes_val = points[-1]["Average"] if points else 0.0
            except Exception:
                bytes_val = 0.0
            rows.append((
                "s3",
                loc,
                name,
                "Standard",
                "active",
                float(bytes_val) / 1e9,
                "gb-month",
                json.dumps(tags),
                _resolve_creator(name, tags, cloudtrail, cache),
                datetime.now(timezone.utc),
                json.dumps(b, default=str),
            ))
    except Exception as e:
        print(f"[aws-cost] s3 error: {e}")
    return rows

def poll_aws():
    creator_cache = {}
    session_kwargs = {
        "aws_access_key_id": AWS_ACCESS_KEY_ID,
        "aws_secret_access_key": AWS_SECRET_ACCESS_KEY,
    }
    while True:
        try:
            for region in REGIONS:
                ec2 = boto3.client("ec2", region_name=region, **session_kwargs)
                cloudtrail = boto3.client("cloudtrail", region_name=region, **session_kwargs)
                if "ec2" in SERVICES:
                    for row in _poll_ec2(region, ec2, cloudtrail, creator_cache):
                        yield row
                if "ebs" in SERVICES:
                    for row in _poll_ebs(region, ec2, cloudtrail, creator_cache):
                        yield row
            if "s3" in SERVICES:
                s3 = boto3.client("s3", **session_kwargs)
                cw = boto3.client("cloudwatch", region_name="us-east-1", **session_kwargs)
                ct = boto3.client("cloudtrail", region_name="us-east-1", **session_kwargs)
                for row in _poll_s3(s3, cw, ct, creator_cache):
                    yield row
        except Exception as e:
            print(f"[aws-cost] outer loop error: {e}")
        time.sleep(POLL_INTERVAL)
$$
SETTINGS type='python', mode='streaming', read_function_name='poll_aws';
```

- [ ] **Step 2.2: Create `ddl/002_aws_resources.sql`**

```sql
CREATE STREAM IF NOT EXISTS {{ .DB }}.aws_resources (
  service        string,
  region         string,
  resource_id    string,
  resource_type  string,
  state          string,
  size_units     float64,
  unit           string,
  tags_json      string,
  creator        string,
  snapshot_ts    datetime64(3)
)
TTL to_datetime(snapshot_ts) + INTERVAL 7 DAY;
```

- [ ] **Step 2.3: Create `ddl/003_mv_resource_inventory.sql`**

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_resource_inventory
INTO {{ .DB }}.aws_resources
AS SELECT
  service,
  region,
  resource_id,
  resource_type,
  state,
  size_units,
  unit,
  tags_json,
  creator,
  snapshot_ts
FROM {{ .DB }}.aws_resource_poller;
```

- [ ] **Step 2.4: Update `manifest.yaml` — append to `resources:`**

Replace `resources: []` with:

```yaml
resources:
  - file: ddl/001_aws_resource_poller.sql
    type: external_stream
    name: aws_resource_poller
  - file: ddl/002_aws_resources.sql
    type: stream
    name: aws_resources
  - file: ddl/003_mv_resource_inventory.sql
    type: materialized_view
    name: mv_resource_inventory
```

- [ ] **Step 2.5: Install and verify**

```bash
cd apps/aws-cost && make install
```

Expected: HTTP 200 from the install endpoint, body contains the app id `io.timeplus.aws-cost`. If the response contains `provision <name>: ...` the named DDL failed — re-read that file and fix.

Manual verification (in Timeplus SQL console, using **valid** test credentials in the install dialog):
```sql
SELECT count() FROM table(aws_cost.aws_resources);   -- > 0 after ~1 poll interval
SELECT * FROM aws_cost.aws_resources LIMIT 5;
```

- [ ] **Step 2.6: Commit**

```bash
git add apps/aws-cost/ddl/00{1,2,3}_*.sql apps/aws-cost/manifest.yaml
git commit -m "aws-cost: add resource poller + inventory stream"
```

---

## Task 3: Price poller (external_stream → MV → mutable_stream)

**Files:**
- Create: `apps/aws-cost/ddl/004_aws_price_poller.sql`
- Create: `apps/aws-cost/ddl/005_aws_prices.sql`
- Create: `apps/aws-cost/ddl/006_mv_prices.sql`
- Modify: `apps/aws-cost/manifest.yaml`

- [ ] **Step 3.1: Create `ddl/004_aws_price_poller.sql`**

```sql
CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.aws_price_poller (
  service        string,
  region         string,
  resource_type  string,
  unit           string,
  hourly_usd     float64,
  effective_ts   datetime64(3),
  raw_payload    string
)
AS $$
import boto3
import json
import time
from datetime import datetime, timezone

AWS_ACCESS_KEY_ID = "{{ .Config.aws_access_key_id }}"
AWS_SECRET_ACCESS_KEY = "{{ .Config.aws_secret_access_key }}"
REGIONS = {{ .Config.regions }}
SERVICES = {{ .Config.services }}
REFRESH_HOURS = {{ .Config.price_refresh_hours }}

REGION_LOCATION = {
    "us-east-1": "US East (N. Virginia)",
    "us-east-2": "US East (Ohio)",
    "us-west-1": "US West (N. California)",
    "us-west-2": "US West (Oregon)",
    "eu-west-1": "EU (Ireland)",
    "eu-central-1": "EU (Frankfurt)",
    "ap-southeast-1": "Asia Pacific (Singapore)",
    "ap-northeast-1": "Asia Pacific (Tokyo)",
    "ap-south-1": "Asia Pacific (Mumbai)",
}

EC2_TYPES = [
    "t3.nano","t3.micro","t3.small","t3.medium","t3.large","t3.xlarge","t3.2xlarge",
    "t4g.nano","t4g.micro","t4g.small","t4g.medium","t4g.large","t4g.xlarge",
    "m5.large","m5.xlarge","m5.2xlarge","m5.4xlarge","m5.8xlarge",
    "m6i.large","m6i.xlarge","m6i.2xlarge","m6i.4xlarge",
    "c5.large","c5.xlarge","c5.2xlarge","c5.4xlarge",
    "c6i.large","c6i.xlarge","c6i.2xlarge","c6i.4xlarge",
    "r5.large","r5.xlarge","r5.2xlarge","r5.4xlarge",
    "r6i.large","r6i.xlarge","r6i.2xlarge",
]
EBS_TYPES = ["gp3","gp2","io2","io1","st1","sc1"]
S3_TIERS  = ["Standard","Standard - Infrequent Access","Glacier"]

def _first_price_usd(price_item):
    try:
        terms = (price_item.get("terms") or {}).get("OnDemand") or {}
        for _, term in terms.items():
            for _, pd in (term.get("priceDimensions") or {}).items():
                ppu = (pd.get("pricePerUnit") or {}).get("USD")
                if ppu is not None:
                    return float(ppu)
    except Exception:
        pass
    return None

def _query_ec2_price(pricing, location, instance_type):
    resp = pricing.get_products(
        ServiceCode="AmazonEC2",
        Filters=[
            {"Type":"TERM_MATCH","Field":"location","Value":location},
            {"Type":"TERM_MATCH","Field":"instanceType","Value":instance_type},
            {"Type":"TERM_MATCH","Field":"operatingSystem","Value":"Linux"},
            {"Type":"TERM_MATCH","Field":"tenancy","Value":"Shared"},
            {"Type":"TERM_MATCH","Field":"preInstalledSw","Value":"NA"},
            {"Type":"TERM_MATCH","Field":"capacitystatus","Value":"Used"},
        ],
        MaxResults=1,
    )
    pl = resp.get("PriceList", [])
    if not pl:
        return None, ""
    item = json.loads(pl[0])
    return _first_price_usd(item), pl[0]

def _query_ebs_price(pricing, location, vol_type):
    resp = pricing.get_products(
        ServiceCode="AmazonEC2",
        Filters=[
            {"Type":"TERM_MATCH","Field":"location","Value":location},
            {"Type":"TERM_MATCH","Field":"productFamily","Value":"Storage"},
            {"Type":"TERM_MATCH","Field":"volumeApiName","Value":vol_type},
        ],
        MaxResults=1,
    )
    pl = resp.get("PriceList", [])
    if not pl:
        return None, ""
    item = json.loads(pl[0])
    return _first_price_usd(item), pl[0]

def _query_s3_price(pricing, location, tier):
    resp = pricing.get_products(
        ServiceCode="AmazonS3",
        Filters=[
            {"Type":"TERM_MATCH","Field":"location","Value":location},
            {"Type":"TERM_MATCH","Field":"productFamily","Value":"Storage"},
            {"Type":"TERM_MATCH","Field":"storageClass","Value":tier},
        ],
        MaxResults=1,
    )
    pl = resp.get("PriceList", [])
    if not pl:
        return None, ""
    item = json.loads(pl[0])
    return _first_price_usd(item), pl[0]

def poll_prices():
    pricing = boto3.client(
        "pricing",
        region_name="us-east-1",
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
    )
    while True:
        try:
            for region in REGIONS:
                location = REGION_LOCATION.get(region, region)
                ts = datetime.now(timezone.utc)
                if "ec2" in SERVICES:
                    for it in EC2_TYPES:
                        price, raw = _query_ec2_price(pricing, location, it)
                        if price is not None:
                            yield ("ec2", region, it, "instance-hour", price, ts, raw)
                if "ebs" in SERVICES:
                    for vt in EBS_TYPES:
                        monthly, raw = _query_ebs_price(pricing, location, vt)
                        if monthly is not None:
                            yield ("ebs", region, vt, "gb-month", monthly / 730.0, ts, raw)
                if "s3" in SERVICES:
                    for tier in S3_TIERS:
                        monthly, raw = _query_s3_price(pricing, location, tier)
                        if monthly is not None:
                            short = "Standard" if tier == "Standard" else ("Standard-IA" if "Infrequent" in tier else "Glacier")
                            yield ("s3", region, short, "gb-month", monthly / 730.0, ts, raw)
        except Exception as e:
            print(f"[aws-cost] price poller error: {e}")
        time.sleep(REFRESH_HOURS * 3600)
$$
SETTINGS type='python', mode='streaming', read_function_name='poll_prices';
```

- [ ] **Step 3.2: Create `ddl/005_aws_prices.sql`**

```sql
CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.aws_prices (
  service        string,
  region         string,
  resource_type  string,
  unit           string,
  hourly_usd     float64,
  effective_ts   datetime64(3),
  PRIMARY KEY (service, region, resource_type, unit)
);
```

- [ ] **Step 3.3: Create `ddl/006_mv_prices.sql`**

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_prices
INTO {{ .DB }}.aws_prices
AS SELECT
  service,
  region,
  resource_type,
  unit,
  hourly_usd,
  effective_ts
FROM {{ .DB }}.aws_price_poller;
```

- [ ] **Step 3.4: Update `manifest.yaml` — append to `resources:`**

```yaml
  - file: ddl/004_aws_price_poller.sql
    type: external_stream
    name: aws_price_poller
  - file: ddl/005_aws_prices.sql
    type: mutable_stream
    name: aws_prices
  - file: ddl/006_mv_prices.sql
    type: materialized_view
    name: mv_prices
```

- [ ] **Step 3.5: Install and verify**

Uninstall any prior version first (the UI does this; or use the API), then:
```bash
cd apps/aws-cost && make install
```

Manual verification (after ~30 seconds, since the Pricing API is slow):
```sql
SELECT count() FROM table(aws_cost.aws_prices);
SELECT * FROM table(aws_cost.aws_prices)
  WHERE service='ec2' AND region='us-east-1' LIMIT 10;
```
Expected: non-zero rows; `hourly_usd` looks reasonable (`m5.large` ≈ 0.096).

- [ ] **Step 3.6: Commit**

```bash
git add apps/aws-cost/ddl/00{4,5,6}_*.sql apps/aws-cost/manifest.yaml
git commit -m "aws-cost: add price poller + prices mutable_stream"
```

---

## Task 4: Cost join + roll-up views

**Files:**
- Create: `apps/aws-cost/ddl/007_v_resource_cost_now.sql`
- Create: `apps/aws-cost/ddl/008_v_cost_by_creator.sql`
- Create: `apps/aws-cost/ddl/009_v_cost_by_service_region.sql`
- Create: `apps/aws-cost/ddl/010_v_top_expensive.sql`
- Modify: `apps/aws-cost/manifest.yaml`

- [ ] **Step 4.1: Create `ddl/007_v_resource_cost_now.sql`**

```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_resource_cost_now AS
SELECT
  r._tp_time                            AS ts,
  r.service                             AS service,
  r.region                              AS region,
  r.resource_id                         AS resource_id,
  r.resource_type                       AS resource_type,
  r.state                               AS state,
  r.size_units                          AS size_units,
  r.unit                                AS unit,
  r.creator                             AS creator,
  r.tags_json                           AS tags_json,
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

- [ ] **Step 4.2: Create `ddl/008_v_cost_by_creator.sql`**

```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_cost_by_creator AS
SELECT
  creator,
  sum(hourly_cost_usd)  AS hourly_usd,
  sum(monthly_cost_usd) AS monthly_usd,
  count()               AS resources
FROM {{ .DB }}.v_resource_cost_now
WHERE _tp_time > now() - 2m
  AND state IN ('running','in-use','active')
  AND hourly_cost_usd IS NOT NULL
GROUP BY creator
EMIT ON UPDATE WITH DELAY 5s;
```

- [ ] **Step 4.3: Create `ddl/009_v_cost_by_service_region.sql`**

```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_cost_by_service_region AS
SELECT
  service,
  region,
  sum(hourly_cost_usd) AS hourly_usd,
  count()              AS resources
FROM {{ .DB }}.v_resource_cost_now
WHERE _tp_time > now() - 2m
  AND state IN ('running','in-use','active')
  AND hourly_cost_usd IS NOT NULL
GROUP BY service, region
EMIT ON UPDATE WITH DELAY 5s;
```

- [ ] **Step 4.4: Create `ddl/010_v_top_expensive.sql`**

`LIMIT n` directly on a streaming source query *terminates* the stream after n rows globally — wrong semantics for a "top 20 right now" panel. Wrap in a 1-minute tumble window so each emit produces a bounded batch that ORDER BY + LIMIT can sort.

```sql
CREATE VIEW IF NOT EXISTS {{ .DB }}.v_top_expensive AS
SELECT
  window_start                AS time,
  resource_id,
  service,
  region,
  resource_type,
  creator,
  any(hourly_cost_usd)        AS hourly_cost_usd,
  any(monthly_cost_usd)       AS monthly_cost_usd
FROM tumble({{ .DB }}.v_resource_cost_now, _tp_time, 1m)
WHERE state IN ('running','in-use','active')
  AND hourly_cost_usd IS NOT NULL
GROUP BY window_start, resource_id, service, region, resource_type, creator
ORDER BY hourly_cost_usd DESC
LIMIT 20;
```

- [ ] **Step 4.5: Update `manifest.yaml` — append to `resources:`**

```yaml
  - file: ddl/007_v_resource_cost_now.sql
    type: view
    name: v_resource_cost_now
  - file: ddl/008_v_cost_by_creator.sql
    type: view
    name: v_cost_by_creator
  - file: ddl/009_v_cost_by_service_region.sql
    type: view
    name: v_cost_by_service_region
  - file: ddl/010_v_top_expensive.sql
    type: view
    name: v_top_expensive
```

- [ ] **Step 4.6: Install and verify**

```bash
cd apps/aws-cost && make install
```

Manual verification (in Timeplus SQL console):
```sql
SELECT * FROM aws_cost.v_resource_cost_now LIMIT 5;       -- streaming, has hourly_cost_usd
SELECT * FROM aws_cost.v_cost_by_creator LIMIT 20;        -- streaming aggregation
```
Expected: rows with non-null `hourly_cost_usd` for at least one (service, region, resource_type) where both sides match. If everything is NULL, check that price rows exist for those exact keys.

- [ ] **Step 4.7: Commit**

```bash
git add apps/aws-cost/ddl/0{07,08,09,10}_*.sql apps/aws-cost/manifest.yaml
git commit -m "aws-cost: add cost join view + roll-up views"
```

---

## Task 5: 1-minute total spend rate stream

**Files:**
- Create: `apps/aws-cost/ddl/011_aws_cost_1m.sql`
- Create: `apps/aws-cost/ddl/012_mv_cost_1m.sql`
- Modify: `apps/aws-cost/manifest.yaml`

- [ ] **Step 5.1: Create `ddl/011_aws_cost_1m.sql`**

```sql
CREATE STREAM IF NOT EXISTS {{ .DB }}.aws_cost_1m (
  time              datetime64(3),
  total_hourly_usd  float64,
  resource_count    uint32
)
TTL to_datetime(time) + INTERVAL 30 DAY;
```

- [ ] **Step 5.2: Create `ddl/012_mv_cost_1m.sql`**

The MV reads from `v_resource_cost_now`. We alias `window_start` to `time` because `window_start` is reserved in stream column names.

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cost_1m
INTO {{ .DB }}.aws_cost_1m
AS SELECT
  window_start                  AS time,
  sum(hourly_cost_usd)          AS total_hourly_usd,
  to_uint32(count())            AS resource_count
FROM tumble({{ .DB }}.v_resource_cost_now, _tp_time, 1m)
WHERE state IN ('running','in-use','active')
  AND hourly_cost_usd IS NOT NULL
GROUP BY window_start;
```

- [ ] **Step 5.3: Update `manifest.yaml` — append to `resources:`**

```yaml
  - file: ddl/011_aws_cost_1m.sql
    type: stream
    name: aws_cost_1m
  - file: ddl/012_mv_cost_1m.sql
    type: materialized_view
    name: mv_cost_1m
```

- [ ] **Step 5.4: Install and verify**

```bash
cd apps/aws-cost && make install
```

Manual verification (wait > 1 minute after install):
```sql
SELECT * FROM table(aws_cost.aws_cost_1m) ORDER BY time DESC LIMIT 5;
```
Expected: one row per minute with a positive `total_hourly_usd`.

- [ ] **Step 5.5: Commit**

```bash
git add apps/aws-cost/ddl/01{1,2}_*.sql apps/aws-cost/manifest.yaml
git commit -m "aws-cost: add 1-minute total spend rate stream"
```

---

## Task 6: Dashboard

**Files:**
- Create: `apps/aws-cost/dashboards/main.json`
- Modify: `apps/aws-cost/manifest.yaml`

- [ ] **Step 6.1: Create `dashboards/main.json`**

```json
[
  {
    "id": "kpi-total-rate",
    "title": "Total Spend Rate",
    "description": "Current USD per hour across monitored resources",
    "position": { "h": 2, "w": 6, "x": 0, "y": 0, "nextX": 6, "nextY": 2 },
    "viz_type": "chart",
    "viz_content": "SELECT total_hourly_usd FROM table([[ .DB ]].aws_cost_1m) ORDER BY time DESC LIMIT 1",
    "viz_config": {
      "chartType": "singleValue",
      "config": {
        "field": "total_hourly_usd",
        "fontSize": 48,
        "unit": { "position": "left", "value": "$" },
        "fractionDigits": 2,
        "thresholds": []
      }
    }
  },
  {
    "id": "kpi-monthly-proj",
    "title": "Monthly Projection",
    "description": "Current hourly rate × 730 hours",
    "position": { "h": 2, "w": 6, "x": 6, "y": 0, "nextX": 12, "nextY": 2 },
    "viz_type": "chart",
    "viz_content": "SELECT total_hourly_usd * 730 AS monthly_usd FROM table([[ .DB ]].aws_cost_1m) ORDER BY time DESC LIMIT 1",
    "viz_config": {
      "chartType": "singleValue",
      "config": {
        "field": "monthly_usd",
        "fontSize": 48,
        "unit": { "position": "left", "value": "$" },
        "fractionDigits": 0,
        "thresholds": []
      }
    }
  },
  {
    "id": "chart-cost-time",
    "title": "Hourly Cost Over Time",
    "description": "1-minute samples of total spend rate (USD/hr)",
    "position": { "h": 4, "w": 12, "x": 0, "y": 2, "nextX": 12, "nextY": 6 },
    "viz_type": "chart",
    "viz_content": "SELECT time, total_hourly_usd FROM [[ .DB ]].aws_cost_1m WHERE _tp_time > now() - 6h",
    "viz_config": {
      "chartType": "line",
      "config": {
        "xAxis": "time",
        "yAxis": "total_hourly_usd",
        "xRange": "Infinity",
        "lineStyle": "curve",
        "legend": false,
        "gridlines": true,
        "yRange": { "min": 0, "max": null },
        "colors": ["#D53F8C"]
      }
    }
  },
  {
    "id": "chart-by-service-region",
    "title": "Cost by Service × Region",
    "description": "Hourly USD grouped by service and region (latest cycle)",
    "position": { "h": 4, "w": 6, "x": 0, "y": 6, "nextX": 6, "nextY": 10 },
    "viz_type": "chart",
    "viz_content": "SELECT service, region, hourly_usd FROM [[ .DB ]].v_cost_by_service_region",
    "viz_config": {
      "chartType": "bar",
      "config": {
        "xAxis": "region",
        "yAxis": "hourly_usd",
        "color": "service",
        "dataLabel": false,
        "gridlines": true,
        "colors": ["#D53F8C","#9F2BC0","#F7775A","#F0BE3E","#8934D9","#DA4B36"]
      }
    }
  },
  {
    "id": "chart-by-creator",
    "title": "Cost by Creator",
    "description": "Who is currently spending money (latest cycle)",
    "position": { "h": 4, "w": 6, "x": 6, "y": 6, "nextX": 12, "nextY": 10 },
    "viz_type": "chart",
    "viz_content": "SELECT creator, hourly_usd FROM [[ .DB ]].v_cost_by_creator ORDER BY hourly_usd DESC LIMIT 15",
    "viz_config": {
      "chartType": "bar",
      "config": {
        "xAxis": "creator",
        "yAxis": "hourly_usd",
        "dataLabel": true,
        "gridlines": true,
        "colors": ["#9F2BC0"]
      }
    }
  },
  {
    "id": "table-top-resources",
    "title": "Top 20 Expensive Resources",
    "description": "Resources sorted by hourly cost (latest cycle)",
    "position": { "h": 6, "w": 12, "x": 0, "y": 10, "nextX": 12, "nextY": 16 },
    "viz_type": "chart",
    "viz_content": "SELECT resource_id, service, region, resource_type, creator, hourly_cost_usd, monthly_cost_usd FROM [[ .DB ]].v_top_expensive",
    "viz_config": {
      "chartType": "table",
      "config": {
        "updateMode": "all",
        "columns": []
      }
    }
  }
]
```

- [ ] **Step 6.2: Update `manifest.yaml` — set `dashboards:`**

Replace `dashboards: []` with:

```yaml
dashboards:
  - file: dashboards/main.json
    name: AWS Cost Monitor
    description: Realtime AWS spend by service, region, and creator
```

- [ ] **Step 6.3: Install and verify in the Timeplus UI**

```bash
cd apps/aws-cost && make install
```

Open the Timeplus UI → Apps → AWS Resource Cost Monitor → the AWS Cost Monitor dashboard.

Expected (after ~2 poll cycles):
- "Total Spend Rate" shows a non-zero `$ X.XX`
- "Monthly Projection" shows `$ X,XXX`
- "Hourly Cost Over Time" line starts filling in (one point per minute)
- "Cost by Service × Region" shows stacked bars for ec2/ebs/s3 across configured regions
- "Cost by Creator" shows at least one bar (likely `unknown` if test resources have no creator tags; verify tag-resolution works by adding a `CreatedBy=test` tag to an EC2 instance and re-polling)
- "Top 20" table populates with resource_ids and dollar values

If a panel is empty, run its `viz_content` SQL directly in the SQL console (after substituting `[[ .DB ]]` → `aws_cost`) to isolate whether it's an SQL or rendering issue.

- [ ] **Step 6.4: Commit**

```bash
git add apps/aws-cost/dashboards/main.json apps/aws-cost/manifest.yaml
git commit -m "aws-cost: add dashboard"
```

---

## Task 7: Update root-level discoverability

The root `Makefile` accepts `APP=<name>`. Make sure `make build APP=aws-cost` works from the repo root.

**Files:** (verify-only; no changes expected)

- [ ] **Step 7.1: Verify root build**

```bash
make build APP=aws-cost
```
Expected: produces `apps/aws-cost/aws-cost.tpapp`, no errors.

- [ ] **Step 7.2: No-op if pass; if fail, update root Makefile**

If step 7.1 fails because the root Makefile hard-codes a default APP, inspect it and adjust. Common pattern:

```makefile
APP ?= market-data
build:
	$(MAKE) -C apps/$(APP) build
```
No change needed if the structure matches; otherwise commit the fix.

- [ ] **Step 7.3: Commit if any change**

```bash
git add Makefile
git commit -m "aws-cost: make root Makefile target aws-cost"
```

---

## Notes / gotchas

- **Pricing API slowness**: the price poller makes serial HTTP calls; the first full cycle can take several minutes. Until it completes, `v_resource_cost_now` will show NULL costs (LEFT JOIN behavior is intentional).
- **CloudTrail throttling**: the creator resolver caches results (including `"unknown"`), so a single throttled call doesn't keep failing — but a fresh install against a large account may report many `"unknown"` creators on the first cycle.
- **S3 BucketSizeBytes is daily**: the metric refreshes once per day. S3 cost will appear stale relative to EC2/EBS by up to 24 h.
- **Reserved column names**: `window_start` is generated by `tumble` — never use it as a stream column. We alias to `time` in step 5.2.
- **Re-installing**: the installer is idempotent for `CREATE … IF NOT EXISTS`, but the Python streaming functions hold long-lived connections — if you change the Python body, you must uninstall and reinstall the app for the new code to take effect.
