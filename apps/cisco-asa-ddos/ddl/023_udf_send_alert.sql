CREATE OR REPLACE FUNCTION send_ddos_alert(title string, content string, severity string)
RETURNS string
LANGUAGE PYTHON AS $$
import json
import requests

def send_ddos_alert(title, content, severity):
    results = []
    for t, c, s in zip(title, content, severity):
        try:
            requests.post(
                '{{ .Config.alert_webhook_url }}',
                data=json.dumps({'title': t, 'message': c, 'severity': s}),
                timeout=5
            )
        except Exception:
            pass
        results.append('OK')
    return results
$$
