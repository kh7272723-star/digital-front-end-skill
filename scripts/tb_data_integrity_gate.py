#!/usr/bin/env python3
"""TB Data Integrity Gate: reject TBs that connect data signals but never compare them.

For each data-bearing OUTPUT signal found in a TB file, checks whether that
SPECIFIC signal name appears in a value-comparison context.  Input-only signals
(_i suffix) and pure handshake signals (_ready_o, _valid_o) are excluded.

Exit 0 (PASS) only when all data-bearing output signals in all project TB
files have at least one signal-specific comparison.

Exit 1 (FAIL) with findings otherwise.

Usage:
  python scripts/tb_data_integrity_gate.py <project_dir> [--level L1|L2]
"""
import argparse
import os
import re
import sys


# Data-bearing OUTPUT signal patterns (excluding _ready_o and _valid_o)
DATA_SIGNAL_PATTERNS = [
    (r"\brd_data_o\b", "FIFO/read data output"),
    (r"\brdata_o\b", "FIFO/read data output"),
    (r"\bdata_out_o\b", "data output"),
    (r"\bdout_o\b", "data output"),
    (r"\bfifo_rdata_o\b", "FIFO read data"),
    (r"\bdfifo_rdata_i\b", "FIFO read data (dfifo interface)"),
    (r"\bm_axi_wdata_o\b", "AXI write data"),
    (r"\bwdata_o\b", "write data output"),
    (r"\bcpl_bytes_xfr_o\b", "completion bytes"),
    (r"\bcpl_bytes_o\b", "completion bytes"),
    (r"\bcpl_byte_cnt_o\b", "completion bytes"),
    (r"\bbytes_written_o\b", "completion bytes"),
    (r"\btotal_bytes_o\b", "completion bytes"),
    (r"\bcpl_status_o\b", "completion status"),
    (r"\bcompletion_status_o\b", "completion status"),
    (r"\balloc_b_count_o\b", "burst planner alloc count"),
    (r"\bdesc_cmd_bytes_o\b", "descriptor bytes output"),
    (r"\bdesc_cmd_addr_o\b", "descriptor address output"),
    (r"\bdesc_cmd_tag_o\b", "descriptor tag output"),
    (r"\bdesc_cmd_src_addr_o\b", "descriptor source address"),
    (r"\bdesc_cmd_dst_addr_o\b", "descriptor destination address"),
    (r"\bdesc_bytes_o\b", "descriptor bytes"),
    (r"\bdesc_addr_o\b", "descriptor address"),
    (r"\bdesc_data_o\b", "descriptor data output"),
]


def _read_file(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception:
        return ""


def _strip_comments(text):
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    return text


def _looks_like_testbench(text):
    return bool(re.search(r"\b(initial|always|forever|repeat|@\s*\(\s*posedge)", text))


def _signal_has_comparison(signal_name, code):
    """Check if signal_name or a common name variant appears in a comparison context."""
    candidates = {signal_name}
    # rd_data_o <-> rdata_o (with/without leading 'd')
    if signal_name.startswith("rd_"):
        candidates.add("r" + signal_name[2:])
    elif signal_name.startswith("r_") and not signal_name.startswith("rd_"):
        candidates.add("rd" + signal_name[1:])
    # dfifo_rdata_i style -> also try rdata_o
    if signal_name == "dfifo_rdata_i":
        candidates.add("rdata_o")

    for name in sorted(candidates, key=len, reverse=True):
        escaped = re.escape(name)
        patterns = [
            escaped + r"\s*(?:==|===|!=|!==)",
            r"(?:expected|exp)_\w+\s*(?:==|===|!=|!==)\s*" + escaped,
            escaped + r"\s*(?:==|===|!=|!==)\s*(?:expected|exp)_\w+",
            r"check_\w+\s*\([^;)]*" + escaped,
            r"\bassert\b[^;]*" + escaped,
            r"(?:mismatch|error)_cnt\b[^;\n]*" + escaped,
            escaped + r"[^;\n]*(?:mismatch|error)_cnt\b",
            r"scoreboard[^;\n]*" + escaped,
            r"\$display[^;]*" + escaped + r"[^;]*\bFAIL\b",
        ]
        for pat in patterns:
            if re.search(pat, code, re.IGNORECASE):
                return True
    return False


def _find_data_signals(code):
    found = {}
    for pat, desc in DATA_SIGNAL_PATTERNS:
        for m in re.finditer(pat, code, re.IGNORECASE):
            name = m.group(0)
            if name not in found:
                found[name] = desc
    return found


def check_tb_file(tb_path, level):
    findings = []
    raw = _read_file(tb_path)
    if not raw:
        return findings
    code = _strip_comments(raw)
    if not _looks_like_testbench(code):
        return findings
    data_signals = _find_data_signals(code)
    if not data_signals:
        return findings
    is_top = "_top" in os.path.basename(tb_path).lower() or "integration" in tb_path.lower()
    severity = "E" if (is_top or level == "L2") else "W"
    for signal_name, desc in sorted(data_signals.items()):
        if _signal_has_comparison(signal_name, code):
            continue
        findings.append(
            f"[{severity}] {os.path.basename(tb_path)}: {desc} signal "
            f"'{signal_name}' is wired but never compared against an expected "
            f"value. Tests may false-pass with corrupted data. "
            f"Add: {signal_name} == expected_xxx or check_xxx({signal_name}).")
    return findings


def check_project(proj_dir, level):
    tb_dir = os.path.join(proj_dir, "tb")
    if not os.path.isdir(tb_dir):
        return []
    all_findings = []
    for fname in sorted(os.listdir(tb_dir)):
        if not fname.endswith((".v", ".sv")):
            continue
        if not fname.lower().startswith("tb_"):
            continue
        fpath = os.path.join(tb_dir, fname)
        all_findings.extend(check_tb_file(fpath, level))
    return all_findings


def main():
    parser = argparse.ArgumentParser(
        description="TB Data Integrity Gate")
    parser.add_argument("project_dir")
    parser.add_argument("--level", default="L1", choices=["L1", "L2"])
    args = parser.parse_args()
    findings = check_project(args.project_dir, args.level)
    if not findings:
        print("TB_DATA_INTEGRITY_GATE: PASS")
        sys.exit(0)
    print("TB_DATA_INTEGRITY_GATE: FAIL")
    for f in findings:
        print(f"  - {f}")
    sys.exit(1)


if __name__ == "__main__":
    main()
