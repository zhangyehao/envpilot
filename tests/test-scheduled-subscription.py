"""Exercise scheduled refresh with an isolated HOME, a loopback provider and the real Mihomo validator."""

import datetime
import gzip
import http.server
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import threading


def main():
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        return
    repo = Path(__file__).resolve().parents[1]
    payload = b'proxies: []\nproxy-groups:\n  - {name: Scheduled, type: select, proxies: [DIRECT]}\nrules: ["MATCH,DIRECT"]\n'
    requests = []

    class Provider(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *_):
            pass

    with tempfile.TemporaryDirectory() as temp, http.server.ThreadingHTTPServer(("127.0.0.1", 0), Provider) as provider:
        threading.Thread(target=provider.serve_forever, daemon=True).start()
        home = Path(temp)
        cfg = home / ".config/envpilot"
        cfg.mkdir(parents=True)
        mihomo = home / ".config/mihomo"
        mihomo.mkdir()
        ref = mihomo / "subscription.url"
        ref.write_text(f"http://127.0.0.1:{provider.server_port}/test-private-reference\n")
        ref.chmod(0o600)
        binary = home / "software/mihomo/mihomo"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(gzip.decompress(next((repo / "downloads").glob("mihomo-linux-amd64-*.gz")).read_bytes()))
        binary.chmod(0o700)
        now = datetime.datetime.now(datetime.timezone.utc)
        start = (now - datetime.timedelta(minutes=10)).strftime("%H:%M")
        end = (now + datetime.timedelta(minutes=10)).strftime("%H:%M")
        (cfg / "config.yaml").write_text(
            f"language: en\nupdates:\n  components: []\n  envpilot: false\n  timezone: UTC\n"
            f"  window_start: '{start}'\n  window_end: '{end}'\n"
            "  models: {enabled: false}\n  subscription: {enabled: true, interval_days: 3}\n"
        )
        env = dict(PATH=os.environ["PATH"], HOME=str(home), ENVPILOT_CONFIG_DIR=str(cfg), ENVPILOT_MODE="online",
                   ENVPILOT_LANG="en", USER="envpilotfixture", HOSTNAME=home.name)
        env["ENVPILOT_CORE"] = os.environ.get("ENVPILOT_CORE", str(repo / "bin/envpilot-core"))

        def cli(*args):
            run = subprocess.run(["bash", str(repo / "envpilot.sh"), *args], env=env, cwd=temp,
                                 capture_output=True, text=True, timeout=90)
            if run.returncode:
                raise RuntimeError(f"{args}: {run.stderr}")
            return run.stdout

        cli("updates", "check", "--json")
        assert not requests
        cli("updates", "tick")
        cli("updates", "tick")
        assert requests == ["/test-private-reference"], requests
        # The installer also writes the configured controller and proxy ports.
        assert "Scheduled" in (mihomo / "config.yaml").read_text()
        status = json.loads(cli("doctor", "--json"))
        assert status["scheduler"]["last_outcome"] == "ok", status
        assert status["results"][0]["status"] == "refreshed", status
        history = json.loads(cli("updates", "history", "--component", "subscription", "--json"))
        assert len(history) == 1 and history[0]["origin"] == "automatic" and history[0]["status"] == "refreshed", history
        for f in (cfg / "updates").rglob("*"):
            if f.is_file():
                assert b"/test-private-reference" not in f.read_bytes(), f
        provider.shutdown()


if __name__ == "__main__":
    main()
