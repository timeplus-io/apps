# AWS Resource Cost Monitor

A Timeplus app that polls AWS for live resource inventory and pricing, joins them in realtime, and surfaces hourly spend by **service**, **region**, and **creator**.

## What it monitors

- **EC2 instances** — priced per `instance-hour`
- **EBS volumes** — priced per GB (monthly rate ÷ 730 to normalize hourly)
- **S3 buckets** — size summed across all storage classes from CloudWatch `BucketSizeBytes`; priced per GB

Resources, regions, and services are all configurable at install time.

## How it works

```
aws_resource_poller  (Python streaming, boto3, every 60s)
   └── mv_resource_inventory ──► aws_resources  (append, 7d TTL)

aws_price_poller     (Python streaming, AWS Pricing API, every 6h)
   └── mv_prices ──► aws_prices  (mutable, PK = service+region+type+unit)

aws_resources
   │
   ▼ hop(step=1m, window=5m) + latest() per resource_id
aws_resource_usage_live  (mutable, PK = resource_id)
   │
   ▼ LEFT JOIN aws_prices   (filter: snapshot_ts > now()-90s)
aws_resource_cost_live   (mutable, PK = resource_id, holds current cost)
   │
   ▼ simple single-level GROUP BY  (snapshot_ts > now()-90s)
v_cost_by_creator
v_cost_by_service_region
v_top_expensive
v_resource_cost_now   (passthrough view of cost_live)

aws_resources
   └── mv_cost_1m  (hop+latest+JOIN inline, 1m tumble) ──► aws_cost_1m  (time series, 30d TTL)
```

### Why two pipelines

- The **live** pipeline (`usage_live` → `cost_live`) uses mutable streams so rollup views can do simple single-level `GROUP BY` with proper changelog semantics — no double counting, correct counts.
- The **time-series** pipeline (`mv_cost_1m`) writes to an append stream (`aws_cost_1m`) for the "Hourly Cost Over Time" chart. `tumble()` isn't supported on changelog inputs, so it tumbles directly on `aws_resources` and does the same `hop + latest + JOIN` dedup inline.

### Freshness filter (`snapshot_ts > now() - 90s`)

Mutable streams accumulate one row per resource forever, even after a resource is terminated. The hop window fires every 1 minute, so any resource present in the latest poll has `snapshot_ts` within the last ~1m. Every cost view filters `snapshot_ts > now() - 90s` (1 hop step + 30s margin) to ignore stale entries from disappeared resources.

### Creator attribution

Resolved in this order (first hit wins):

1. **Tags** (case-insensitive): `CreatedBy`, `CreatorName`, `Creator`, `Owner`, `created_by`, `createdby_user`, `ownername`.
2. **Kubernetes PVC namespace** (EBS only): `kubernetes.io/created-for/pvc/namespace` → `k8s:<namespace>`. Applied *before* CloudTrail so CSI-driver volumes aren't attributed to `eks-*-ebs-csi`.
3. **CloudTrail `LookupEvents`** — parses the full `userIdentity` block (principalId / arn / sessionContext) to get a human name, not a numeric ID.
4. **Inherit from attached EC2 instance** (EBS only): root/data volumes auto-created by `RunInstances` show as `<creator> (via i-…)`.
5. `unknown` — typical for resources older than CloudTrail's 90-day window with no tags. Add a `CreatorName` tag to fix.

The `v_k8s_volumes` view surfaces EBS volumes provisioned by Kubernetes with their cluster, namespace, PVC name, and PV name.

## Build & install

```bash
make build                # produces aws-cost.tpapp
make install              # POSTs to localhost:8000
```

Or from the repo root: `make build APP=aws-cost`.

## Config

| key | type | default | notes |
|---|---|---|---|
| `aws_access_key_id` | string (secret) | — | required |
| `aws_secret_access_key` | string (secret) | — | required |
| `regions` | list | `["us-east-1","us-west-2"]` | JSON array of region codes |
| `services` | multi_choice | `["ec2","ebs","s3"]` | subset of `ec2`, `ebs`, `s3` |
| `poll_interval_seconds` | integer | `60` | resource re-scan cadence |
| `price_refresh_hours` | integer | `6` | pricing API refresh cadence |

S3 bucket sizes are refreshed once per hour internally (the daily CloudWatch metric changes at most once a day, so faster polling is wasted CloudWatch calls).

## Credentials handling

Starting in v0.3.1, the two AWS keys you supply at install time are stored in a Proton **named collection** (`aws_cost_creds`) rather than rendered into the Python stream body. This keeps them out of `SHOW CREATE EXTERNAL STREAM aws_cost.aws_resource_poller` (and the price poller). The streams reference the collection via `SETTINGS named_collection='aws_cost_creds'`, and a `_tp_init()` hook injects the values at session start.

**Privileges the installing principal needs** (in addition to the usual create-stream grants):

- `CREATE NAMED COLLECTION` — to create `aws_cost_creds`
- `NAMED COLLECTION` on `aws_cost_creds` — to attach it to the two external streams

**Where the secrets are still visible:** `system.named_collections` returns the raw JSON blob (Proton auto-masks only the literal key `password`). Restrict `SELECT` on that table to operators. `SELECT name FROM system.named_collections` is safe and works for discovery.

**Upgrading from v0.3.0** (which still has credentials in the Python body): re-installing the package will create `aws_cost_creds` but the existing streams keep their old bodies because `CREATE EXTERNAL STREAM IF NOT EXISTS` is a no-op. `ALTER STREAM ... MODIFY SETTING` can't rewrite the `$$ ... $$` Python body either. Drop the two pollers and reinstall:

```sql
DROP STREAM aws_cost.aws_resource_poller;
DROP STREAM aws_cost.aws_price_poller;
-- then reinstall the app
```

**Rotating credentials later:** `ALTER NAMED COLLECTION aws_cost_creds SET init_function_parameters='{"access_key_id":"…","secret_access_key":"…"}'` updates `system.named_collections`, but the two streams captured the old value at create time (Proton merges the collection into stream settings only during storage construction). To actually rotate, drop and re-create the two streams after the `ALTER NAMED COLLECTION`.

## IAM permissions required

The IAM principal needs:

- `ec2:DescribeInstances`
- `ec2:DescribeVolumes`
- `s3:ListAllMyBuckets`, `s3:GetBucketLocation`, `s3:GetBucketTagging`
- `cloudwatch:GetMetricStatistics`
- `cloudtrail:LookupEvents` (for creator fallback)
- `pricing:GetProducts`

All actions are read-only. None of them support resource-level constraints in IAM, so `Resource: "*"` is required.

**Inline policy** (paste into IAM → Users → *user* → Add permissions → Create inline policy → JSON):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AwsCostInventory",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeVolumes",
        "s3:ListAllMyBuckets",
        "s3:GetBucketLocation",
        "s3:GetBucketTagging",
        "cloudwatch:GetMetricStatistics",
        "cloudtrail:LookupEvents",
        "pricing:GetProducts"
      ],
      "Resource": "*"
    }
  ]
}
```

Or via CLI:

```bash
aws iam put-user-policy \
  --user-name <your-user> \
  --policy-name TimeplusAwsCostMonitor \
  --policy-document file://policy.json
```

## Dashboard

`dashboards/main.json` — 6 panels:

- **Total Spend Rate** (singleValue, USD/hr)
- **Monthly Projection** (singleValue, hourly × 730)
- **Hourly Cost Over Time** (line, last 24h)
- **Cost by Service × Region** (stacked bar)
- **Cost by Creator** (bar)
- **Top 20 Expensive Resources** (table)

## Known limitations

- **Pricing API cold start**: the price poller queries dozens of (region, type) pairs serially; the first cycle takes several minutes. Until it completes, `hourly_cost_usd` will be NULL for unmatched resources.
- **EC2 instance-type whitelist**: the price poller iterates a curated set (`t3.*`, `m5.*`, `c5.*`, `r5.*`, `t4g.*`, `m6i.*`, `c6i.*`, `r6i.*`). Resources of other families (`m6a.*`, `c3.*`, etc.) will show with `hourly_cost_usd = 0` until added to the whitelist.
- **S3 size is daily**: `BucketSizeBytes` is a daily CloudWatch metric, so S3 cost lags by up to 48h.
- **On-Demand only**: no Reserved Instance / Savings Plan / Spot pricing in v1.
- **Single IAM principal**: no cross-account assumption.
- **Mutable stream growth**: `aws_resource_usage_live` and `aws_resource_cost_live` keep one row per resource_id forever (no auto-cleanup). The `snapshot_ts > now() - 90s` filter hides stale entries from dashboards, but the underlying streams accumulate over time. Negligible for typical accounts.
