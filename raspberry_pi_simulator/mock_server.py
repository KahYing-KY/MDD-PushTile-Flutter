
import json
from datetime import datetime
from pathlib import Path

from flask import Flask, jsonify, request
from flask_cors import CORS

app = Flask(__name__)

# Local development only
CORS(app)

DATA_FILE = Path(__file__).parent / "progress_screen.dat"

sensor_state = {
    "hall1": False,
    "hall2": False,
    "connected": True,
    "last_updated": None,
}


def save_event(sensor, detected):
    timestamp = datetime.now().astimezone().isoformat(
        timespec="milliseconds"
    )

    event = {
        "timestamp": timestamp,
        "sensor": sensor,
        "detected": detected,
    }

    with DATA_FILE.open("a", encoding="utf-8") as file:
        file.write(json.dumps(event) + "\n")

    sensor_state["last_updated"] = timestamp

    print("Saved:", event)


@app.get("/api/hall")
def get_hall():
    return jsonify(sensor_state)


@app.get("/api/history")
def get_history():
    history = []

    if DATA_FILE.exists():
        with DATA_FILE.open("r", encoding="utf-8") as file:
            for line in file:
                try:
                    history.append(json.loads(line))
                except json.JSONDecodeError:
                    continue

    return jsonify(history[-100:][::-1])


@app.post("/api/simulate")
def simulate():
    data = request.get_json(silent=True) or {}

    sensor = data.get("sensor")
    detected = data.get("detected")

    if sensor not in ("hall1", "hall2") or type(detected) is not bool:
        return jsonify({"error": "Invalid sensor data"}), 400

    if sensor_state[sensor] != detected:
        sensor_state[sensor] = detected
        save_event(sensor, detected)

    return jsonify(sensor_state)


if __name__ == "__main__":
    print("Mock Raspberry Pi server running...")
    app.run(host="127.0.0.1", port=5000, debug=False)
