# AWS Resource Cost Monitor

A Timeplus app that polls AWS for live resource inventory and pricing, joins them in realtime, and surfaces hourly spend by **service**, **region**, and **creator**.

## What it monitors

- **EC2 instances** — priced per `instance-hour`
- **EBS volumes** — priced per GB (monthly rate ÷ 730 to normalize hourly)
- **S3 buckets** — size from CloudWatch `BucketSizeBytes` (daily granularity); priced per GB

Resources, regions, and services are all configurable at install time.

## How it works

```
aws_resource_poller  (Python streaming, boto3)
   └── mv_resource_inventory ─→ aws_resources  (append-only, 7d TTL)

aws_price_poller     (Python streaming, AWS Pricing API)
   └── mv_prices ─→ aws_prices  (mutable_stream, PK=service+region+type+unit)

aws_resources  ⋈  aws_prices  (streaming JOIN)
   └── v_resource_cost_now      per-resource hourly + monthly cost
        ├── v_cost_by_creator
        ├── v_cost_by_service_region
        ├── v_top_expensive      (1-min tumble window, top 20)
        └── mv_cost_1m ─→ aws_cost_1m  (1-minute total spend rate, 30d TTL)
```

The resource poller runs on `poll_interval_seconds` (default 60s). The price poller is slower — every `price_refresh_hours` (default 6h) — since On-Demand prices change rarely.

**Creator attribution** is best-effort: tag-first (`CreatedBy`, `Owner`, `creator`, `owner`, `created_by`), falling back to CloudTrail `LookupEvents` (cached per resource id). Resources without tags in accounts with no CloudTrail history appear as `unknown`.

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
- **EC2 instance-type whitelist**: the price poller iterates a curated set (`t3.*`, `m5.*`, `c5.*`, `r5.*`, `t4g.*`, `m6i.*`, `c6i.*`, `r6i.*`). Resources of other families will show with NULL cost.
- **S3 size is daily**: `BucketSizeBytes` is a daily CloudWatch metric, so S3 cost lags by up to 24h.
- **On-Demand only**: no Reserved Instance / Savings Plan / Spot pricing in v1.
- **Single IAM principal**: no cross-account assumption.
