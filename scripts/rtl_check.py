#!/usr/bin/env python3
"""Run an RTL fixture and compare the result with its manifest."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


def run_cmd(cmd: list[str], cwd: Path, timeout_seconds: int) -> tuple[int, str]:
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout_seconds,
        check=False,
    )
    return proc.returncode, proc.stdout


def excerpt(text: str, max_lines: int = 80) -> str:
    lines = text.splitlines()
    if len(lines) <= max_lines:
        return text
    keep_head = max_lines // 2
    keep_tail = max_lines - keep_head
    return "\n".join(lines[:keep_head] + ["... log truncated ..."] + lines[-keep_tail:])


def load_manifest(case_dir: Path) -> dict:
    manifest_path = case_dir / "manifest.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"Missing manifest: {manifest_path}")
    with manifest_path.open("r", encoding="utf-8") as f:
        return json.load(f)


def run_optional_verilator(
    case_dir: Path,
    sources: list[Path],
    testbench: Path,
    timeout_seconds: int,
) -> tuple[str, bool]:
    verilator = shutil.which("verilator")
    if not verilator:
        return "## verilator\nSKIP: verilator not found\n", True

    cmd = [
        verilator,
        "--lint-only",
        "--timing",
        "-Wall",
    ] + [str(p) for p in sources + [testbench]]
    rc, log = run_cmd(cmd, case_dir, timeout_seconds)
    return "## verilator\n" + log, rc == 0


def run_optional_yosys(
    case_dir: Path,
    sources: list[Path],
    timeout_seconds: int,
) -> tuple[str, bool]:
    yosys = shutil.which("yosys")
    if not yosys:
        return "## yosys\nSKIP: yosys not found\n", True

    script = "; ".join(
        ["read_verilog -sv " + " ".join(str(p) for p in sources), "hierarchy -check", "proc", "opt", "stat"]
    )
    rc, log = run_cmd([yosys, "-q", "-p", script], case_dir, timeout_seconds)
    return "## yosys\n" + log, rc == 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Run an RTL fixture with Icarus Verilog.")
    parser.add_argument("--case", required=True, help="Fixture directory containing manifest.json.")
    parser.add_argument(
        "--optional-tools",
        action="store_true",
        help="Also run Verilator lint and Yosys sanity checks when installed.",
    )
    args = parser.parse_args()

    case_dir = Path(args.case).resolve()
    manifest = load_manifest(case_dir)
    timeout_seconds = int(manifest.get("timeout_seconds", 10))

    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if not iverilog or not vvp:
        print("RTL_CHECK_RESULT: FAIL")
        print("Missing required tools: iverilog and vvp")
        return 1

    build_dir = case_dir / "build"
    build_dir.mkdir(exist_ok=True)
    output_path = build_dir / "sim.out"

    sources = [case_dir / src for src in manifest["sources"]]
    testbench = case_dir / manifest["testbench"]
    compile_cmd = [
        iverilog,
        "-g2012",
        "-s",
        manifest["top"],
        "-o",
        str(output_path),
    ] + [str(p) for p in sources + [testbench]]

    expected = manifest.get("expected", {})
    expected_result = expected.get("result", "pass")
    expected_contains = expected.get("contains", [])

    log_parts: list[str] = []
    optional_ok = True
    try:
        compile_rc, compile_log = run_cmd(compile_cmd, case_dir, timeout_seconds)
        log_parts.append("## compile")
        log_parts.append(compile_log)
        if compile_rc == 0:
            run_rc, run_log = run_cmd([vvp, str(output_path)], case_dir, timeout_seconds)
            log_parts.append("## run")
            log_parts.append(run_log)
        else:
            run_rc = 1
        if args.optional_tools and compile_rc == 0:
            verilator_log, verilator_ok = run_optional_verilator(
                case_dir, sources, testbench, timeout_seconds
            )
            yosys_log, yosys_ok = run_optional_yosys(case_dir, sources, timeout_seconds)
            log_parts.append(verilator_log)
            log_parts.append(yosys_log)
            optional_ok = verilator_ok and yosys_ok
    except subprocess.TimeoutExpired as exc:
        log_parts.append(f"TIMEOUT after {timeout_seconds}s: {exc}")
        compile_rc = 1
        run_rc = 1
        optional_ok = False

    combined_log = "\n".join(log_parts)
    actual_result = "pass" if compile_rc == 0 and run_rc == 0 else "fail"
    contains_ok = all(token in combined_log for token in expected_contains)
    result_ok = actual_result == expected_result and contains_ok and optional_ok

    print(f"CASE: {manifest.get('name', case_dir.name)}")
    print(f"EXPECTED_RESULT: {expected_result}")
    print(f"ACTUAL_RESULT: {actual_result}")
    print(f"EXPECTED_TOKENS_FOUND: {contains_ok}")
    if args.optional_tools:
        print(f"OPTIONAL_TOOL_CHECKS: {'PASS' if optional_ok else 'FAIL'}")
    print(f"RTL_CHECK_RESULT: {'PASS' if result_ok else 'FAIL'}")
    print("LOG_EXCERPT:")
    print(excerpt(combined_log).rstrip())
    return 0 if result_ok else 1


if __name__ == "__main__":
    sys.exit(main())
