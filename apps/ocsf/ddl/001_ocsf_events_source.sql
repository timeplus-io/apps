CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.ocsf_events_source (
  raw           string,
  class_uid     uint32,
  generated_at  datetime64(3)
)
AS $$
import json
import time
from datetime import datetime
from ocsf_simulator import stream_ocsf_events

def read_ocsf_events():
    classes = [int(x) for x in "{{ .Config.event_classes }}".split(",") if x.strip()]
    interval = float("{{ .Config.interval_seconds }}")
    version = "{{ .Config.ocsf_version }}"

    while True:
        try:
            for event in stream_ocsf_events(
                event_classes=classes,
                interval=interval,
                ocsf_version=version,
            ):
                yield (
                    json.dumps(event),
                    int(event.get("class_uid", 0)),
                    datetime.utcnow(),
                )
        except Exception:
            time.sleep(5)
$$
SETTINGS type='python', mode='streaming', read_function_name='read_ocsf_events';
