#!/usr/bin/env python3
"""选择本次 CI 的普通 iPhone；没有预创建设备时使用已安装的设备类型创建。"""
import json
import subprocess
import sys


def listing(kind):
    return json.loads(subprocess.check_output(["xcrun", "simctl", "list", kind, "--json"], text=True))


devices = listing("devices")["devices"]
runtimes = listing("runtimes")["runtimes"]
runtime = next((r for r in runtimes if "iOS-27-1" in r["identifier"] and r.get("isAvailable", True)), None)
if runtime is None:
    sys.exit("iOS 27.1 runtime unavailable")
phones = [d for d in devices.get(runtime["identifier"], []) if d["name"].startswith("iPhone") and d.get("isAvailable", True)]
preferred_names = ["iPhone 18 Pro", "iPhone 17 Pro", "iPhone 18", "iPhone 17", "iPhone 16 Pro", "iPhone 16"]
for name in preferred_names:
    if device := next((d for d in phones if d["name"] == name), None):
        print(device["name"], file=sys.stderr)
        print(device["udid"])
        sys.exit(0)

types = listing("devicetypes")["devicetypes"]
supported = {d["identifier"] for d in runtime.get("supportedDeviceTypes", [])}
subprocess.run(["xcrun", "simctl", "help", "create"], stdout=sys.stderr, stderr=sys.stderr, check=True)
for name in preferred_names:
    candidate = next((d for d in types if d["name"] == name and (not supported or d["identifier"] in supported)), None)
    if candidate is None:
        continue
    result = subprocess.run(["xcrun", "simctl", "create", "QingSongXiong-UI", candidate["identifier"], runtime["identifier"]],
                            text=True, capture_output=True)
    if result.returncode == 0:
        print("Created " + name, file=sys.stderr)
        print(result.stdout.strip())
        sys.exit(0)
    print("Cannot create " + name + ": " + result.stderr.strip(), file=sys.stderr)

# 仍可使用预创建设备；录像始终显式指定 primary 显示屏。
if phones:
    print("Fallback: " + phones[0]["name"], file=sys.stderr)
    print(phones[0]["udid"])
else:
    sys.exit("No compatible iPhone simulator available")
