CREATE OR REPLACE FUNCTION alert_to_slack(value string) RETURNS string LANGUAGE PYTHON AS $$
import json
import requests

def alert_to_slack(value):
    webhook_url = '{{ .Config.slack_webhook_url }}'
    result = ""
    for val in value:
        result += f"{val}\n"
    if webhook_url:
        requests.post(webhook_url, data=json.dumps({"text": result}))
    return value
$$;
