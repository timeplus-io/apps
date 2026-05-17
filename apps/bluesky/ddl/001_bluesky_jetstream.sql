CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.bluesky_jetstream (
  did         string,
  time_us     int64,
  kind        string,
  operation   string,
  collection  string,
  rkey        string,
  cid         string,
  record_json string,
  raw_event   string,
  received_at datetime64(3)
)
AS $$
import websocket
import json
import time
from datetime import datetime

def read_bluesky_jetstream():
    jetstream_url = "{{ .Config.jetstream_url }}"
    wanted_collections = json.loads('{{ .Config.wanted_collections }}')

    ws = None
    while True:
        try:
            params = {}
            for collection in wanted_collections:
                collection = collection.strip()
                if collection:
                    params.setdefault("wantedCollections", []).append(collection)

            query_parts = []
            for key, values in params.items():
                for v in values:
                    query_parts.append(f"{key}={v}")

            url = jetstream_url
            if query_parts:
                url = f"{jetstream_url}?{'&'.join(query_parts)}"

            ws = websocket.create_connection(url, timeout=30)

            while True:
                message = ws.recv()
                if not message:
                    continue

                received_at = datetime.utcnow()

                try:
                    event = json.loads(message)
                except json.JSONDecodeError:
                    continue

                did = event.get("did") or ""
                time_us = event.get("time_us") or 0
                kind = event.get("kind") or ""

                operation = ""
                collection = ""
                rkey = ""
                cid = ""
                record_json = ""

                if kind == "commit":
                    commit = event.get("commit") or {}
                    operation = commit.get("operation") or ""
                    collection = commit.get("collection") or ""
                    rkey = commit.get("rkey") or ""
                    cid = commit.get("cid") or ""
                    record = commit.get("record")
                    if record:
                        record_json = json.dumps(record)

                yield (
                    did,
                    time_us,
                    kind,
                    operation,
                    collection,
                    rkey,
                    cid,
                    record_json,
                    message,
                    received_at,
                )

        except Exception:
            time.sleep(5)
        finally:
            if ws:
                try:
                    ws.close()
                except Exception:
                    pass
        time.sleep(1)

$$
SETTINGS type='python', mode='streaming', read_function_name='read_bluesky_jetstream';
