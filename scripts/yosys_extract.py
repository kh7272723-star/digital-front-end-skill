#!/usr/bin/env python3
"""Yosys synthesis report extraction tool.

Runs yosys synthesis on RTL and extracts structured report:
- Cell counts by type
- Latch detection
- Loop detection (combinational feedback)
- Unused/undriven signals
- Longest topological path
- Synthesis warnings

Usage:
    python yosys_extract.py <rtl_file> [--top <module>] [--yosys <path>]
    python yosys_extract.py rr_ready_valid_arbiter.v --top rr_ready_valid_arbiter
    python yosys_extract.py rtl/*.v --top my_module
"""

import argparse
import re
import subprocess
import sys
import tempfile
import os
from pathlib import Path


def find_yosys():
    """Find yosys executable."""
    # Check PATH
    for path_dir in os.environ.get("PATH", "").split(os.pathsep):
        yosys = Path(path_dir) / "yosys.exe"
        if yosys.exists():
            return str(yosys)
        yosys = Path(path_dir) / "yosys"
        if yosys.exists():
            return str(yosys)
    return None


def run_yosys(yosys_path, rtl_files, top_module):
    """Run yosys synthesis and return output."""
    sources = " ".join(rtl_files)
    cmd = f'"{yosys_path}" -p "read_verilog -sv {sources}; synth -top {top_module}; check -assert; stat; ltp"'

    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=120
        )
        return result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return "ERROR: yosys timed out after 120 seconds"
    except Exception as e:
        return f"ERROR: {e}"


def parse_synth_report(output):
    """Parse yosys output into structured report."""
    report = {
        "warnings": [],
        "errors": [],
        "cells": {},
        "stats": {},
        "latches": [],
        "loops": [],
        "ltp_length": None,
        "ltp_path": [],
        "check_problems": 0,
    }

    lines = output.split("\n")
    in_stat = False
    in_ltp = False
    ltp_module = ""

    for i, line in enumerate(lines):
        stripped = line.strip()

        # Warnings
        if "Warning:" in stripped:
            report["warnings"].append(stripped)
            if "latch" in stripped.lower() or "found DLATCH" in stripped:
                report["latches"].append(stripped)
            if "loop" in stripped.lower() or "Detected loop" in stripped:
                report["loops"].append(stripped)

        # Errors
        if "ERROR" in stripped or "error:" in stripped.lower():
            report["errors"].append(stripped)

        # Check pass results
        if "Found and reported" in stripped:
            m = re.search(r"Found and reported (\d+) problems", stripped)
            if m:
                report["check_problems"] = int(m.group(1))

        # Stat section
        if stripped.startswith("=== ") and stripped.endswith(" ==="):
            in_stat = True
            ltp_module = stripped[4:-4].strip()
            continue

        if in_stat:
            # Cell count line: "     $_CELLTYPE_    N"
            m = re.match(r"\s+(\$\w+)\s+(\d+)", stripped)
            if m:
                cell_type = m.group(1)
                count = int(m.group(2))
                report["cells"][cell_type] = count
                if "DLATCH" in cell_type:
                    report["latches"].append(f"Cell: {cell_type} x{count}")

            # Stat metrics
            m = re.match(r"Number of (\w[\w\s]*):\s+(\d+)", stripped)
            if m:
                key = m.group(1).strip().replace(" ", "_")
                report["stats"][key] = int(m.group(2))

            if stripped.startswith("5.") or stripped == "":
                in_stat = False

        # LTP section
        if "Longest topological path" in stripped:
            in_ltp = True
            m = re.search(r"length=(\d+)", stripped)
            if m:
                report["ltp_length"] = int(m.group(1))
            ltp_module = ""
            m = re.search(r"in (\S+)", stripped)
            if m:
                ltp_module = m.group(1)
            continue

        if in_ltp:
            m = re.match(r"\s+\d+: (\\?\w[\w\[\]$.]*)", stripped)
            if m:
                report["ltp_path"].append(m.group(1))
            if stripped == "" or (stripped and not stripped[0].isspace()):
                in_ltp = False

    return report


def print_report(report, top_module):
    """Print structured report."""
    print(f"=== Synthesis Report: {top_module} ===\n")

    # Errors
    if report["errors"]:
        print("ERRORS:")
        for e in report["errors"]:
            print(f"  {e}")
        print()

    # Warnings
    if report["warnings"]:
        print(f"WARNINGS ({len(report['warnings'])}):")
        for w in report["warnings"][:10]:
            print(f"  {w}")
        if len(report["warnings"]) > 10:
            print(f"  ... ({len(report['warnings'])} total)")
        print()

    # Latch detection
    if report["latches"]:
        print("LATCH INFERENCE DETECTED:")
        for l in report["latches"]:
            print(f"  {l}")
        print()

    # Loop detection
    if report["loops"]:
        print("COMBINATIONAL LOOPS DETECTED:")
        for l in report["loops"][:5]:
            print(f"  {l}")
        print()

    # Check results
    print(f"Structural check: {report['check_problems']} problems found\n")

    # Stats
    if report["stats"]:
        print("RESOURCE USAGE:")
        for key, val in report["stats"].items():
            print(f"  {key}: {val}")
        print()

    # Cell breakdown
    if report["cells"]:
        print("CELL COUNTS:")
        for cell, count in sorted(report["cells"].items(), key=lambda x: -x[1]):
            print(f"  {cell:30s} {count}")
        print()

    # LTP
    if report["ltp_length"] is not None:
        print(f"CRITICAL PATH (longest topological path): {report['ltp_length']} gates")
        if report["ltp_path"]:
            for j, node in enumerate(report["ltp_path"][:10]):
                print(f"  {j}: {node}")
            if len(report["ltp_path"]) > 10:
                print(f"  ... ({len(report['ltp_path'])} nodes total)")
        print()

    # Summary
    issues = []
    if report["latches"]:
        issues.append(f"{len(report['latches'])} latch(es)")
    if report["check_problems"] > 0:
        issues.append(f"{report['check_problems']} structural problem(s)")
    if report["loops"]:
        issues.append(f"{len(report['loops'])} combinational loop(s)")
    if report["ltp_length"] and report["ltp_length"] > 25:
        issues.append(f"critical path length {report['ltp_length']} (target: <25)")

    if issues:
        print(f"ISSUES FOUND: {', '.join(issues)}")
    else:
        print("SYNTHESIS CLEAN: no structural issues detected.")


def main():
    parser = argparse.ArgumentParser(description="Yosys synthesis report extraction")
    parser.add_argument("rtl_files", nargs="+", help="RTL source files")
    parser.add_argument("--top", required=True, help="Top module name")
    parser.add_argument("--yosys", help="Path to yosys executable")
    parser.add_argument("--json", action="store_true", help="Output as JSON")

    args = parser.parse_args()

    # Find yosys
    yosys_path = args.yosys
    if not yosys_path:
        yosys_path = find_yosys()
    if not yosys_path:
        print("Error: yosys not found. Use --yosys to specify path.", file=sys.stderr)
        sys.exit(1)

    # Validate files
    for f in args.rtl_files:
        if not Path(f).exists():
            print(f"Error: file not found: {f}", file=sys.stderr)
            sys.exit(1)

    # Run yosys
    print(f"Running yosys on {len(args.rtl_files)} file(s), top={args.top}...")
    output = run_yosys(yosys_path, args.rtl_files, args.top)

    # Parse report
    report = parse_synth_report(output)

    # Output
    if args.json:
        import json
        print(json.dumps(report, indent=2))
    else:
        print_report(report, args.top)


if __name__ == "__main__":
    main()
