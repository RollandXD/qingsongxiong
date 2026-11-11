#!/usr/bin/env python3
"""UI 验收合同：只接受单个 XCTest 标识，零测试或缺少结果必须失败。"""
import argparse
from pathlib import Path
import re


TARGET = "QingSongXiongUITests"


def selection_argument(selector: str) -> str:
    # Apple 的标识是 target/suite/method，不是正则；组合用例不得用 | 拼接。
    if selector and not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*(?:/[A-Za-z_][A-Za-z_0-9]*)?", selector):
        raise ValueError("UI 选择仅支持 Suite 或 Suite/testMethod；多条请运行整个 Suite，不能用 | 拼接")
    return "-only-testing:" + TARGET + ("/" + selector if selector else "")


def validate_result(log: str, selector: str = "") -> int:
    selection_argument(selector)
    summaries = re.findall(r"Executed\s+(\d+)\s+tests?, with\s+(\d+)\s+failures?", log)
    if not summaries:
        raise ValueError("缺少 XCTest 执行汇总，不能认定 UI 测试通过")
    count, failures = map(int, summaries[-1])
    if count == 0:
        raise ValueError("实际执行 0 条 UI 测试：拒绝假绿灯")
    if failures:
        raise ValueError(f"UI 测试有 {failures} 条失败")
    if "/" in selector:
        suite, method = selector.split("/")
        expected = f"Test Case '-[{TARGET}.{suite} {method}]' passed"
        if expected not in log:
            raise ValueError("指定的 UI 测试没有通过记录")
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("selection", "result"))
    parser.add_argument("--selector", default="")
    parser.add_argument("--log", type=Path)
    args = parser.parse_args()
    try:
        if args.mode == "selection":
            print(selection_argument(args.selector))
        else:
            if args.log is None:
                parser.error("result 需要 --log")
            count = validate_result(args.log.read_text(), args.selector)
            print(f"UI 执行合同通过：实际执行 {count} 条测试（不是仅看 xcodebuild 退出码）")
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + "\n")


if __name__ == "__main__":
    main()
