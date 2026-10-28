
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from datetime import datetime

state = {
    "hall1": False,
    "hall2": False,
    "connected": True,
    "last_updated": None
}

class Handler(BaseHTTPRequestHandler):
    def send_json(self, data, status=200):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_json({})

    def do_GET(self):
        if self.path == "/api/hall":
            self.send_json(state)
        else:
            self.send_json({"error": "Not found"}, 404)

    def do_POST(self):
        if self.path != "/api/simulate":
            self.send_json({"error": "Not found"}, 404)
            return

        try:
            length = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(length))

            sensor = data.get("sensor")
            detected = data.get("detected")

            if sensor not in ("hall1", "hall2") or type(detected) is not bool:
                self.send_json({"error": "Invalid sensor or value"}, 400)
                return

            state[sensor] = detected
            state["last_updated"] = datetime.now().isoformat()
            print(f"{sensor} = {detected}", flush=True)
            self.send_json(state)

        except Exception as error:
            self.send_json({"error": str(error)}, 400)

print("Hall simulator running at http://127.0.0.1:5000")
HTTPServer(("127.0.0.1", 5000), Handler).serve_forever()
