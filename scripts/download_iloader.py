#!/usr/bin/env python3
"""提取固定版本官方原生程序，避开 AppImage 自带图形库与启动钩子。"""
from pathlib import Path
import hashlib
import shutil
import subprocess
import tempfile
import urllib.request

root = Path(__file__).resolve().parents[1]
directory = root / ".local-tools"
directory.mkdir(exist_ok=True)
installation = directory / "iloader-native-2.4.1"
binary = installation / "usr/bin/iloader"
binary_digest = "ce84b5ea1b209606a4c1b3922886687a7b637a51defcbfa660033d832b4d9a83"
package = directory / "iloader-2.4.1-amd64.deb"
package_digest = "93f1e66c173a47925704c4757c137e766ffa5133aec1f4176d831ff78529e979"
url = "https://github.com/nab138/iloader/releases/download/v2.4.1/iloader-linux-amd64.deb"

def matches(path: Path, digest: str) -> bool:
    return path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == digest

if installation.exists():
    if not matches(binary, binary_digest):
        raise SystemExit("Existing native installer differs; stop without overwriting")
    print(binary)
    raise SystemExit(0)
if package.exists() and not matches(package, package_digest):
    raise SystemExit("Existing package differs; stop without overwriting")
if not package.exists():
    with tempfile.NamedTemporaryFile(dir=directory, delete=False) as temporary:
        pending = Path(temporary.name)
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                shutil.copyfileobj(response, temporary)
        except BaseException:
            pending.unlink(missing_ok=True)
            raise
    if not matches(pending, package_digest):
        pending.unlink()
        raise SystemExit("Official package checksum mismatch")
    if package.exists():
        pending.unlink()
        raise SystemExit("Package appeared while downloading; stop without overwriting")
    pending.rename(package)
with tempfile.TemporaryDirectory(prefix="iloader-extract-", dir=directory) as temporary:
    staging = Path(temporary)
    subprocess.run(["bsdtar", "-xf", str(package), "-C", str(staging)], check=True)
    native = staging / "native"
    native.mkdir()
    subprocess.run(["bsdtar", "-xf", str(staging / "data.tar.gz"), "-C", str(native)], check=True)
    if not matches(native / "usr/bin/iloader", binary_digest):
        raise SystemExit("Extracted native binary checksum mismatch")
    if installation.exists():
        raise SystemExit("Native installation appeared while extracting; stop")
    native.rename(installation)
binary.chmod(0o755)
print(binary)
