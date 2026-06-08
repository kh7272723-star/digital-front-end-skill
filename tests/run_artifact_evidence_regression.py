#!/usr/bin/env python3
"""Regression tests for artifact budget and false-evidence gates."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PY = sys.executable


def run_cmd(args: list[str]) -> tuple[int, str]:
    env = os.environ.copy()
    env.setdefault("PYTHONIOENCODING", "utf-8")
    result = subprocess.run(
        [PY] + args,
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
    )
    return result.returncode, result.stdout + result.stderr


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def expect_fail(name: str, args: list[str], must_contain: list[str]) -> None:
    rc, output = run_cmd(args)
    if rc == 0:
        raise AssertionError(f"{name}: expected FAIL, got PASS\n{output}")
    for token in must_contain:
        if token not in output:
            raise AssertionError(f"{name}: missing token {token!r}\n{output}")
    print(f"[PASS] {name} rejected as expected")


def expect_pass(name: str, args: list[str]) -> None:
    rc, output = run_cmd(args)
    if rc != 0:
        raise AssertionError(f"{name}: expected PASS, got rc={rc}\n{output}")
    print(f"[PASS] {name} accepted")


def test_sim_log_semantic_contradictions(tmp: Path) -> None:
    wlast_log = tmp / "sim" / "shape_bad.log"
    write(wlast_log, """
TEST_START single_dma
CPL[1]: tag=1 status=0
Shape: AR=1 AW=1 W=1 R=1 B=1 WLAST=0 WSTRB=11111111
TEST_PASS single_dma
ALL_TESTS_PASS
SIMULATION_DONE
""")
    expect_fail(
        "sim_log_wlast_zero",
        ["scripts/sim_log_gate.py", str(wlast_log)],
        ["WLAST=0"],
    )

    dup_cpl_log = tmp / "sim" / "duplicate_cpl.log"
    write(dup_cpl_log, """
TEST_START single_dma
CPL[1]: tag=1 status=0
CPL[2]: tag=1 status=0
TEST_PASS single_dma
ALL_TESTS_PASS
SIMULATION_DONE
""")
    expect_fail(
        "sim_log_duplicate_completion",
        ["scripts/sim_log_gate.py", str(dup_cpl_log)],
        ["CPL[2]"],
    )

    ordered_cpl_log = tmp / "sim" / "ordered_cpl.log"
    write(ordered_cpl_log, """
TEST_START completion_ordering
Expected completions: 2
CPL[1]: tag=1 status=0
CPL[2]: tag=2 status=0
TEST_PASS completion_ordering
ALL_TESTS_PASS
SIMULATION_DONE
""")
    expect_pass("sim_log_expected_multi_completion",
                ["scripts/sim_log_gate.py", str(ordered_cpl_log)])


def test_rtl_style_fake_tb_checks(tmp: Path) -> None:
    tb = tmp / "tb" / "tb_fake_dma.v"
    write(tb, r"""
`default_nettype none
module tb_fake_dma;
  reg [31:0] awaddr;
  reg [7:0] awlen;
  reg wlast;
  integer cpl_count;
  initial begin
    awaddr = 32'h0;
    awlen = 8'hff;
    wlast = 1'b0;
    cpl_count = 2;
    if (awaddr !== 32'h0) ;
    if (awlen !== 8'hff) ;
    if (wlast !== 1'b1 && wlast !== 1'b0) $fatal;
    if (cpl_count < 1) $fatal;
    $display("ALL_TESTS_PASS");
    $finish;
  end
endmodule
`default_nettype wire
""")
    expect_fail(
        "rtl_style_empty_if_and_weak_wlast",
        ["scripts/rtl_style_check.py", str(tb)],
        ["TB_EMPTY_IF1", "TB_WLAST_BOOL1", "TB_CPL_COUNT1"],
    )


def test_artifact_budget_gate(tmp: Path) -> None:
    project = tmp / "artifact_bad"
    write(project / "tb_archive" / "tb_old.v", "module tb_old; endmodule\n")
    write(project / "sim" / "tb_top.vvp", "compiled\n")
    write(project / "sim" / "sim_addr_chan.log", "ALL_TESTS_PASS\nSIMULATION_DONE\n")
    write(project / "sim" / "sim_tb_addr_chan.log", "ALL_TESTS_PASS\nSIMULATION_DONE\n")
    write(project / "scripts" / "run_sim.py", "print('custom runner')\n")

    expect_fail(
        "artifact_budget_rejects_noncanonical_output",
        ["scripts/artifact_budget_gate.py", str(project)],
        ["tb_archive", ".vvp", "Duplicate simulation evidence", "scripts/run_sim.py"],
    )

    clean = tmp / "artifact_clean"
    write(clean / "tb" / "tb_leaf.v", "module tb_leaf; endmodule\n")
    write(clean / "sim" / "tb_leaf.log", "ALL_TESTS_PASS\nSIMULATION_DONE\n")
    expect_pass("artifact_budget_clean_project",
                ["scripts/artifact_budget_gate.py", str(clean)])


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="artifact_evidence_") as td:
        tmp = Path(td)
        test_sim_log_semantic_contradictions(tmp)
        test_rtl_style_fake_tb_checks(tmp)
        test_artifact_budget_gate(tmp)
    print("artifact/evidence regressions: PASS")


if __name__ == "__main__":
    main()
