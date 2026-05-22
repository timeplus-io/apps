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
from datetime import datetime, timezone, timedelta

# Credentials are populated by _tp_init() from the named collection.
# Leaving them empty here keeps secrets out of `SHOW CREATE EXTERNAL STREAM`.
AWS_ACCESS_KEY_ID = ""
AWS_SECRET_ACCESS_KEY = ""
REGIONS = {{ .Config.regions }}
SERVICES = {{ .Config.services }}
POLL_INTERVAL = {{ .Config.poll_interval_seconds }}

def _tp_init(params):
    global AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
    cfg = json.loads(params)
    AWS_ACCESS_KEY_ID = cfg["access_key_id"]
    AWS_SECRET_ACCESS_KEY = cfg["secret_access_key"]

TAG_KEYS = ("createdby", "creatorname", "creator", "owner", "created_by", "createdby_user", "ownername")

S3_STORAGE_TYPES = (
    "StandardStorage", "StandardIAStorage", "OneZoneIAStorage",
    "IntelligentTieringFAStorage", "IntelligentTieringIAStorage",
    "IntelligentTieringAAStorage", "IntelligentTieringAIAStorage",
    "IntelligentTieringDAAStorage",
    "GlacierStorage", "GlacierInstantRetrievalStorage", "DeepArchiveStorage",
    "ReducedRedundancyStorage",
)
S3_REFRESH_SECONDS = 3600

def _tags_to_dict(tag_list):
    if not tag_list:
        return {}
    return {t.get("Key", ""): t.get("Value", "") for t in tag_list}

def _name_from_user_identity(ui):
    # Prefer the readable suffix after ':' in principalId (e.g. "AROA...:alice@co")
    pid = ui.get("principalId", "")
    if ":" in pid:
        suffix = pid.split(":", 1)[1].strip()
        if suffix and not suffix.isdigit():
            return suffix
    # SSO/AssumedRole: last path component of the ARN is the session name
    arn = ui.get("arn", "")
    if "/" in arn:
        tail = arn.rsplit("/", 1)[-1].strip()
        if tail and not tail.isdigit():
            return tail
    # Plain IAM user
    if ui.get("userName"):
        return ui["userName"]
    # Role issuer name as a last structured fallback
    issuer = (ui.get("sessionContext") or {}).get("sessionIssuer") or {}
    if issuer.get("userName"):
        return issuer["userName"]
    return ""

def _resolve_creator(resource_id, tags, cloudtrail_client, cache):
    # Case-insensitive tag lookup so CreatorName / creatorname / CREATOR_NAME all match.
    lower_tags = {k.lower(): v for k, v in tags.items() if v}
    for k in TAG_KEYS:
        if k in lower_tags:
            return lower_tags[k]
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
            ev = events[0]
            raw = ev.get("CloudTrailEvent")
            if raw:
                try:
                    ui = json.loads(raw).get("userIdentity", {}) or {}
                    name = _name_from_user_identity(ui)
                    if name:
                        creator = name
                except Exception:
                    pass
            if creator == "unknown":
                creator = ev.get("Username") or "unknown"
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
                    creator = _resolve_creator(rid, tags, cloudtrail, cache)
                    # Always record the instance's resolved creator so attached
                    # EBS volumes can inherit it as a fallback.
                    cache[rid] = creator
                    rows.append((
                        "ec2",
                        region,
                        rid,
                        inst.get("InstanceType", ""),
                        (inst.get("State") or {}).get("Name", ""),
                        1.0,
                        "instance-hour",
                        json.dumps(tags),
                        creator,
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
                # K8s-provisioned PVC volumes are always created by the EBS CSI
                # driver's IAM role, so CloudTrail would otherwise attribute
                # them to something like 'eks-dev-ebs-csi'. The PVC namespace
                # is the meaningful owner — prefer it before any other lookup.
                ns = tags.get("kubernetes.io/created-for/pvc/namespace")
                if ns:
                    creator = "k8s:{}".format(ns)
                    cache[rid] = creator
                else:
                    creator = _resolve_creator(rid, tags, cloudtrail, cache)
                    # Root/data volumes auto-created by RunInstances aren't
                    # individually indexed in CloudTrail. Fall back to the
                    # attached instance's creator, if we resolved one earlier.
                    if creator == "unknown":
                        attachments = vol.get("Attachments") or []
                        if attachments:
                            inst_id = attachments[0].get("InstanceId", "")
                            inst_creator = cache.get(inst_id)
                            if inst_creator and inst_creator != "unknown":
                                creator = "{} (via {})".format(inst_creator, inst_id)
                                cache[rid] = creator
                rows.append((
                    "ebs",
                    region,
                    rid,
                    vol.get("VolumeType", ""),
                    vol.get("State", ""),
                    float(vol.get("Size", 0)),
                    "gb-month",
                    json.dumps(tags),
                    creator,
                    datetime.now(timezone.utc),
                    json.dumps(vol, default=str),
                ))
    except Exception as e:
        print(f"[aws-cost] ebs {region} error: {e}")
    return rows

def _poll_s3(s3, cw_clients, ct_clients, session_kwargs, cache):
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
            cw = cw_clients.get(loc)
            if cw is None:
                cw = boto3.client("cloudwatch", region_name=loc, **session_kwargs)
                cw_clients[loc] = cw
            ct = ct_clients.get(loc)
            if ct is None:
                ct = boto3.client("cloudtrail", region_name=loc, **session_kwargs)
                ct_clients[loc] = ct
            # S3 BucketSizeBytes is a daily metric, published 24-48h late, and
            # only exists per StorageType that actually has data. Sum the most
            # recent datapoint across all known storage classes, over a 3-day
            # window so we catch the latest available snapshot.
            now_utc = datetime.now(timezone.utc)
            start_utc = now_utc - timedelta(days=3)
            bytes_val = 0.0
            for st in S3_STORAGE_TYPES:
                try:
                    m = cw.get_metric_statistics(
                        Namespace="AWS/S3",
                        MetricName="BucketSizeBytes",
                        Dimensions=[
                            {"Name": "BucketName", "Value": name},
                            {"Name": "StorageType", "Value": st},
                        ],
                        StartTime=start_utc,
                        EndTime=now_utc,
                        Period=86400,
                        Statistics=["Average"],
                    )
                    pts = m.get("Datapoints", [])
                    if pts:
                        bytes_val += max(pts, key=lambda p: p["Timestamp"])["Average"]
                except Exception as e:
                    print(f"[aws-cost] s3 {name} {st} error: {e}")
            rows.append((
                "s3",
                loc,
                name,
                "Standard",
                "active",
                float(bytes_val) / 1e9,
                "gb-month",
                json.dumps(tags),
                _resolve_creator(name, tags, ct, cache),
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
    ec2_clients = {r: boto3.client("ec2", region_name=r, **session_kwargs) for r in REGIONS}
    cloudtrail_clients = {r: boto3.client("cloudtrail", region_name=r, **session_kwargs) for r in REGIONS}
    s3_client = boto3.client("s3", **session_kwargs) if "s3" in SERVICES else None
    s3_cw_clients = {}
    s3_ct_clients = dict(cloudtrail_clients)
    s3_cache_rows = []
    s3_last_refresh = 0.0
    while True:
        try:
            for region in REGIONS:
                ec2 = ec2_clients[region]
                cloudtrail = cloudtrail_clients[region]
                if "ec2" in SERVICES:
                    for row in _poll_ec2(region, ec2, cloudtrail, creator_cache):
                        yield row
                if "ebs" in SERVICES:
                    for row in _poll_ebs(region, ec2, cloudtrail, creator_cache):
                        yield row
            if "s3" in SERVICES and s3_client is not None:
                # S3 bucket size is a daily metric — no point hammering
                # CloudWatch every poll. Refresh once per S3_REFRESH_SECONDS;
                # re-emit cached rows (with refreshed snapshot_ts) in between
                # so downstream views still see a current heartbeat.
                if time.time() - s3_last_refresh >= S3_REFRESH_SECONDS:
                    s3_cache_rows = list(_poll_s3(s3_client, s3_cw_clients, s3_ct_clients, session_kwargs, creator_cache))
                    s3_last_refresh = time.time()
                now_utc = datetime.now(timezone.utc)
                for row in s3_cache_rows:
                    yield row[:9] + (now_utc,) + row[10:]
        except Exception as e:
            print(f"[aws-cost] outer loop error: {e}")
        time.sleep(POLL_INTERVAL)
$$
SETTINGS type='python', mode='streaming', read_function_name='poll_aws',
         init_function_name='_tp_init', named_collection='aws_cost_creds';
