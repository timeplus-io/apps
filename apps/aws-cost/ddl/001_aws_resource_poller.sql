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
