#!/usr/bin/env python3
"""编译前检查真实 import 与包依赖，保持功能边界可检查。"""
from pathlib import Path
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
rules = json.loads((ROOT / "architecture.json").read_text())
sources = ROOT / "Packages/BearKit/Sources"
errors = []
for directory in sorted(p for p in sources.iterdir() if p.is_dir()):
    if directory.name not in rules:
        errors.append(f"缺少模块规则：{directory.name}")
        continue
    for path in directory.rglob("*.swift"):
        imports = re.findall(r"^\s*(?:@\w+\s+)?import\s+(\w+)", path.read_text(), re.M)
        for module in imports:
            if module not in rules[directory.name]:
                errors.append(f"{path.relative_to(ROOT)} 不允许依赖 {module}")

if shutil.which("swift"):
    raw = subprocess.check_output(["swift", "package", "--package-path", str(ROOT / "Packages/BearKit"), "dump-package"], text=True)
    package = json.loads(raw)
    for target in package["targets"]:
        if target["name"] not in rules:
            continue
        for entry in target["dependencies"]:
            for value in entry.values():
                dependency = value[0]
                if dependency not in rules[target["name"]]:
                    errors.append(f"Package.swift：{target['name']} 非法依赖 {dependency}")

for path in (ROOT / "SharedUI").glob("*.swift"):
    imports = re.findall(r"^\s*import\s+(\w+)", path.read_text(), re.M)
    allowed = {"Foundation", "SwiftUI", "WidgetKit", "AIUsageDomain", "AIUsagePresentation", "BearDesignSystem"}
    for module in imports:
        if module not in allowed:
            errors.append(f"共享组件界面越层引用：{path.relative_to(ROOT)} -> {module}")

gate = json.loads((ROOT / "device-gate.json").read_text())
for path in (ROOT / "WidgetExtension").rglob("*.swift"):
    imports = re.findall(r"^\s*import\s+(\w+)", path.read_text(), re.M)
    for forbidden in {"AIUsageAuth", "AIUsageFeature", "AuthenticationServices", "WebKit"}:
        if forbidden in imports:
            errors.append(f"Widget 不得链接交互式授权或主 App 页面：{path.relative_to(ROOT)} -> {forbidden}")
if gate["status"] != "verified":
    forbidden = re.compile(r"backend-api/wham|api\.anthropic\.com|api\.deepseek\.com")
    for path in sources.rglob("*.swift"):
        if forbidden.search(path.read_text()):
            errors.append(f"真机门槛未通过，不得启用真实接口：{path.relative_to(ROOT)}")
if errors:
    raise SystemExit("\n".join(errors))
print(f"架构边界通过：{len(rules)} 个模块；真机状态：{gate['status']}")
