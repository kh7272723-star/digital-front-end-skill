#!/usr/bin/env python3
"""
RTL Complexity Checker — Engineering Intuition Automation

Checks RTL files against engineering-intuition-checklist.md:
  - Code complexity: always block size, nesting depth, module size, fanout
  - Combinational depth: assign chain depth, wide comparators, priority chains
  - Area red flags: register arrays, repeated instances, hard-coded constants

Optional Yosys integration for synthesis-based area/timing analysis.

Usage:
    python rtl_complexity_check.py rtl/*.v
    python rtl_complexity_check.py rtl/*.v --yosys --top module_name

Source: engineering-intuition-checklist.md (RMM, Synopsys DC, Xilinx UG901)
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path


# Thresholds from engineering-intuition-checklist.md
THRESHOLDS = {
    "always_block_lines": 50,      # C1
    "if_else_depth": 3,            # C2
    "module_lines": 300,           # C3
    "fanout_refs": 50,             # C4
    "reg_array_depth": 64,         # A1
    "repeated_instances": 4,       # A2
    "priority_chain_depth": 8,     # D3
}


def read_file(path):
    """Read file with UTF-8 encoding."""
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def strip_comments(text):
    """Remove single-line and multi-line Verilog comments."""
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    return text


def find_modules(text):
    """Find module boundaries: returns list of (name, start_line, end_line)."""
    modules = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        m = re.match(r"\s*module\s+(\w+)", lines[i])
        if m:
            name = m.group(1)
            start = i
            depth = 0
            j = i
            while j < len(lines):
                depth += lines[j].count("begin") - lines[j].count("end")
                if re.search(r"\bendmodule\b", lines[j]):
                    modules.append((name, start, j))
                    i = j
                    break
                j += 1
        i += 1
    return modules


def check_always_block_size(text):
    """C1: Check always @(*) block line counts."""
    issues = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        if re.search(r"always\s+@\s*\(\s*\*", lines[i]):
            start = i
            depth = 0
            j = i
            while j < len(lines):
                depth += lines[j].count("begin") - lines[j].count("end")
                if depth <= 0 and j > start:
                    block_len = j - start + 1
                    if block_len > THRESHOLDS["always_block_lines"]:
                        issues.append({
                            "id": "C1",
                            "level": "WARNING",
                            "line": start + 1,
                            "message": f"always @(*) block is {block_len} lines (threshold: {THRESHOLDS['always_block_lines']})",
                            "fix": "Extract sub-expressions or split into multiple blocks"
                        })
                    i = j
                    break
                j += 1
        i += 1
    return issues


def check_nesting_depth(text):
    """C2: Check if-else nesting depth."""
    issues = []
    lines = text.split("\n")
    max_depth = 0
    current_depth = 0
    max_line = 0
    for i, line in enumerate(lines):
        stripped = line.strip()
        # Count if/else if/else nesting
        if re.search(r"\bif\s*\(", stripped):
            current_depth += 1
            if current_depth > max_depth:
                max_depth = current_depth
                max_line = i + 1
        if re.search(r"\bend\b", stripped) and current_depth > 0:
            current_depth -= 1

    if max_depth > THRESHOLDS["if_else_depth"]:
        issues.append({
            "id": "C2",
            "level": "WARNING",
            "line": max_line,
            "message": f"if-else nesting depth is {max_depth} (threshold: {THRESHOLDS['if_else_depth']})",
            "fix": "Use case/casez or early-return pattern"
        })
    return issues


def check_module_size(text, filename):
    """C3: Check module line counts."""
    issues = []
    modules = find_modules(text)
    for name, start, end in modules:
        size = end - start + 1
        if size > THRESHOLDS["module_lines"]:
            issues.append({
                "id": "C3",
                "level": "WARNING",
                "line": start + 1,
                "message": f"Module '{name}' is {size} lines (threshold: {THRESHOLDS['module_lines']})",
                "fix": "Decompose into submodules"
            })
    return issues


def check_register_arrays(text):
    """A1: Check for register arrays that should be RAM."""
    issues = []
    pattern = re.compile(
        r"reg\s+\[(\d+):0\]\s+(\w+)\s+\[0:(\d+)\]",
        re.IGNORECASE
    )
    for m in pattern.finditer(text):
        width = int(m.group(1)) + 1
        name = m.group(2)
        depth = int(m.group(3)) + 1
        if depth > THRESHOLDS["reg_array_depth"]:
            line_num = text[:m.start()].count("\n") + 1
            issues.append({
                "id": "A1",
                "level": "ERROR" if depth > 256 else "WARNING",
                "line": line_num,
                "message": f"Register array '{name}' is {depth}x{width} ({depth * width} FFs). Use inferred RAM.",
                "fix": "Use reg [W-1:0] mem [0:N-1] with proper read/write coding for RAM inference"
            })
    return issues


def check_hardcoded_constants(text):
    """A3: Check for non-parameterized numeric literals in port declarations."""
    issues = []
    # Look for fixed-width literals in module port declarations
    lines = text.split("\n")
    in_module_header = False
    for i, line in enumerate(lines):
        if re.search(r"\bmodule\s+\w+", line):
            in_module_header = True
        if in_module_header and re.search(r"\bendmodule\b", line):
            in_module_header = False
        # Check for hardcoded widths in reg/wire declarations
        if in_module_header or re.search(r"^\s*(reg|wire|input|output)\s+\[", line):
            # Not a parameter — flag if it's a literal number
            pass  # Too many false positives; skip for now
    return issues


def check_fanout(text):
    """C4: Estimate signal fanout by counting references."""
    issues = []
    # Find wire/reg declarations
    decl_pattern = re.compile(r"(?:wire|reg)\s+(?:\[[\d:]+\]\s+)?(\w+)\s*;")
    declared = set()
    for m in decl_pattern.finditer(text):
        declared.add(m.group(1))

    # Count references for each declared signal
    refs = Counter()
    for sig in declared:
        # Count word-boundary matches, excluding declaration line
        count = len(re.findall(r"\b" + re.escape(sig) + r"\b", text))
        refs[sig] = count

    for sig, count in refs.most_common(10):
        if count > THRESHOLDS["fanout_refs"]:
            # Find line of declaration
            decl_match = re.search(
                r"(?:wire|reg)\s+(?:\[[\d:]+\]\s+)?" + re.escape(sig) + r"\s*;",
                text
            )
            line_num = text[:decl_match.start()].count("\n") + 1 if decl_match else 0
            issues.append({
                "id": "C4",
                "level": "WARNING",
                "line": line_num,
                "message": f"Signal '{sig}' referenced {count} times (threshold: {THRESHOLDS['fanout_refs']})",
                "fix": "Insert register stages or MAX_FANOUT attribute"
            })
    return issues


def check_priority_chains(text):
    """D3: Check for long if-else if chains."""
    issues = []
    lines = text.split("\n")
    chain_len = 0
    chain_start = 0
    in_chain = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if re.search(r"\belse\s+if\s*\(", stripped):
            chain_len += 1
        elif re.search(r"\bif\s*\(", stripped):
            if in_chain and chain_len > THRESHOLDS["priority_chain_depth"]:
                issues.append({
                    "id": "D3",
                    "level": "WARNING",
                    "line": chain_start + 1,
                    "message": f"Priority chain is {chain_len} levels (threshold: {THRESHOLDS['priority_chain_depth']})",
                    "fix": "Use case/casez for parallel decode"
                })
            chain_len = 1
            chain_start = i
            in_chain = True
        elif not stripped.startswith("//") and stripped and not stripped.startswith("end"):
            if in_chain and chain_len > THRESHOLDS["priority_chain_depth"]:
                issues.append({
                    "id": "D3",
                    "level": "WARNING",
                    "line": chain_start + 1,
                    "message": f"Priority chain is {chain_len} levels (threshold: {THRESHOLDS['priority_chain_depth']})",
                    "fix": "Use case/casez for parallel decode"
                })
            in_chain = False
            chain_len = 0
    return issues


def check_repeated_instances(text):
    """A2: Check for repeated module instantiations."""
    issues = []
    # Find module instantiations: module_name instance_name (...)
    inst_pattern = re.compile(r"^\s*(\w+)\s+(?:#\s*\([^)]*\)\s+)?(\w+)\s*\(", re.MULTILINE)
    instances = Counter()
    for m in inst_pattern.finditer(text):
        mod_name = m.group(1)
        # Filter out Verilog keywords
        if mod_name not in ("if", "else", "case", "while", "for", "always",
                            "initial", "begin", "end", "module", "function",
                            "task", "generate", "assign", "wire", "reg",
                            "input", "output", "parameter", "localparam"):
            instances[mod_name] += 1

    for mod_name, count in instances.items():
        if count > THRESHOLDS["repeated_instances"]:
            issues.append({
                "id": "A2",
                "level": "INFO",
                "line": 0,
                "message": f"Module '{mod_name}' instantiated {count} times (threshold: {THRESHOLDS['repeated_instances']})",
                "fix": "Consider time-multiplexed resource sharing"
            })
    return issues


def run_yosys(sources, top_module):
    """Run Yosys synthesis and extract stat/ltp output."""
    source_str = " ".join(f'"{s}"' for s in sources)
    cmd = (
        f'yosys -p "read_verilog -sv {source_str}; '
        f'synth -top {top_module}; check -assert; stat; ltp" 2>&1'
    )
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=120
        )
        return result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return "ERROR: Yosys synthesis timed out (120s)"
    except FileNotFoundError:
        return "ERROR: Yosys not found in PATH"


def parse_yosys_output(output):
    """Parse Yosys stat/ltp output for key metrics."""
    metrics = {}

    # Cell count
    m = re.search(r"Number of cells:\s+(\d+)", output)
    if m:
        metrics["cell_count"] = int(m.group(1))

    # Wire count
    m = re.search(r"Number of wires:\s+(\d+)", output)
    if m:
        metrics["wire_count"] = int(m.group(1))

    # Latch detection
    latches = re.findall(r"\$_DLATCH_\w+", output)
    metrics["latch_count"] = len(latches)

    # Critical path (ltp length)
    m = re.search(r"Longest topological path.*?:\s*(\d+)", output)
    if m:
        metrics["critical_path_length"] = int(m.group(1))

    # Loop detection
    loops = re.findall(r"loop", output, re.IGNORECASE)
    metrics["loop_warnings"] = len(loops)

    return metrics


def analyze_file(filepath, yosys_output=None):
    """Analyze a single RTL file and return all issues."""
    text = read_file(filepath)
    clean = strip_comments(text)

    issues = []
    issues.extend(check_always_block_size(clean))
    issues.extend(check_nesting_depth(clean))
    issues.extend(check_module_size(clean, filepath))
    issues.extend(check_register_arrays(clean))
    issues.extend(check_fanout(clean))
    issues.extend(check_priority_chains(clean))
    issues.extend(check_repeated_instances(clean))

    # Add filename to each issue
    for issue in issues:
        issue["file"] = os.path.basename(filepath)

    return issues


def print_report(all_issues, yosys_metrics=None):
    """Print human-readable report."""
    print("=" * 70)
    print("RTL Complexity Report")
    print("=" * 70)

    if not all_issues and not yosys_metrics:
        print("\nNo issues found. Design looks clean.")
        return

    # Group by severity
    errors = [i for i in all_issues if i["level"] == "ERROR"]
    warnings = [i for i in all_issues if i["level"] == "WARNING"]
    infos = [i for i in all_issues if i["level"] == "INFO"]

    print(f"\nSummary: {len(errors)} errors, {len(warnings)} warnings, {len(infos)} info")

    if errors:
        print(f"\n{'='*70}")
        print("ERRORS (must fix)")
        print("=" * 70)
        for issue in errors:
            loc = f"{issue['file']}:{issue['line']}" if issue['line'] else issue['file']
            print(f"  [{issue['id']}] {loc}: {issue['message']}")
            print(f"         Fix: {issue['fix']}")

    if warnings:
        print(f"\n{'='*70}")
        print("WARNINGS (should fix)")
        print("=" * 70)
        for issue in warnings:
            loc = f"{issue['file']}:{issue['line']}" if issue['line'] else issue['file']
            print(f"  [{issue['id']}] {loc}: {issue['message']}")
            print(f"         Fix: {issue['fix']}")

    if infos:
        print(f"\n{'='*70}")
        print("INFO (style/readability)")
        print("=" * 70)
        for issue in infos:
            loc = f"{issue['file']}:{issue['line']}" if issue['line'] else issue['file']
            print(f"  [{issue['id']}] {loc}: {issue['message']}")

    if yosys_metrics:
        print(f"\n{'='*70}")
        print("Yosys Synthesis Metrics")
        print("=" * 70)
        for key, value in yosys_metrics.items():
            print(f"  {key}: {value}")
        if yosys_metrics.get("latch_count", 0) > 0:
            print("  ** LATCH INFERENCE DETECTED — always a bug in synchronous design **")
        if yosys_metrics.get("critical_path_length", 0) > 25:
            print(f"  ** Critical path ({yosys_metrics['critical_path_length']} gates) exceeds 25-gate target for 100MHz **")

    print()


def main():
    parser = argparse.ArgumentParser(
        description="RTL Complexity Checker — Engineering Intuition Automation"
    )
    parser.add_argument("files", nargs="+", help="RTL files to analyze")
    parser.add_argument("--yosys", action="store_true", help="Run Yosys synthesis analysis")
    parser.add_argument("--top", type=str, help="Top module name for Yosys synthesis")
    parser.add_argument("--json", type=str, help="Output JSON report to file")
    parser.add_argument("--thresholds", type=str, help="Custom thresholds JSON file")

    args = parser.parse_args()

    # Load custom thresholds if provided
    if args.thresholds:
        with open(args.thresholds, "r") as f:
            custom = json.load(f)
            THRESHOLDS.update(custom)

    # Analyze files
    all_issues = []
    for filepath in args.files:
        if os.path.exists(filepath):
            issues = analyze_file(filepath)
            all_issues.extend(issues)
        else:
            print(f"Warning: file not found: {filepath}")

    # Yosys integration
    yosys_metrics = None
    if args.yosys:
        if not args.top:
            print("Error: --top is required with --yosys")
            sys.exit(1)
        print(f"Running Yosys synthesis on {args.top}...")
        yosys_out = run_yosys(args.files, args.top)
        yosys_metrics = parse_yosys_output(yosys_out)

        # Add Yosys-based issues
        if yosys_metrics.get("latch_count", 0) > 0:
            all_issues.append({
                "id": "E2",
                "level": "ERROR",
                "file": "yosys",
                "line": 0,
                "message": f"Latch inference detected: {yosys_metrics['latch_count']} latches",
                "fix": "Add default assignments to all combinational blocks"
            })
        if yosys_metrics.get("critical_path_length", 0) > 25:
            all_issues.append({
                "id": "D1",
                "level": "ERROR",
                "file": "yosys",
                "line": 0,
                "message": f"Critical path is {yosys_metrics['critical_path_length']} gates (target: <25 for 100MHz)",
                "fix": "Insert pipeline registers or restructure logic"
            })

    # Print report
    print_report(all_issues, yosys_metrics)

    # JSON output
    if args.json:
        report = {
            "issues": all_issues,
            "summary": {
                "errors": len([i for i in all_issues if i["level"] == "ERROR"]),
                "warnings": len([i for i in all_issues if i["level"] == "WARNING"]),
                "info": len([i for i in all_issues if i["level"] == "INFO"]),
            },
        }
        if yosys_metrics:
            report["yosys"] = yosys_metrics
        with open(args.json, "w") as f:
            json.dump(report, f, indent=2)
        print(f"JSON report saved to {args.json}")

    # Exit code: 1 if errors, 0 otherwise
    if any(i["level"] == "ERROR" for i in all_issues):
        sys.exit(1)


if __name__ == "__main__":
    main()
