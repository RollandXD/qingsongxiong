#!/usr/bin/env python3
"""仅检查项目源码，不读取用户凭据目录。"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
errors = []
patterns = [
    re.compile(r"gh[pousr]_[A-Za-z0-9]{24,}"),
    re.compile(r"github_pat_[A-Za-z0-9_]{30,}"),
    re.compile(r"sk-(?:ant-|proj-)?[A-Za-z0-9_-]{24,}"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
]
for path in root.rglob("*"):
    if not path.is_file() or any(part in {".git", ".build", ".swiftpm", "output", "DerivedData"} or part.endswith(".xcodeproj") for part in path.parts):
        continue
    if path.suffix.lower() in {".p12", ".p8", ".mobileprovision", ".pem"}:
        errors.append(f"禁止提交签名或凭据文件：{path.relative_to(root)}")
    if path.stat().st_size > 2_000_000:
        continue
    try:
        text = path.read_text()
    except UnicodeError:
        continue
    if any(pattern.search(text) for pattern in patterns):
        errors.append(f"疑似凭据，请人工检查：{path.relative_to(root)}")
if errors:
    raise SystemExit("\n".join(errors))
print("源码凭据检查通过")
