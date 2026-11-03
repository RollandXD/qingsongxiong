#!/usr/bin/env python3
"""下载固定版本官方 Linux 安装器；仅保存在忽略目录，不运行或收集账号。"""
from pathlib import Path
import hashlib
import shutil
import tempfile
import urllib.request

root = Path(__file__).resolve().parents[1]
directory = root / ".local-tools"
directory.mkdir(exist_ok=True)
destination = directory / "iloader-2.4.1.AppImage"
checksum = "defa76e4fc3e7cfa2e60888288e14d076e6a99cc50b38da2d86562817bcd4663"
url = "https://github.com/nab138/iloader/releases/download/v2.4.1/iloader-linux-amd64.AppImage"
if destination.exists():
    if hashlib.sha256(destination.read_bytes()).hexdigest() != checksum:
        raise SystemExit("Existing installer has a different checksum; stop without overwriting")
else:
    with tempfile.NamedTemporaryFile(dir=directory, delete=False) as temporary:
        pending = Path(temporary.name)
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                shutil.copyfileobj(response, temporary)
        except BaseException:
            pending.unlink(missing_ok=True)
            raise
    if hashlib.sha256(pending.read_bytes()).hexdigest() != checksum:
        pending.unlink()
        raise SystemExit("Official installer checksum mismatch")
    if destination.exists():
        pending.unlink()
        raise SystemExit("Installer appeared while downloading; stop without overwriting")
    pending.rename(destination)
destination.chmod(0o755)
print(destination)
