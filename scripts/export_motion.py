#!/usr/bin/env python3
"""只截取合成 UI 巡览区间，导出原速和 0.25× 影片；不访问用户数据。"""
import json
from datetime import datetime
from pathlib import Path
import re
import shutil
import subprocess
import sys


def tour_range(log: str, recording_start: float) -> tuple[float, float] | None:
    start = re.search(r"BEAR_MOTION_START\s+(\d+(?:\.\d+)?)", log)
    end = re.search(r"BEAR_MOTION_END\s+(\d+(?:\.\d+)?)", log)
    if not start or not end:
        return None
    first, last = float(start[1]), float(end[1])
    if first < recording_start or last <= first:
        raise ValueError("动效巡览时间范围无效")
    return max(0, first - recording_start - 0.3), last - first + 0.6


def export(directory: Path) -> None:
    log = directory / "ui-tests.log"
    source = directory / "native-motion.mp4"
    metadata = directory / "recording.json"
    if not all(path.is_file() for path in (log, source, metadata)):
        print("尚无完整合成 UI 录像，未导出动效影片。")
        return
    recording = json.loads(metadata.read_text())
    if recording.get("data") != "synthetic":
        raise SystemExit("只允许导出声明为合成数据的 UI 录像。")
    if not shutil.which("ffprobe"):
        raise SystemExit("动效影片需要 ffprobe 校准真实首帧时间。")
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format_tags=creation_time", "-of", "json", str(source)],
                           check=True, capture_output=True, text=True)
    created = json.loads(probe.stdout).get("format", {}).get("tags", {}).get("creation_time")
    if not created:
        raise SystemExit("原始 MP4 缺少 creation_time，不能用进程启动时间猜测首帧。")
    recording_start = datetime.fromisoformat(created.replace("Z", "+00:00")).timestamp()
    bounds = tour_range(log.read_text(errors="replace"), recording_start)
    if bounds is None:
        print("本次没有完成动效巡览（定向测试或测试失败），不伪造影片。")
        return
    if not shutil.which("ffmpeg"):
        raise SystemExit("动效影片需要 ffmpeg；未导出原速/慢放影片。")
    subprocess.run(["ffmpeg", "-version"], check=True, stdout=subprocess.DEVNULL)
    common = ["-an", "-c:v", "libx264", "-preset", "fast", "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
    normal = directory / "motion-tour-1x.mp4"
    slow = directory / "motion-tour-025x.mp4"
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-ss", str(bounds[0]), "-i", str(source),
                    "-t", str(bounds[1]), *common, str(normal)], check=True)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(normal),
                    "-vf", "setpts=4*(PTS-STARTPTS)", *common, str(slow)], check=True)
    (directory / "motion-tour.json").write_text(json.dumps({"data": "synthetic", "offset": bounds[0],
        "duration": bounds[1], "recordingCreationTime": created, "speeds": [1, 0.25], "files": [normal.name, slow.name]}, indent=2) + "\n")
    print("已导出合成动效巡览：1× 与 0.25×，未变更原始录像。")


if __name__ == "__main__":
    export(Path(sys.argv[1] if len(sys.argv) > 1 else "output"))
