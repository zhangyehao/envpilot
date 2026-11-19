"""Local WebSocket fixture; never connects to an upstream provider."""
import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import struct
import threading

path = Path(os.environ.get("FAKE_CODEX_SOCKET_HOME", os.environ["CODEX_HOME"])) / "app-server-control/app-server-control.sock"
path.parent.mkdir(parents=True, exist_ok=True)
if path.exists() or path.is_symlink():
    path.unlink()
bound_path = path
if os.environ.get("FAKE_CODEX_SOCKET_SYMLINK"):
    bound_path = path.parent / "node-local" / "control.sock"
    bound_path.parent.mkdir(parents=True, exist_ok=True)
    if bound_path.exists():
        bound_path.unlink()
listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
listener.bind(str(bound_path))
listener.listen(10)
if bound_path != path:
    path.symlink_to(bound_path.relative_to(path.parent) if os.environ["FAKE_CODEX_SOCKET_SYMLINK"] == "relative" else bound_path)


def handle(connection):
    try:
        connection.settimeout(4)
        request = b""
        while b"\r\n\r\n" not in request:
            data = connection.recv(4096)
            if not data:
                return
            request += data
        key = next(line.split(b":", 1)[1].strip() for line in request.split(b"\r\n") if line.lower().startswith(b"sec-websocket-key:"))
        accept = base64.b64encode(hashlib.sha1(key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest())
        connection.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n")
        with connection.makefile("rb") as frames:
            while True:
                header = frames.read(2)
                if len(header) != 2:
                    break
                length = header[1] & 127
                if length == 126:
                    length = struct.unpack("!H", frames.read(2))[0]
                elif length == 127:
                    length = struct.unpack("!Q", frames.read(8))[0]
                mask = frames.read(4)
                raw = frames.read(length)
                if len(mask) != 4 or len(raw) != length or header[0] & 15 != 1:
                    break
                request = json.loads(bytes(b ^ mask[i % 4] for i, b in enumerate(raw)))
                if "id" not in request:
                    continue
                activity_file = path.parent / "test-activity"
                activity = activity_file.read_text().strip() if activity_file.exists() else "idle"
                method = request["method"]
                if method == "initialize":
                    result = {"codexHome": os.environ["CODEX_HOME"], "userAgent": "codex-cli/" + os.environ.get("FAKE_CODEX_VERSION", "0.153.0")}
                elif method == "thread/loaded/list":
                    result = {"data": ["fixture-thread"]}
                elif method == "thread/read":
                    result = {"thread": {"status": {"type": activity}}}
                elif method == "model/list":
                    result = {"data": [{"id": "sample", "hidden": True}]}
                else:
                    break
                data = json.dumps({"id": request["id"], "result": result}).encode()
                frame = bytes([0x81, len(data)]) if len(data) < 126 else bytes([0x81, 126]) + struct.pack('!H', len(data))
                connection.sendall(frame + data)
    except (OSError, StopIteration):
        pass
    finally:
        connection.close()


while True:
    connection, _ = listener.accept()
    threading.Thread(target=handle, args=(connection,), daemon=True).start()
