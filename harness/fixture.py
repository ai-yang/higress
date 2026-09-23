"""Deterministic Redis/upstream fixture; no external dependencies or data."""
import json
import socketserver
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOCK = threading.RLock()
CASES = {}
EVENTS = []
CACHED = b'{"source":"cache","value":"fixture-only"}'
UPSTREAM = b'{"source":"upstream","value":"fixture-only"}'


def event(kind, request_id="", **fields):
    with LOCK:
        value = {"seq": len(EVENTS), "time_ns": time.monotonic_ns(),
                 "event": kind, "id": request_id, **fields}
        EVENTS.append(value)
        print(json.dumps(value), flush=True)


class Control(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def respond(self, value, status=200):
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        with LOCK:
            self.respond({"events": list(EVENTS), "cases": {
                key: {"mode": item["mode"], "upstream": item["upstream"]}
                for key, item in CASES.items()}})

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        rid = data.get("id", "")
        with LOCK:
            if self.path == "/reset":
                for case in CASES.values():
                    case["redis_gate"].set()
                    case["upstream_gate"].set()
                CASES.clear()
                EVENTS.clear()
            elif self.path == "/prepare":
                if rid in CASES:
                    return self.respond({"error": "duplicate request id"}, 409)
                CASES[rid] = {"mode": data["mode"], "upstream": 0,
                              "redis_gate": threading.Event(),
                              "upstream_gate": threading.Event()}
                event("prepared", rid, mode=data["mode"],
                      key="higress-audit:" + rid, value=CACHED.decode())
            elif self.path == "/release-redis":
                event("redis_release_requested", rid)
                CASES[rid]["redis_gate"].set()
            elif self.path == "/release-upstream":
                CASES[rid]["upstream_gate"].set()
            elif self.path == "/client-complete":
                event("client_complete", rid, **data.get("result", {}))
            else:
                return self.respond({"error": "unknown control path"}, 404)
        self.respond({"ok": True})


class Upstream(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_GET(self):
        rid = self.headers.get("x-verification-id", "warmup")
        with LOCK:
            case = CASES.get(rid)
            if case is not None:
                case["upstream"] += 1
            event("upstream_seen", rid, headers=dict(self.headers))
        if case is not None and not case["upstream_gate"].wait(20):
            event("fixture_deadline", rid, source="upstream")
        try:
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(UPSTREAM)))
            self.end_headers()
            self.wfile.write(UPSTREAM)
        except (BrokenPipeError, ConnectionResetError):
            # Baseline hit forwards upstream but later returns the cache locally.
            event("upstream_peer_closed", rid)


class Redis(socketserver.StreamRequestHandler):
    def read_command(self):
        line = self.rfile.readline()
        if not line:
            return None
        if not line.startswith(b"*"):
            raise ValueError("expected RESP array")
        parts = []
        for _ in range(int(line[1:])):
            size = self.rfile.readline()
            if not size.startswith(b"$"):
                raise ValueError("expected RESP bulk string")
            parts.append(self.rfile.read(int(size[1:])))
            if self.rfile.read(2) != b"\r\n":
                raise ValueError("invalid RESP delimiter")
        return parts

    def handle(self):
        while True:
            parts = self.read_command()
            if parts is None:
                return
            command = parts[0].decode().upper()
            key = parts[1].decode() if len(parts) > 1 else ""
            rid = key.removeprefix("higress-audit:")
            event("redis_command", rid, command=command,
                  args=[p.decode() for p in parts[1:]])
            if command == "GET":
                with LOCK:
                    case = CASES.get(rid)
                if case is None:
                    event("unexpected_key", rid)
                    reply = b"-ERR unknown fixture key\r\n"
                else:
                    event("redis_get_seen", rid)
                    if not case["redis_gate"].wait(20):
                        event("fixture_deadline", rid, source="redis")
                        return
                    mode = case["mode"]
                    if mode == "hit":
                        reply = b"$" + str(len(CACHED)).encode() + b"\r\n" + CACHED + b"\r\n"
                    elif mode in ("miss", "timeout"):
                        reply = b"$-1\r\n"
                    elif mode == "empty":
                        reply = b"$0\r\n\r\n"
                    else:
                        reply = b"-ERR controlled asynchronous fixture error\r\n"
                    event("redis_reply_released", rid, mode=mode)
            elif command in ("SET", "SETEX", "AUTH", "SELECT", "CLIENT"):
                reply = b"+OK\r\n"
            elif command == "PING":
                reply = b"+PONG\r\n"
            else:
                event("unexpected_command", rid, command=command)
                reply = b"-ERR unsupported command\r\n"
            try:
                self.wfile.write(reply)
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                event("redis_peer_closed", rid)
                return


class RedisServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    for server in (RedisServer(("0.0.0.0", 6379), Redis),
                   ThreadingHTTPServer(("0.0.0.0", 8080), Upstream)):
        threading.Thread(target=server.serve_forever, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", 9000), Control).serve_forever()
