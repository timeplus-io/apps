CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.taxi_feed(
  car_id     string,
  ts         datetime64(3),
  longitude  float64,
  latitude   float64,
  speed_kmh  float64
)
AS $$
from taxi_simulator import stream_taxi_data
from datetime import datetime
import time

def read_taxi_stream():
    while True:
        try:
            for ev in stream_taxi_data(
                num_cars={{ .Config.num_cars }},
                speed_kmh={{ .Config.speed_kmh }},
            ):
                yield (
                    ev["car_id"],
                    datetime.fromisoformat(ev["time"].replace("Z", "+00:00")),
                    ev["longitude"],
                    ev["latitude"],
                    ev["speed_kmh"],
                )
        except Exception:
            time.sleep(2)
$$
SETTINGS type='python', mode='streaming', read_function_name='read_taxi_stream';
