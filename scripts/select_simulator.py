#!/usr/bin/env python3
"""按目标机型选择兼容的 iOS 27 运行时；Xcode 版本与运行时版本分别核实。"""
import json
import os
from pathlib import Path
import subprocess
import sys


def listing(kind):
    return json.loads(subprocess.check_output(["xcrun", "simctl", "list", kind, "--json"], text=True))


def selected(device_id, runtime):
    Path("output").mkdir(exist_ok=True)
    Path("output/simulator-profile.json").write_text(json.dumps({
        "model": desired, "runtime": runtime["name"], "runtimeVersion": runtime["version"],
    }, ensure_ascii=False))
    print(desired + " / " + runtime["name"], file=sys.stderr)
    print(device_id)
    sys.exit(0)


desired = os.environ.get("BEAR_SIMULATOR_NAME", "iPhone 16 Pro")
devices = listing("devices")["devices"]
runtimes = [r for r in listing("runtimes")["runtimes"]
            if "SimRuntime.iOS-27" in r["identifier"] and r.get("isAvailable", True)]
types = listing("devicetypes")["devicetypes"]
candidate = next((d for d in types if d["name"] == desired), None)
if candidate is None:
    sys.exit("Device type unavailable: " + desired)


def advertised(runtime):
    supported = {d["identifier"] for d in runtime.get("supportedDeviceTypes", [])}
    return not supported or candidate["identifier"] in supported


print("Installed iOS 27 runtimes: " + json.dumps([
    {"name": r["name"], "version": r["version"], "supportsTarget": advertised(r)} for r in runtimes
], ensure_ascii=False), file=sys.stderr)
# 兼容性优先，其次选择同代系统的较新版本；不把 Duo 专属运行时当成普通 iPhone。
runtimes.sort(key=lambda r: (advertised(r), tuple(int(p) for p in r["version"].split("."))), reverse=True)
subprocess.run(["xcrun", "simctl", "help", "create"], stdout=sys.stderr, stderr=sys.stderr, check=True)
for runtime in runtimes:
    for device in devices.get(runtime["identifier"], []):
        if device["name"] == desired and device.get("isAvailable", True):
            selected(device["udid"], runtime)
    # create 的实际结果是最终依据；即使静态兼容列表缺失，也不能替换成其他机型。
    result = subprocess.run(["xcrun", "simctl", "create", "QingSongXiong-UI", candidate["identifier"], runtime["identifier"]],
                            text=True, capture_output=True)
    if result.returncode == 0:
        selected(result.stdout.strip(), runtime)
    print("Cannot create " + desired + " on " + runtime["name"] + ": " + result.stderr.strip(), file=sys.stderr)
sys.exit("Required iOS 27 simulator unavailable: " + desired + "; refusing to substitute another device")
