#!/usr/bin/env python3
"""rtl_style_check.py — automated RTL style and constraint checker.

Checks C19, C21, NBA traps, port naming, default_nettype.
Designed to catch violations that pass Step 8 manual review.

Usage: python scripts/rtl_style_check.py <file1.v> [file2.v ...]
Exit code: 0 = clean, 1 = violations found.
"""

import re
import sys

OUT = []
FILE = ""


def warn(level, code, line_no, msg):
    """Append a finding. level: E=error, W=warning."""
    OUT.append(f"[{level}][{code}] {FILE}:{line_no}: {msg}")


def check_c21_multi_stmt(lines):
    """C21: one statement per line — detect '; ' or ';\\t' followed by non-comment code."""
    for i, raw in enumerate(lines, 1):
        s = raw.rstrip()
        # skip comments and blank lines
        if not s or s.lstrip().startswith('//'):
            continue
        # strip line comments
        code = s.split('//')[0]
        # skip for-loop headers (semicolons are part of the for syntax)
        if re.match(r'\s*for\s*\(', code):
            continue
        # skip generate for headers
        if re.match(r'\s*generate\s+for\s*\(', code):
            continue

        # find ';' with non-whitespace after it, excluding end of code
        m = re.search(r';(?!\s*$)\s*(\S)', code)
        if m:
            stripped = code.lstrip()
            if stripped.startswith('//'):
                continue
            after = code[m.start():]
            ch = m.group(1)
            # If after ';' comes 'end' or 'else' or comment, it's OK
            rest = after[1:].lstrip()
            if rest.startswith('end') or rest.startswith('else '):
                continue
            if rest.startswith('//'):
                continue
            warn('E', 'C21', i, f"multiple statements on one line: ...{after[:60].strip()}")


def check_c19_if_if_chain(lines):
    """C19: sequential if blocks without else in sequential always blocks.

    Detects patterns like:
        if (cond1) begin ... end
        if (cond2) begin ... end   <-- missing else
    inside always @(posedge) blocks.
    """
    in_seq_block = False
    prev_if_line = 0
    prev_had_else = False
    # Track nested begin/end depth
    depth = 0

    for i, raw in enumerate(lines, 1):
        s = raw.rstrip()
        code = s.split('//')[0]

        if re.search(r'always\s*@\s*\(\s*posedge', code):
            in_seq_block = True
            prev_if_line = 0
            prev_had_else = True  # reset
            depth = 0
            continue

        if in_seq_block and re.match(r'\s*end\b', code):
            if depth > 0:
                depth -= 1
            else:
                in_seq_block = False
                continue

        if not in_seq_block:
            continue

        # Track begin/end depth for nested ifs
        if re.search(r'\bbegin\b', code):
            depth += 1
        if re.search(r'\bend\b', code) and depth > 0:
            depth -= 1

        # Detect start of 'if' at current depth level (not nested inside another if's begin-end)
        m = re.match(r'\s*if\s*\(', code)
        if m:
            if prev_if_line > 0 and not prev_had_else and depth == 0:
                warn('W', 'C19', i,
                     f"consecutive 'if' without 'else' between "
                     f"(previous if line {prev_if_line}) — "
                     f"may indicate missing else-if chain")
            prev_if_line = i
            prev_had_else = False

        # Detect 'else if' or 'else begin' — marks the previous if as closed
        m2 = re.match(r'\s*end\s*else\s+if\s*\(', code)
        m3 = re.match(r'\s*end\s*else\s*$', code)
        m4 = re.match(r'\s*\}\s*else\s*\{', code)
        m5 = re.match(r'\s*\}?\s*else\s+if\s*\(', code)
        m6 = re.match(r'\s*else\s+if\s*\(', code)
        m7 = re.match(r'\s*end\s+else\s+begin\b', code)
        m8 = re.match(r'\s*else\s+begin\b', code)
        if m2 or m3 or m4 or m5 or m6 or m7 or m8:
            prev_had_else = True


def check_nba_trap1(lines):
    """NBA Trap 1: registered counter + registered dependent output in same always block.

    Pattern: inside always @(posedge), a counter increments via <=, and another
    register's <= RHS references that counter. The dependent register gets the OLD value.

    Heuristic: find 'x_q <= x_q +' patterns, then check if any other <= on following
    lines references x_q in its RHS.
    """
    in_seq = False
    counters = set()

    for i, raw in enumerate(lines, 1):
        s = raw.rstrip()
        code = s.split('//')[0]

        if re.search(r'always\s*@\s*\(\s*posedge', code):
            in_seq = True
            counters = set()
            continue

        if in_seq and re.match(r'\s*end\b', code):
            in_seq = False
            continue

        if not in_seq:
            continue

        # Detect counter: signal_q <= signal_q + ...
        m = re.match(r'\s*(\w+)\s*<=\s*\1\s*\+', code)
        if m:
            counters.add(m.group(1))

        # Detect dependent output: rhs references a counter we've seen
        if counters:
            m2 = re.match(r'\s*(\w+)\s*<=\s*(.+)', code)
            if m2:
                rhs = m2.group(2)
                lhs = m2.group(1)
                for c in counters:
                    # counter itself updating is fine
                    if c == lhs:
                        continue
                    if re.search(r'\b' + re.escape(c) + r'\b', rhs):
                        warn('W', 'NBA1', i,
                             f"registered output '{lhs}' reads counter '{c}' "
                             f"in same always block — uses pre-NBA (old) value. "
                             f"Consider combinational output instead.")


def check_nba_trap2(lines):
    """NBA Trap 2: advancing read pointer + registered data from same indexed memory.

    Detects: inside always @(posedge), rd_ptr_q advances and data_o gets
    mem[rd_ptr_q] — data_o gets old slot because pointer advanced via NBA.
    """
    in_seq = False
    ptr_advancing = set()
    mem_name = None

    for i, raw in enumerate(lines, 1):
        s = raw.rstrip()
        code = s.split('//')[0]

        if re.search(r'always\s*@\s*\(\s*posedge', code):
            in_seq = True
            ptr_advancing = set()
            mem_name = None
            continue

        if in_seq and re.match(r'\s*end\b', code):
            in_seq = False
            continue

        if not in_seq:
            continue

        # Detect pointer advance: ptr_q <= ptr_q + 1
        m = re.match(r'\s*(\w*ptr\w*)\s*<=\s*\1\s*\+', code)
        if m:
            ptr_advancing.add(m.group(1))

        # Detect registered read from indexed memory
        m2 = re.match(r'\s*(\w+)\s*<=\s*(\w+)\[(\w+)\]', code)
        if m2:
            lhs = m2.group(1)
            mem = m2.group(2)
            idx = m2.group(3).strip()
            if idx in ptr_advancing or idx + '_q' in ptr_advancing:
                warn('W', 'NBA2', i,
                     f"registered output '{lhs}' reads {mem}[{idx}] "
                     f"while '{idx}' advances in same block — "
                     f"data shifts by 1 beat. Use combinational read instead.")


def check_port_suffix(lines):
    """Verify port suffixes: outputs use _o, inputs use _i."""
    in_port_list = False
    for i, raw in enumerate(lines, 1):
        s = raw.rstrip()
        code = s.split('//')[0]

        # Detect port list start
        if re.match(r'\s*(input|output|inout)\s+', code):
            in_port_list = True

        if in_port_list:
            # Check each port declaration
            m = re.search(r'(input|output)\s+(wire|reg)?\s*(?:\[\d+:\d+\]\s*)?(\w+)', code)
            if m:
                direction = m.group(1)
                name = m.group(3)
                if direction == 'output' and not name.endswith('_o'):
                    # exempt clock/reset
                    if name in ('clk_i', 'rst_ni', 'rst_i'):
                        if name.endswith('_i') or name.endswith('_ni'):
                            continue
                    warn('W', 'N1', i, f"output port '{name}' should use '_o' suffix")
                elif direction == 'input' and not (name.endswith('_i') or name.endswith('_ni')):
                    # exempt clock/reset
                    if name in ('clk_i', 'rst_ni', 'rst_i'):
                        continue
                    warn('W', 'N1', i, f"input port '{name}' should use '_i' suffix")

        # Detect port list end
        if re.search(r'\)\s*;', code):
            in_port_list = False


def check_default_nettype(lines):
    """First non-comment, non-blank line must be `default_nettype none."""
    for i, raw in enumerate(lines, 1):
        s = raw.strip()
        if not s or s.startswith('//'):
            continue
        if s == '`default_nettype none':
            return
        warn('E', 'C3', i, "missing ``default_nettype none`` as first directive")
        return


def check_file(filepath):
    global FILE, OUT
    FILE = filepath
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
    except Exception as e:
        OUT.append(f"[E] {filepath}: cannot read: {e}")
        return

    check_default_nettype(lines)
    check_c21_multi_stmt(lines)
    check_c19_if_if_chain(lines)
    check_nba_trap1(lines)
    check_nba_trap2(lines)
    check_port_suffix(lines)


def main():
    global OUT
    if len(sys.argv) < 2:
        print("Usage: python rtl_style_check.py <file1.v> [file2.v ...]")
        sys.exit(2)

    for path in sys.argv[1:]:
        check_file(path)

    if OUT:
        for line in OUT:
            print(line)
        errors = sum(1 for o in OUT if o.startswith('[E]'))
        warns = sum(1 for o in OUT if o.startswith('[W]'))
        print(f"\n{len(OUT)} finding(s): {errors} error(s), {warns} warning(s)")
        sys.exit(1)
    else:
        print("All checks PASS")


if __name__ == '__main__':
    main()
