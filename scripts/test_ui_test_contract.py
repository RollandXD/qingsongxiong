#!/usr/bin/env python3
"""不用 Xcode 也能复现错误筛选和零测试假绿灯。"""
import unittest

from ui_test_contract import selection_argument, validate_result


class UIExecutionContractTests(unittest.TestCase):
    def test_default_selects_entire_ui_target(self):
        self.assertEqual(selection_argument(""), "-only-testing:QingSongXiongUITests")

    def test_suite_and_single_method_follow_apple_identifier_format(self):
        for selector in ("DesignUITests", "DesignUITests/testHomeShowsTwoChosenCardsAndTimeline"):
            self.assertEqual(selection_argument(selector), "-only-testing:QingSongXiongUITests/" + selector)

    def test_pipe_combination_is_rejected_before_building(self):
        with self.assertRaisesRegex(ValueError, "不能用"):
            selection_argument("DesignUITests/testOne|DesignUITests/testTwo")

    def test_unsafe_or_malformed_selector_is_rejected(self):
        for selector in ("-skip-testing:All", "A/B/C", "A/", " A", "A\nB"):
            with self.subTest(selector=selector), self.assertRaises(ValueError):
                selection_argument(selector)

    def test_zero_tests_even_with_success_marker_is_failure(self):
        log = "Executed 0 tests, with 0 failures (0 unexpected) in 0.000 seconds\n** TEST EXECUTE SUCCEEDED **"
        with self.assertRaisesRegex(ValueError, "0 条"):
            validate_result(log)

    def test_missing_or_failed_summary_is_failure(self):
        for log in ("** TEST EXECUTE SUCCEEDED **", "Executed 2 tests, with 1 failure (0 unexpected)"):
            with self.subTest(log=log), self.assertRaises(ValueError):
                validate_result(log)

    def test_final_summary_is_total_not_sum_of_nested_suites(self):
        log = "Executed 3 tests, with 0 failures\nExecuted 24 tests, with 0 failures\nExecuted 27 tests, with 0 failures"
        self.assertEqual(validate_result(log), 27)

    def test_successful_single_method_must_actually_be_present(self):
        selector = "DesignUITests/testHome"
        log = "Executed 1 test, with 0 failures"
        with self.assertRaisesRegex(ValueError, "没有通过记录"):
            validate_result(log, selector)
        log += "\nTest Case '-[QingSongXiongUITests.DesignUITests testHome]' passed (1.2 seconds)."
        self.assertEqual(validate_result(log, selector), 1)


if __name__ == "__main__":
    unittest.main()
