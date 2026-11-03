#!/usr/bin/env python3
"""保留待重签 IPA 的权限声明，不接触 Apple 证书或用户账户。"""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

source, output = map(Path, sys.argv[1:3])
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="bear-payload-") as temporary:
    payload = Path(temporary) / "Payload"
    payload.mkdir()
    app = payload / source.name
    shutil.copytree(source, app, symlinks=True)
    # 临时 ad-hoc 签名仅携带待重签权限，不能装到真机，不是开发者签名。
    for bundle in [*app.glob("PlugIns/*.appex"), app]:
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        bundle_id = info["CFBundleIdentifier"]
        # SideStore 0.7.0 的 App ID 注册会直接使用基础显示名。
        # 校验真实构建产物：签名名称为英文，桌面品牌由本地化资源提供。
        for key in ("CFBundleDisplayName", "CFBundleName"):
            name = info[key]
            if not name or not name.isascii() or not all(c.isalnum() or c == " " for c in name):
                raise SystemExit(f"{bundle_id}: {key} must be an ASCII signing name")
        localized = plistlib.loads((bundle / "zh-Hans.lproj/InfoPlist.strings").read_bytes())
        expected_name = "轻松熊小组件" if bundle.suffix == ".appex" else "轻松熊"
        if localized.get("CFBundleDisplayName") != expected_name:
            raise SystemExit(f"{bundle_id}: localized brand name missing from built bundle")
        entitlements = {
            "application-identifier": "UNSIGNED00." + bundle_id,
            "com.apple.developer.team-identifier": "UNSIGNED00",
            "com.apple.security.application-groups": ["group.io.github.rollandxd.qingsongxiong"],
            "keychain-access-groups": ["UNSIGNED00.io.github.rollandxd.qingsongxiong.shared"],
        }
        path = Path(temporary) / (bundle_id + ".plist")
        path.write_bytes(plistlib.dumps(entitlements))
        subprocess.run(["codesign", "--force", "--sign", "-", "--entitlements", str(path), str(bundle)], check=True)
        subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)
    destination = output / "QingSongXiong-needs-signing.ipa"
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(payload.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(payload.parent))
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    (output / "SHA256SUMS.txt").write_text(f"{digest}  {destination.name}\n")
    (output / "build-status.json").write_text(json.dumps({
        "product": "QingSongXiong", "mode": info.get("BearBuildMode", "signing-verification"),
        "appleSigned": False, "requiresResigning": True,
        "deviceGate": json.loads((Path(__file__).resolve().parents[1] / "device-gate.json").read_text())["status"],
        "liveProvidersEnabled": bool(info.get("BearEnabledProviders", [])),
        "availableProviders": info.get("BearEnabledProviders", []),
    }, ensure_ascii=False, indent=2) + "\n")
    print(destination)
