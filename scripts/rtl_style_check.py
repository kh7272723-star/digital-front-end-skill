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


def strip_comments(lines):
    """Return code text with line comments removed."""
    return [line.split('//')[0] for line in lines]


def check_axi_parameter_traps(lines):
    """Catch common AXI burst width traps."""
    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]
        if re.search(r'parameter\s+\w*MAX_BURST\w*\s*=\s*256\b', code):
            warn('W', 'AXI1', i,
                 "MAX_BURST=256 cannot be stored directly in 8 bits; "
                 "AXI AxLEN encodes beats-1, so 256 beats is AxLEN=8'd255")
        if re.search(r'\[\s*7\s*:\s*0\s*\]\s+\w*MAX_BURST\w*', code):
            warn('W', 'AXI1', i,
                 "8-bit max-burst storage cannot represent value 256; "
                 "store beats-1 or use a wider internal count")


def check_unused_response_inputs(lines):
    """Warn when protocol response inputs are declared but never consumed."""
    code_text = '\n'.join(strip_comments(lines))
    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]
        m = re.search(r'\binput\b(?:\s+wire|\s+reg)?(?:\s*\[[^\]]+\])?\s+(\w*(?:resp|bresp|rresp)\w*_i)\b', code)
        if not m:
            continue
        name = m.group(1)
        if len(re.findall(r'\b' + re.escape(name) + r'\b', code_text)) <= 1:
            warn('W', 'PRESP1', i,
                 f"response input '{name}' is declared but not used; "
                 "protocol errors may be dropped instead of reaching completion status")


def check_constant_valid_outputs(lines):
    """Warn on valid-like outputs tied to zero, a common unfinished stub."""
    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]
        if re.search(r'\bassign\s+\w*valid\w*_o\s*=\s*1\'b0\s*;', code):
            warn('W', 'STUB1', i,
                 "valid-like output is tied to 0; document as intentional stub or implement handshake")


def check_ready_high_fifo_drop(lines):
    """Warn when a source is always ready but data is accepted only if FIFO is not full."""
    code_text = '\n'.join(strip_comments(lines))
    ready_names = []
    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]
        m = re.search(r'\bassign\s+(\w*ready\w*_o)\s*=\s*1\'b1\s*;', code)
        if m:
            ready_names.append((i, m.group(1)))

    if not ready_names:
        return

    fifo_gated_write = re.search(
        r'\b\w*(?:wr_en|push|write)\w*\s*=\s*[^;\n]*\b\w*valid\w*_i\b[^;\n]*&&\s*!?\s*\w*full\w*',
        code_text)
    if not fifo_gated_write:
        return

    for line_no, ready_name in ready_names:
        if re.search(r'b_?ready', ready_name):
            continue
        if not re.search(r'(?:rready|wready|tready)', ready_name):
            continue
        warn('W', 'FLOW1', line_no,
             f"'{ready_name}' is tied high while FIFO write is gated by full; "
             "upstream data can be dropped unless ready reflects storage availability")


def check_start_same_cycle_old_q(lines):
    """Warn when start_i captures a register and reads it again in the same clock block."""
    in_seq = False
    in_start = False
    start_depth = 0
    captured = set()

    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]

        if re.search(r'always\s*@\s*\(\s*posedge', code):
            in_seq = True
            in_start = False
            start_depth = 0
            captured = set()
            continue

        if not in_seq:
            continue

        if re.match(r'\s*end\b', code) and not in_start:
            in_seq = False
            continue

        if re.search(r'\bif\s*\(\s*start_i\s*\)', code):
            in_start = True
            start_depth = 0
            captured = set()

        if in_start:
            m = re.match(r'\s*(\w+_q)\s*<=\s*[^;]+;', code)
            if m:
                lhs = m.group(1)
                rhs = code.split('<=', 1)[1]
                for prev in captured:
                    if prev != lhs and re.search(r'\b' + re.escape(prev) + r'\b', rhs):
                        warn('W', 'NBA3', i,
                             f"start_i block reads '{prev}' after assigning it with <= in same block; "
                             "RHS uses the old value. Use a combinational intermediate.")
                captured.add(lhs)

            start_depth += len(re.findall(r'\bbegin\b', code))
            start_depth -= len(re.findall(r'\bend\b', code))
            if start_depth <= 0 and re.search(r'\bend\b', code):
                in_start = False


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
    check_axi_parameter_traps(lines)
    check_unused_response_inputs(lines)
    check_constant_valid_outputs(lines)
    check_ready_high_fifo_drop(lines)
    check_start_same_cycle_old_q(lines)


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
