#!/usr/bin/env python3
"""Build versioned, self-contained envpilot archives and checksums."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [("linux", "amd64"), ("linux", "arm64"), ("linux", "armv7"), ("darwin", "amd64"), ("darwin", "arm64"), ("windows", "amd64"), ("windows", "arm64")]


def main():
    version = (ROOT / "VERSION").read_text().strip()
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    for system, arch in TARGETS:
        suffix = ".exe" if system == "windows" else ""
        name = f"envpilot-core-{version}-{system}-{arch}{suffix}"
        env = dict(os.environ, GOOS=system, GOARCH="arm" if arch == "armv7" else arch, CGO_ENABLED="0")
        if arch == "armv7":
            env["GOARM"] = "7"
        subprocess.run(["go", "build", "-trimpath", "-ldflags", f"-s -w -X main.version={version}", "-o", str(dist / name), "./cmd/envpilot-core"], cwd=ROOT, env=env, check=True)
        with tempfile.TemporaryDirectory(prefix="envpilot-package-") as directory:
            package = Path(directory) / f"envpilot-{version}"
            for relative in files:
                if not relative:
                    continue
                if relative.startswith("downloads/mihomo-") and not relative.startswith(f"downloads/mihomo-{system}-{arch}"):
                    continue
                source = ROOT / relative
                if not source.is_file():
                    continue
                dest = package / relative
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, dest)
            (package / "bin").mkdir(exist_ok=True)
            binary = package / "bin" / f"envpilot-core{suffix}"
            shutil.copyfile(dist / name, binary)
            binary.chmod(0o755)
            archive = dist / f"envpilot-{version}-{system}-{arch}"
            if system == "windows":
                with zipfile.ZipFile(str(archive) + ".zip", "w", zipfile.ZIP_DEFLATED) as output:
                    for item in sorted(package.rglob("*")):
                        if item.is_file():
                            output.write(item, item.relative_to(package.parent))
            else:
                with tarfile.open(str(archive) + ".tar.gz", "w:gz") as output:
                    def permissions(info):
                        # Windows chmod does not preserve executable bits for tar.
                        if info.name.endswith("/bin/envpilot-core"):
                            info.mode = 0o755
                        return info
                    output.add(package, arcname=package.name, filter=permissions)
    sums = []
    for file in sorted(dist.iterdir()):
        if file.is_file() and file.name != "SHA256SUMS":
            digest = hashlib.sha256()
            with file.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            sums.append(f"{digest.hexdigest()}  {file.name}\n")
    (dist / "SHA256SUMS").write_text("".join(sums), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
