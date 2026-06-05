"""Compile log gate: reject logs with hard compile errors/warnings.

Exit 0 only when no hard findings are present across all provided logs.
Exit 1 with clear findings otherwise.

Usage: python scripts/compile_log_gate.py <compile_log> [<compile_log> ...]
"""
import argparse
import io
import re
import sys

# Wrap stdout/stderr for encoding-safe printing on Windows code pages.
try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except (AttributeError, io.UnsupportedOperation):
    try:
        sys.stdout = io.TextIOWrapper(
            sys.stdout.buffer,
            encoding='utf-8',
            errors='replace')
        sys.stderr = io.TextIOWrapper(
            sys.stderr.buffer,
            encoding='utf-8',
            errors='replace')
    except AttributeError:
        pass


def read_log_text(log_file: str) -> str:
    """Read logs produced by shells/tools with UTF-8, UTF-16, or mixed bytes."""
    with open(log_file, 'rb') as f:
        data = f.read()

    for enc in ('utf-8-sig', 'utf-16', 'utf-16-le', 'utf-16-be'):
        try:
            text = data.decode(enc)
        except UnicodeError:
            continue
        if text.count('\x00') <= max(4, len(text) // 20):
            return text

    text = data.decode('utf-8', errors='replace')
    if '\x00' in text:
        text = text.replace('\x00', '')
    return text


def is_timescale_inherited_line(line: str) -> bool:
    """Return True if the line is a benign timescale-inherited warning."""
    lower = line.lower()
    return 'timescale' in lower and 'inherited' in lower


# Patterns checked against every non-skipped line.
# Each entry: (compiled_regex, short_description)
_LINE_PATTERNS = [
    (re.compile(r'\berror:', re.IGNORECASE),               "error marker"),
    (re.compile(r'syntax error', re.IGNORECASE),           "syntax error"),
    (re.compile(r'elaboration failed', re.IGNORECASE),     "elaboration failed"),
    (re.compile(r'unable to bind', re.IGNORECASE),         "unable to bind"),
    (re.compile(r'\bunresolved\b', re.IGNORECASE),         "unresolved reference"),
    (re.compile(r'implicit (wire|net)', re.IGNORECASE),    "implicit wire/net"),
    (re.compile(r'multiple driver', re.IGNORECASE),        "multiple driver"),
    (re.compile(r'out of bound', re.IGNORECASE),           "out of bounds"),
    (re.compile(r'selecting after', re.IGNORECASE),        "selecting after"),
    (re.compile(r'selecting before', re.IGNORECASE),       "selecting before"),
    (re.compile(r'Replacing.*(\'\s*bx|\bwith\s+x\b)',
                re.IGNORECASE),                             "replacing with x/bx"),
    (re.compile(r'\bPort\b.*\bexpects\b.*\bgot\b',
                re.IGNORECASE),                             "port width mismatch"),
    (re.compile(r'\bpadding\b', re.IGNORECASE),            "padding warning"),
    (re.compile(r'\bpruning\b', re.IGNORECASE),            "pruning warning"),
    (re.compile(r'\btruncat', re.IGNORECASE),              "truncation warning"),
    (re.compile(r'truncat.*(?:24\'|to\s+(?:0|fit))',
                re.IGNORECASE),                             "numeric constant truncation"),
    (re.compile(r'\bextend(?!ed)\b', re.IGNORECASE),      "extend warning"),
    (re.compile(r'\binferred\s+latch\b|latch\s+inferred',
                re.IGNORECASE),                             "inferred latch"),
]


def check_log(text: str) -> list[str]:
    """Return list of findings. Empty list means PASS.

    Hard-fails on empty or whitespace-only logs: an empty compile log cannot
    prove compilation succeeded.
    """
    findings = []

    if not text.strip():
        findings.append("Empty or whitespace-only compile log (no evidence of compilation)")
        return findings

    for line_no, line in enumerate(text.splitlines(), 1):
        if is_timescale_inherited_line(line):
            continue
        for pat, desc in _LINE_PATTERNS:
            if pat.search(line):
                findings.append(
                    f"Line {line_no}: {desc}: {line.strip()!r}")

    return findings


def main():
    parser = argparse.ArgumentParser(
        description="Compile log gate: reject logs with hard compile errors/warnings.")
    parser.add_argument(
        'compile_logs', nargs='+',
        help='Compile log file(s) to check')
    args = parser.parse_args()

    all_findings: dict[str, list[str]] = {}
    overall_fail = False

    for log_file in args.compile_logs:
        try:
            text = read_log_text(log_file)
        except FileNotFoundError:
            print(f"[REJECT] File not found: {log_file}", file=sys.stderr)
            overall_fail = True
            continue

        findings = check_log(text)
        all_findings[log_file] = findings
        if findings:
            overall_fail = True

    if not overall_fail:
        print("COMPILE_LOG_GATE: PASS")
        sys.exit(0)

    print("COMPILE_LOG_GATE: FAIL")
    for log_file, findings in all_findings.items():
        if findings:
            print(f"  {log_file}: {len(findings)} finding(s)")
            for f in findings:
                print(f"    - {f}")
        else:
            print(f"  {log_file}: PASS")
    sys.exit(1)


def _smoke_test():
    """Run a self-test to verify all detection patterns work correctly."""
    print("=== compile_log_gate smoke test ===\n")

    test_cases = [
        ("clean",
         "All modules compiled successfully.\nNo errors or warnings.\n",
         True),
        ("timescale inherited only",
         "Warning: timescale inherited for module 'top' from another file\n",
         True),
        ("error marker",
         "ERROR: testbench.sv:42: syntax error near 'endmodule'\n",
         False),
        ("syntax error",
         "Syntax error in module top: missing semicolon\n",
         False),
        ("elaboration failed",
         "Elaboration failed: cannot resolve module type\n",
         False),
        ("unable to bind",
         "Unable to bind wire 'data_out' in module 'top'\n",
         False),
        ("unresolved",
         "Warning: Unresolved reference to 'sub_module'\n",
         False),
        ("implicit wire",
         "implicit wire 'tmp_signal' in module 'top'\n",
         False),
        ("multiple driver",
         "Warning: multiple driver on net 'data_bus'\n",
         False),
        ("out of bound",
         "out of bound: index 8 exceeds width 7\n",
         False),
        ("selecting after",
         "selecting after storage of variable 'count' is not supported\n",
         False),
        ("selecting before",
         "selecting before storage of variable 'count' is not supported\n",
         False),
        ("replacing with x ('bx pattern)",
         "Replacing 'bx with x\n",
         False),
        ("port mismatch",
         "Port 'data_in' expects 8 bits, got 16 bits\n",
         False),
        ("padding",
         "padding of 3 bits in port connection 'data_bus'\n",
         False),
        ("pruning",
         "pruning of unused bits in expression\n",
         False),
        ("truncation",
         "warning: expression truncated to 8 bits\n",
         False),
        ("numeric constant truncation (24'd...)",
         "warning: 24'd16777216 was truncated to fit in 23 bits\n",
         False),
        ("numeric constant truncation (to 0)",
         "constant truncated to 0\n",
         False),
        ("extend (not extended)",
         "extend expression to 16 bits\n",
         False),
        ("extended word (should NOT trigger)",
         "extended to 16 bits automatically\n",
         True),
        ("inferred latch",
         "inferred latch for signal 'hold_reg'\n",
         False),
        ("latch inferred",
         "Warning: latch inferred for 'data_q' in always_comb\n",
         False),
    ]

    all_pass = True
    for name, text, expect_pass in test_cases:
        findings = check_log(text)
        passed = len(findings) == 0
        status = "PASS" if passed else "FAIL"
        expected_label = "PASS" if expect_pass else "FAIL"
        ok = "OK" if passed == expect_pass else "MISMATCH"
        if ok != "OK":
            all_pass = False
        first_line = text.splitlines()[0] if text.splitlines() else "(empty)"
        print(f"  [{ok}] {name}: gate={status} expected={expected_label}")
        print(f"       Input: {first_line!r}")
        for f in findings:
            print(f"       -> {f}")

    print()
    if all_pass:
        print("COMPILE_LOG_GATE: PASS")
    else:
        print("COMPILE_LOG_GATE: FAIL")
        sys.exit(1)


if __name__ == '__main__':
    if len(sys.argv) > 1:
        main()
    else:
        _smoke_test()
