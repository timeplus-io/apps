CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.coinbase_websocket_read_connector(
  type         string,
  product_id   string,
  channel      string,
  full_payload string,
  received_at  datetime64(3)
)
AS $$
import websocket
import json5
import time
from datetime import datetime

def read_coinbase_websocket_stream():
    websocket_url = "{{ index .Config "websocket_url" }}"
    subscription_message = '{"type": "subscribe", "product_ids": ["BTC-USD"], "channels": ["ticker"]}'

    ws = None
    while True:
        try:
            ws = websocket.create_connection(websocket_url)
            ws.send(subscription_message)

            while True:
                message = ws.recv() or ""
                parsed_message = json5.loads(message) or {}

                msg_type = parsed_message.get("type") or ""
                product_id = parsed_message.get("product_id") or ""

                channel_name = ""
                channels = parsed_message.get("channels")
                if msg_type == "subscriptions" and channels:
                    channel_name = ", ".join([c.get("name", "unknown") for c in channels]) or ""
                elif "channel" in parsed_message:
                    channel_name = parsed_message.get("channel") or ""

                yield (
                    msg_type,
                    product_id,
                    channel_name,
                    message,
                    datetime.utcnow(),
                )

        except Exception:
            time.sleep(5)
        finally:
            if ws:
                ws.close()
        time.sleep(1)

$$
SETTINGS type='python', mode='streaming', read_function_name='read_coinbase_websocket_stream';
