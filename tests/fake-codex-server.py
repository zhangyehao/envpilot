"""Local WebSocket fixture; never connects to an upstream provider."""
import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import struct
import threading

path = Path(os.environ["CODEX_HOME"]) / "app-server-control/app-server-control.sock"
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
        connection.recv(4096)
        data = json.dumps({"id": 1, "result": {"userAgent": "codex-cli/" + os.environ.get("FAKE_CODEX_VERSION", "0.153.0")}}).encode()
        connection.sendall(bytes([0x81, len(data)]) + data)
    except (OSError, StopIteration):
        pass
    finally:
        connection.close()


while True:
    connection, _ = listener.accept()
    threading.Thread(target=handle, args=(connection,), daemon=True).start()
