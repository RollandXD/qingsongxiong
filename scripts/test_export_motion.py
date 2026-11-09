#!/usr/bin/env python3
"""合成巡览剪辑合同；媒体工具可用时另验变帧率，不访问用户文件。"""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from export_motion import export, tour_range


class MotionRangeTests(unittest.TestCase):
    def test_complete_tour_keeps_small_context(self):
        bounds = tour_range("BEAR_MOTION_START 101.2\nBEAR_MOTION_END 104.4", 100)
        self.assertIsNotNone(bounds)
        self.assertAlmostEqual(bounds[0], 0.9)
        self.assertAlmostEqual(bounds[1], 3.8)

    def test_context_does_not_seek_before_first_frame(self):
        bounds = tour_range("BEAR_MOTION_START 100.1\nBEAR_MOTION_END 102", 100)
        self.assertEqual(bounds[0], 0)

    def test_failed_or_targeted_test_cannot_fabricate_a_tour(self):
        self.assertIsNone(tour_range("no tour in targeted run", 100))
        self.assertIsNone(tour_range("BEAR_MOTION_START 101.2", 100))

    def test_end_before_start_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "时间范围无效"):
            tour_range("BEAR_MOTION_START 103\nBEAR_MOTION_END 102", 100)

    def test_tour_before_real_recording_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "时间范围无效"):
            tour_range("BEAR_MOTION_START 99\nBEAR_MOTION_END 102", 100)


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "需要媒体工具验证真实帧时间")
class MotionFrameTests(unittest.TestCase):
    def test_variable_frames_are_retained_and_slow_timestamps_are_fourfold(self):
        with tempfile.TemporaryDirectory(prefix="bear-motion-") as directory:
            root = Path(directory)
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                            "testsrc2=size=128x128:rate=20:duration=12", "-vf",
                            "select='eq(n,0)+eq(n,80)+between(n,160,190)+eq(n,239)'",
                            "-fps_mode", "vfr", "-c:v", "libx264", "-metadata",
                            "creation_time=2026-11-09T00:00:00Z", str(root / "native-motion.mp4")], check=True)
            (root / "recording.json").write_text(json.dumps({"data": "synthetic"}))
            (root / "ui-tests.log").write_text("BEAR_MOTION_START 1794182400.3\nBEAR_MOTION_END 1794182411.7")
            with patch("export_motion.subprocess.run", wraps=subprocess.run) as invoked:
                export(root)
            encodes = [call.args[0] for call in invoked.call_args_list if "-c:v" in call.args[0]]
            self.assertEqual(len(encodes), 2)
            for command in encodes:
                self.assertEqual(command[command.index("-fps_mode") + 1], "vfr")
                self.assertEqual(command[command.index("-enc_time_base") + 1], "demux")

            def timestamps(name):
                result = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_frames",
                                         "-show_entries", "frame=best_effort_timestamp_time", "-of", "json",
                                         str(root / name)], check=True, capture_output=True, text=True)
                return [float(frame["best_effort_timestamp_time"]) for frame in json.loads(result.stdout)["frames"]]

            source = timestamps("native-motion.mp4")
            normal = timestamps("motion-tour-1x.mp4")
            slow = timestamps("motion-tour-025x.mp4")
            self.assertGreater(len(source), 30)
            self.assertEqual(len(normal), len(source))
            self.assertEqual(len(slow), len(normal))
            self.assertGreater(normal[1] - normal[0], 3)
            for original, slowed in zip(normal, slow):
                self.assertAlmostEqual(slowed - slow[0], 4 * (original - normal[0]), delta=0.01)
            self.assertEqual(json.loads((root / "motion-tour.json").read_text())["frameTiming"], "variable-preserved")


if __name__ == "__main__":
    unittest.main()
