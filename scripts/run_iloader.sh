#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$(python3 "$project_dir/scripts/download_iloader.py")"
if [[ "${1:-}" == '--check' ]]; then
  dependencies="$(ldd "$installer")"
  if [[ "$dependencies" == *'not found'* ]]; then
    printf '%s\n' "$dependencies" >&2
    exit 1
  fi
  printf '%s\n' 'Native installer checksum and system dependencies verified.' "$installer"
  exit 0
fi
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  printf '%s\n' '请在你自己的图形桌面终端运行本脚本。' >&2
  exit 2
fi
# 只影响该安装器进程；适配已遇到 WebKitGTK 图形问题的桌面。
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  export GDK_BACKEND=wayland
else
  export GDK_BACKEND=x11
fi
export WEBKIT_DISABLE_DMABUF_RENDERER=1
exec "$installer" "$@"
