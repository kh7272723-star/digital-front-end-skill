#!/usr/bin/env python3
"""Workflow gate regression runner.

Copies fixtures to temporary directories and runs workflow_gate.py against
each one, verifying the expected PASS/FAIL outcome.  Uses --force to skip
predecessor-chain checks so each gate's own logic is tested in isolation.

Usage:
    python tests/run_workflow_gate_regression.py
    python tests/run_workflow_gate_regression.py --verbose
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent.parent / "scripts"
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"

TEST_CASES = [
    {
        "name": "premature_tb_before_post_rtl",
        "phase": "post-rtl",
        "expect_pass": False,
        "expect_texts": [
            "premature TB/sim artifacts found before first post-rtl PASS",
        ],
    },
    {
        "name": "parameterized_integration_tb",
        "phase": "pre-integration",
        "expect_pass": False,
        "expect_texts": [
            "PRE_INTEGRATION",
        ],
    },
    {
        "name": "fake_pass_matrix_failed_log",
        "phase": "pre-integration",
        "expect_pass": False,
        "expect_texts": [
            "FAIL/FATAL/timeout evidence",
        ],
    },
    {
        "name": "clean_l2_per_module_then_integration",
        "phase": "pre-integration",
        "expect_pass": True,
        "expect_texts": [],
    },
    {
        "name": "weak_compile_log_no_marker",
        "phase": "post-rtl",
        "expect_pass": False,
        "expect_texts": [
            "lacks RTL-only marker",
            "lacks compile success evidence",
            "COMPILE_RTL_ONLY",
        ],
    },
]


def _run_workflow_gate(project_dir: str, phase: str, force: bool = True
                       ) -> tuple[int, str]:
    """Run workflow_gate.py and return (returncode, combined_output)."""
    cmd = [
        sys.executable,
        str(SCRIPT_DIR / "workflow_gate.py"),
        "--phase", phase,
    ]
    if force:
        cmd.append("--force")
    cmd.append(project_dir)

    env = os.environ.copy()
    env.setdefault("PYTHONIOENCODING", "utf-8")
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
    )
    output = result.stdout
    if result.stderr:
        output += "\n" + result.stderr
    return result.returncode, output


def _run_final_delivery_gate(project_dir: str) -> tuple[int, str]:
    """Run final_delivery_gate.py and return (returncode, combined_output)."""
    cmd = [
        sys.executable,
        str(SCRIPT_DIR / "final_delivery_gate.py"),
        project_dir,
    ]
    env = os.environ.copy()
    env.setdefault("PYTHONIOENCODING", "utf-8")
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
    )
    output = result.stdout
    if result.stderr:
        output += "\n" + result.stderr
    return result.returncode, output


def _clear_sim_dir(project_dir: str) -> None:
    """Remove sim artifacts from a copied fixture."""
    sim_dir = Path(project_dir) / "sim"
    sim_dir.mkdir(exist_ok=True)
    for item in sim_dir.iterdir():
        if item.is_file():
            item.unlink()


def _add_rtl_only_compile_log(project_dir: str) -> None:
    """Add hard RTL-only compile evidence to a copied fixture."""
    log_path = Path(project_dir) / "sim" / "compile_rtl.log"
    log_path.parent.mkdir(exist_ok=True)
    log_path.write_text(
        "# COMPILE_RTL_ONLY\nCOMPILE_PASS\n0 errors\n",
        encoding="utf-8",
    )


def run_test(test_case: dict, verbose: bool = False) -> tuple[bool, str]:
    """Run a single test case. Returns (ok, message)."""
    fixture = FIXTURES_DIR / test_case["name"]
    if not fixture.exists():
        return False, f"Fixture directory not found: {fixture}"

    with tempfile.TemporaryDirectory() as tmpdir:
        proj_dir = os.path.join(tmpdir, test_case["name"])
        shutil.copytree(str(fixture), proj_dir)

        rc, output = _run_workflow_gate(proj_dir, test_case["phase"], force=True)
        actual_pass = rc == 0
        expected_pass = test_case["expect_pass"]

        if verbose:
            print(f"  --- workflow_gate output ({len(output)} chars) ---")
            for line in output.splitlines()[:40]:
                print(f"  | {line}")
            if len(output.splitlines()) > 40:
                print(f"  | ... ({len(output.splitlines()) - 40} more lines)")

        if actual_pass != expected_pass:
            return False, (
                f"Expected {'PASS' if expected_pass else 'FAIL'} (rc=0), "
                f"got {'PASS' if actual_pass else 'FAIL'} (rc={rc})"
            )

        if not expected_pass:
            for expected_text in test_case.get("expect_texts", []):
                if expected_text not in output:
                    return False, (
                        f"FAIL as expected but missing expected text "
                        f"'{expected_text}' in output"
                    )

        return True, "OK"


def run_post_rtl_rerun_after_tb(verbose: bool = False) -> tuple[bool, str]:
    """post-rtl can be re-run after TB exists when it already passed once."""
    fixture = FIXTURES_DIR / "premature_tb_before_post_rtl"
    with tempfile.TemporaryDirectory() as tmpdir:
        proj_dir = os.path.join(tmpdir, "post_rtl_rerun_after_tb")
        shutil.copytree(str(fixture), proj_dir)

        tb_dir = Path(proj_dir) / "tb"
        saved_tbs = {}
        for tb_file in tb_dir.glob("*"):
            saved_tbs[tb_file.name] = tb_file.read_text(encoding="utf-8")
            tb_file.unlink()

        state_file = Path(proj_dir) / "docs" / "workflow_state.json"
        if state_file.exists():
            state_file.unlink()

        rc1, out1 = _run_workflow_gate(proj_dir, "post-rtl", force=True)
        if rc1 != 0:
            if verbose:
                print(out1)
            return False, "initial post-rtl without TB should PASS"

        tb_dir.mkdir(exist_ok=True)
        for name, text in saved_tbs.items():
            (tb_dir / name).write_text(text, encoding="utf-8")

        rc2, out2 = _run_workflow_gate(proj_dir, "post-rtl", force=True)
        if verbose:
            print(out2)
        if rc2 != 0:
            return False, "post-rtl re-run after TB exists should PASS"
        return True, "OK"


def run_success_no_marker_rejected(verbose: bool = False) -> tuple[bool, str]:
    """A compile log with success text but no RTL-only marker must fail."""
    fixture = FIXTURES_DIR / "weak_compile_log_no_marker"
    with tempfile.TemporaryDirectory() as tmpdir:
        proj_dir = os.path.join(tmpdir, "success_no_marker")
        shutil.copytree(str(fixture), proj_dir)
        log_path = Path(proj_dir) / "sim" / "compile.log"
        log_path.write_text(
            "compilation successful\n0 errors\n",
            encoding="utf-8",
        )
        rc, output = _run_workflow_gate(proj_dir, "post-rtl", force=True)
        if verbose:
            print(output)
        if rc == 0:
            return False, "success-only compile log without marker should FAIL"
        if "lacks RTL-only marker" not in output:
            return False, "missing RTL-only marker finding"
        return True, "OK"


def run_invalid_marker_rejected(verbose: bool = False) -> tuple[bool, str]:
    """A negated marker such as NO_COMPILE_RTL_ONLY must not match."""
    fixture = FIXTURES_DIR / "weak_compile_log_no_marker"
    with tempfile.TemporaryDirectory() as tmpdir:
        proj_dir = os.path.join(tmpdir, "invalid_marker")
        shutil.copytree(str(fixture), proj_dir)
        log_path = Path(proj_dir) / "sim" / "compile.log"
        log_path.write_text(
            "# NO_COMPILE_RTL_ONLY\ncompilation successful\n0 errors\n",
            encoding="utf-8",
        )
        rc, output = _run_workflow_gate(proj_dir, "post-rtl", force=True)
        if verbose:
            print(output)
        if rc == 0:
            return False, "negated compile marker should FAIL"
        if "lacks RTL-only marker" not in output:
            return False, "missing RTL-only marker finding"
        return True, "OK"


def run_bom_marker_accepted(verbose: bool = False) -> tuple[bool, str]:
    """A UTF-8 BOM before COMPILE_RTL_ONLY must not hide the marker."""
    fixture = FIXTURES_DIR / "weak_compile_log_no_marker"
    with tempfile.TemporaryDirectory() as tmpdir:
        proj_dir = os.path.join(tmpdir, "bom_marker")
        shutil.copytree(str(fixture), proj_dir)
        log_path = Path(proj_dir) / "sim" / "compile.log"
        log_path.write_text(
            "\ufeff# COMPILE_RTL_ONLY\nCOMPILE_PASS\n0 errors\n",
            encoding="utf-8",
        )
        rc, output = _run_workflow_gate(proj_dir, "post-rtl", force=True)
        if verbose:
            print(output)
        if rc != 0:
            return False, "BOM-prefixed RTL-only marker should PASS"
        return True, "OK"


def run_parameterized_leaf_tb_not_integration(verbose: bool = False
                                             ) -> tuple[bool, str]:
    """A parameterized leaf-module TB must not be classified as integration TB."""
    fixture = FIXTURES_DIR / "clean_l2_per_module_then_integration"
    with tempfile.TemporaryDirectory() as tmpdir:
        proj_dir = os.path.join(tmpdir, "parameterized_leaf_tb")
        shutil.copytree(str(fixture), proj_dir)
        tb_dir = Path(proj_dir) / "tb"
        tb_dir.mkdir(exist_ok=True)
        (tb_dir / "tb_pipeline_stage.v").write_text(
            """
module tb_pipeline_stage;
    reg clk_i;
    reg rst_ni;
    reg valid_i;
    reg [7:0] data_i;
    wire ready_o;
    wire valid_o;
    wire [7:0] data_o;

    pipeline_stage #(.WIDTH(8)) inst_dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .valid_i(valid_i),
        .data_i(data_i),
        .ready_o(ready_o),
        .valid_o(valid_o),
        .data_o(data_o)
    );
endmodule
""".lstrip(),
            encoding="utf-8",
        )
        rc, output = _run_workflow_gate(proj_dir, "pre-integration", force=True)
        if verbose:
            print(output)
        if rc != 0:
            return False, "parameterized leaf TB should not fail pre-integration"
        return True, "OK"


def run_l2_post_sim_requires_pre_integration(verbose: bool = False
                                              ) -> tuple[bool, str]:
    """L2 post-sim must require pre-integration without filename heuristics."""
    fixture = FIXTURES_DIR / "clean_l2_per_module_then_integration"
    with tempfile.TemporaryDirectory() as tmpdir:
        proj_dir = os.path.join(tmpdir, "l2_post_sim_requires_pre_integration")
        shutil.copytree(str(fixture), proj_dir)
        docs_dir = Path(proj_dir) / "docs"
        state = {
            "schema_version": 1,
            "level": "L2",
            "phases": {
                "post-rtl": {
                    "status": "PASS",
                    "timestamp": "2026-06-06T00:00:00Z",
                    "command": "fixture",
                    "evidence": "fixture post-rtl pass",
                }
            },
        }
        (docs_dir / "workflow_state.json").write_text(
            json.dumps(state, indent=2) + "\n",
            encoding="utf-8",
        )
        sim_dir = Path(proj_dir) / "sim"
        sim_dir.mkdir(exist_ok=True)
        (sim_dir / "dma_sim.log").write_text(
            "ALL_TESTS_PASS\nSIMULATION_DONE\n",
            encoding="utf-8",
        )
        rc, output = _run_workflow_gate(proj_dir, "post-sim", force=False)
        if verbose:
            print(output)
        if rc == 0:
            return False, "L2 post-sim without pre-integration should FAIL"
        if "pre-integration" not in output:
            return False, "missing pre-integration predecessor finding"
        return True, "OK"


def run_post_rtl_pass_prints_l2_navigation(verbose: bool = False
                                           ) -> tuple[bool, str]:
    """L2 post-rtl PASS must tell the agent to avoid integration TB."""
    fixture = FIXTURES_DIR / "clean_l2_per_module_then_integration"
    with tempfile.TemporaryDirectory() as tmpdir:
        proj_dir = os.path.join(tmpdir, "post_rtl_l2_navigation")
        shutil.copytree(str(fixture), proj_dir)
        _clear_sim_dir(proj_dir)
        _add_rtl_only_compile_log(proj_dir)

        rc, output = _run_workflow_gate(proj_dir, "post-rtl", force=True)
        if verbose:
            print(output)
        if rc != 0:
            return False, "L2 post-rtl should PASS after RTL-only evidence"
        required = [
            "NEXT_WORKFLOW_STEP: Step 8 no-TB review, then Step 9 L2 per-module verification",
            "NEXT_REQUIRED_ACTION: complete Step 8/8c/8b without TB; first TB-producing step is Step 9 per-module TB + sim",
            "FORBIDDEN_NEXT_ACTION: do not create or run integration TB before pre-integration/module-sim gate PASS",
            "NEXT_REQUIRED_COMMAND: python scripts/workflow_gate.py --phase pre-integration",
        ]
        for text in required:
            if text not in output:
                return False, f"missing post-rtl navigation text: {text}"
        return True, "OK"


def run_pre_integration_pass_allows_integration(verbose: bool = False
                                                ) -> tuple[bool, str]:
    """pre-integration PASS must explicitly allow integration TB next."""
    fixture = FIXTURES_DIR / "clean_l2_per_module_then_integration"
    with tempfile.TemporaryDirectory() as tmpdir:
        proj_dir = os.path.join(tmpdir, "pre_integration_navigation")
        shutil.copytree(str(fixture), proj_dir)

        rc, output = _run_workflow_gate(proj_dir, "pre-integration", force=True)
        if verbose:
            print(output)
        if rc != 0:
            return False, "clean L2 pre-integration fixture should PASS"
        required = [
            "NEXT_WORKFLOW_STEP: Step 10 integration verification",
            "INTEGRATION_TB_ALLOWED: yes",
            "NEXT_REQUIRED_ACTION: write integration TB/assertions",
            "NEXT_REQUIRED_COMMAND: python scripts/workflow_gate.py --phase post-sim",
        ]
        for text in required:
            if text not in output:
                return False, f"missing pre-integration navigation text: {text}"
        return True, "OK"


def run_module_sim_alias_matches_pre_integration(verbose: bool = False
                                                 ) -> tuple[bool, str]:
    """module-sim is a semantic alias for pre-integration."""
    fixture = FIXTURES_DIR / "clean_l2_per_module_then_integration"
    with tempfile.TemporaryDirectory() as tmpdir:
        proj_dir = os.path.join(tmpdir, "module_sim_alias")
        shutil.copytree(str(fixture), proj_dir)

        rc, output = _run_workflow_gate(proj_dir, "module-sim", force=True)
        if verbose:
            print(output)
        if rc != 0:
            return False, "module-sim alias should PASS on clean pre-integration fixture"
        if "CURRENT_STEP_COMPLETED: Step 9-EXIT module-sim / pre-integration gate" not in output:
            return False, "module-sim alias did not print module-sim/pre-integration guidance"
        state_file = Path(proj_dir) / "docs" / "workflow_state.json"
        state = json.loads(state_file.read_text(encoding="utf-8"))
        if state.get("phases", {}).get("pre-integration", {}).get("status") != "PASS":
            return False, "module-sim alias should stamp canonical pre-integration phase"
        return True, "OK"


def run_l2_direct_integration_tb_after_post_rtl_fails(verbose: bool = False
                                                       ) -> tuple[bool, str]:
    """L2 integration TB created after post-rtl but before module sim must fail."""
    fixture = FIXTURES_DIR / "clean_l2_per_module_then_integration"
    with tempfile.TemporaryDirectory() as tmpdir:
        proj_dir = os.path.join(tmpdir, "direct_integration_tb_after_post_rtl")
        shutil.copytree(str(fixture), proj_dir)
        _clear_sim_dir(proj_dir)
        _add_rtl_only_compile_log(proj_dir)

        rtl_top = Path(proj_dir) / "rtl" / "dma_top.v"
        rtl_top.write_text(
            """
`default_nettype none

module dma_top (
    input  wire       clk_i,
    input  wire       rst_ni,
    input  wire       valid_i,
    input  wire [7:0] data_i,
    input  wire [1:0] req_i,
    output wire       valid_o,
    output wire [7:0] data_o,
    output wire [1:0] gnt_o
);
    wire ready_unused;

    pipeline_stage #(.WIDTH(8)) u_pipe (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .valid_i(valid_i),
        .data_i(data_i),
        .ready_o(ready_unused),
        .valid_o(valid_o),
        .data_o(data_o)
    );

    output_arbiter u_arb (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_i(req_i),
        .gnt_o(gnt_o)
    );
endmodule
""".lstrip(),
            encoding="utf-8",
        )

        rc1, out1 = _run_workflow_gate(proj_dir, "post-rtl", force=True)
        if verbose:
            print(out1)
        if rc1 != 0:
            return False, "post-rtl should PASS before direct integration TB test"

        matrix = Path(proj_dir) / "docs" / "module_verification_matrix.md"
        if matrix.exists():
            matrix.unlink()

        tb_top = Path(proj_dir) / "tb" / "tb_dma_top.v"
        tb_top.parent.mkdir(exist_ok=True)
        tb_top.write_text(
            """
module tb_dma_top;
    reg clk_i;
    reg rst_ni;
    reg valid_i;
    reg [7:0] data_i;
    reg [1:0] req_i;
    wire valid_o;
    wire [7:0] data_o;
    wire [1:0] gnt_o;

    dma_top dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .valid_i(valid_i),
        .data_i(data_i),
        .req_i(req_i),
        .valid_o(valid_o),
        .data_o(data_o),
        .gnt_o(gnt_o)
    );
endmodule
""".lstrip(),
            encoding="utf-8",
        )

        rc2, out2 = _run_workflow_gate(proj_dir, "pre-integration", force=False)
        if verbose:
            print(out2)
        if rc2 == 0:
            return False, "direct integration TB before module sim should FAIL"
        required = [
            "PRE_INTEGRATION_STRICT",
            "Integration TB",
            "L2 requires per-module simulation before integration",
        ]
        for text in required:
            if text not in out2:
                return False, f"missing direct-integration failure text: {text}"
        return True, "OK"


def run_workflow_cursor_written(verbose: bool = False) -> tuple[bool, str]:
    """workflow_gate PASS must write a compact cursor with next-step guidance."""
    fixture = FIXTURES_DIR / "clean_l2_per_module_then_integration"
    with tempfile.TemporaryDirectory() as tmpdir:
        proj_dir = os.path.join(tmpdir, "workflow_cursor_written")
        shutil.copytree(str(fixture), proj_dir)
        _clear_sim_dir(proj_dir)
        _add_rtl_only_compile_log(proj_dir)

        rc, output = _run_workflow_gate(proj_dir, "post-rtl", force=True)
        if verbose:
            print(output)
        if rc != 0:
            return False, "post-rtl should PASS before cursor check"
        cursor = Path(proj_dir) / "docs" / "workflow_cursor.md"
        if not cursor.exists():
            return False, "workflow_cursor.md was not written"
        text = cursor.read_text(encoding="utf-8")
        required = [
            "Gate status: PASS",
            "Current phase: post-rtl",
            "Next workflow step: Step 8 no-TB review, then Step 9 L2 per-module verification",
            "Forbidden next action: do not create or run integration TB",
            "Contract lock: pre-rtl PASS snapshots contract docs by sha256",
        ]
        for token in required:
            if token not in text:
                return False, f"workflow_cursor.md missing token: {token}"
        if "Cursor saved to" not in output:
            return False, "gate output did not report cursor path"
        return True, "OK"


def run_final_gate_rejects_hash_drift(verbose: bool = False
                                      ) -> tuple[bool, str]:
    """final_delivery_gate must reject stale contract snapshots by sha256."""
    with tempfile.TemporaryDirectory() as tmpdir:
        proj = Path(tmpdir) / "hash_drift"
        docs = proj / "docs"
        docs.mkdir(parents=True)
        contract = docs / "timing-contract.md"
        contract.write_text("contract-v1\n", encoding="utf-8")
        st = contract.stat()
        state = {
            "schema_version": 1,
            "level": "L1",
            "phases": {
                "pre-rtl": {
                    "status": "PASS",
                    "timestamp": "2026-06-08T00:00:00Z",
                    "command": "fixture",
                    "evidence": "fixture",
                    "snapshot": {
                        "docs/timing-contract.md": {
                            "mtime": st.st_mtime,
                            "size": st.st_size,
                            "sha256": "0" * 64,
                        }
                    },
                },
                "post-rtl": {
                    "status": "PASS",
                    "timestamp": "2026-06-08T00:00:00Z",
                    "command": "fixture",
                    "evidence": "fixture",
                    "snapshot": {},
                },
                "post-sim": {
                    "status": "PASS",
                    "timestamp": "2026-06-08T00:00:00Z",
                    "command": "fixture",
                    "evidence": "fixture",
                    "snapshot": {},
                },
            },
        }
        (docs / "workflow_state.json").write_text(
            json.dumps(state, indent=2) + "\n",
            encoding="utf-8",
        )
        rc, output = _run_final_delivery_gate(str(proj))
        if verbose:
            print(output)
        if rc == 0:
            return False, "final gate should FAIL on contract hash drift"
        if "content hash changed" not in output:
            return False, "final gate did not report content hash drift"
        return True, "OK"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Workflow gate regression runner")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Print gate output for each test")
    args = parser.parse_args()

    results = []
    for tc in TEST_CASES:
        ok, msg = run_test(tc, verbose=args.verbose)
        results.append((tc, ok, msg))
        status = "PASS" if ok else "FAIL"
        expect_label = "PASS" if tc["expect_pass"] else "FAIL"
        print(f"[{status}] {tc['name']}: --phase {tc['phase']} -> expect {expect_label}")
        if not ok:
            print(f"       {msg}")

    special_cases = [
        ("post_rtl_rerun_after_tb", run_post_rtl_rerun_after_tb),
        ("success_no_marker_rejected", run_success_no_marker_rejected),
        ("invalid_marker_rejected", run_invalid_marker_rejected),
        ("bom_marker_accepted", run_bom_marker_accepted),
        ("parameterized_leaf_tb_not_integration",
         run_parameterized_leaf_tb_not_integration),
        ("l2_post_sim_requires_pre_integration",
         run_l2_post_sim_requires_pre_integration),
        ("post_rtl_pass_prints_l2_navigation",
         run_post_rtl_pass_prints_l2_navigation),
        ("pre_integration_pass_allows_integration",
         run_pre_integration_pass_allows_integration),
        ("module_sim_alias_matches_pre_integration",
         run_module_sim_alias_matches_pre_integration),
        ("l2_direct_integration_tb_after_post_rtl_fails",
         run_l2_direct_integration_tb_after_post_rtl_fails),
        ("workflow_cursor_written", run_workflow_cursor_written),
        ("final_gate_rejects_hash_drift", run_final_gate_rejects_hash_drift),
    ]
    for name, fn in special_cases:
        ok, msg = fn(verbose=args.verbose)
        results.append(({"name": name, "phase": "custom", "expect_pass": True}, ok, msg))
        status = "PASS" if ok else "FAIL"
        print(f"[{status}] {name}: custom regression")
        if not ok:
            print(f"       {msg}")

    print()
    total = len(results)
    passed = sum(1 for _, ok, _ in results if ok)
    failed = total - passed
    if failed == 0:
        print(f"All {total} regression tests PASSED")
        return 0
    else:
        print(f"{failed}/{total} regression tests FAILED")
        return 1


if __name__ == "__main__":
    sys.exit(main())
