#!/usr/bin/env python3
"""合成巡览剪辑合同；不调用媒体工具，不访问用户文件。"""
import unittest

from export_motion import tour_range


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


if __name__ == "__main__":
    unittest.main()
