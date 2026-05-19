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
