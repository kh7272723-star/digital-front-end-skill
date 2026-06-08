"""Automated RTL style and structural constraint checker.

Checks C19, C21, NBA traps, port naming, default_nettype, false-pass
testbench patterns, NVMe/DMA traps, and RTL structural purity (FSM/datapath
separation).

Usage: python scripts/rtl_style_check.py [--level L0|L1|L2] <file1.v> [file2.v ...]
Exit code: 0 = clean, 1 = violations found, 2 = usage error.
"""

import os
import argparse
import io
import re
import sys


try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except (AttributeError, io.UnsupportedOperation):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')
    except AttributeError:
        pass

OUT = []
FILE = ""
LEVEL = 'L1'  # default; overridden by --level CLI arg

CONTROL_SUFFIXES = (
    'en', 'we', 're', 'load', 'clr', 'set', 'start', 'stop',
    'push', 'pop', 'fire', 'accept', 'valid', 'ready', 'hold',
    'sel', 'done', 'incr', 'inc',
)


def warn(level, code, line_no, msg):
    """Append a finding. level: E=error, W=warning."""
    OUT.append(f"[{level}][{code}] {FILE}:{line_no}: {msg}")


def _looks_like_testbench(code_text):
    """Best-effort guard so TB-only checks do not fire on RTL implementation files."""
    return bool(re.search(r'\bmodule\s+tb\w*|\binitial\s+begin|\btask\b', code_text))


def check_c21_multi_stmt(lines):
    """C21: one statement per line - detect '; ' or ';\\t' followed by non-comment code."""
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
                     f"(previous if line {prev_if_line}) - "
                     f"may indicate missing else-if chain")
            prev_if_line = i
            prev_had_else = False

        # Detect 'else if' or 'else begin' - marks the previous if as closed
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
                             f"in same always block - uses pre-NBA (old) value. "
                             f"Consider combinational output instead.")


def check_nba_trap2(lines):
    """NBA Trap 2: advancing read pointer + registered data from same indexed memory.

    Detects: inside always @(posedge), rd_ptr_q advances and data_o gets
    mem[rd_ptr_q] - data_o gets old slot because pointer advanced via NBA.
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
                     f"while '{idx}' advances in same block - "
                     f"data shifts by 1 beat. Use combinational read instead.")


def check_port_suffix(lines):
    """Verify port suffixes: outputs use _o, inputs use _i."""
    in_module_port_list = False
    in_task_or_func = False
    ANSI_TYPE_TOKENS = {'wire', 'reg', 'logic', 'signed', 'unsigned', 'integer'}

    for i, raw in enumerate(lines, 1):
        s = raw.rstrip()
        code = s.split('//')[0]

        # Track task/function blocks to exclude their arguments
        if re.match(r'\s*(task|function)\b', code):
            in_task_or_func = True
        if in_task_or_func:
            if re.search(r'\bendtask\b|\bendfunction\b', code):
                in_task_or_func = False
            continue

        # Detect module port list start (ANSI style: input/output inside module header)
        if re.match(r'\s*(input|output|inout)\s+', code):
            in_module_port_list = True

        if in_module_port_list:
            # ANSI port: direction [type] [signed] [width] name
            # Skip type tokens like wire/reg/logic/signed
            m = re.match(
                r'\s*(input|output|inout)\s+'
                r'(?:(wire|reg|logic|integer)\s+)?'
                r'(?:signed\s+)?'
                r'(?:\[\d+:\d+\]\s+)?'
                r'(\w+)',
                code)
            if m:
                direction = m.group(1)
                type_tok = m.group(2)
                name = m.group(3)
                # Skip if name is actually a type token (multi-word port with type on separate line)
                if name in ANSI_TYPE_TOKENS:
                    continue
                if direction == 'output' and not name.endswith('_o'):
                    if name in ('clk_i', 'rst_ni', 'rst_i'):
                        if name.endswith('_i') or name.endswith('_ni'):
                            continue
                    warn('W', 'N1', i, f"output port '{name}' should use '_o' suffix")
                elif direction == 'input' and not (name.endswith('_i') or name.endswith('_ni')):
                    if name in ('clk_i', 'rst_ni', 'rst_i'):
                        continue
                    warn('W', 'N1', i, f"input port '{name}' should use '_i' suffix")

        # Detect port list end
        if re.search(r'\)\s*;', code):
            in_module_port_list = False


def check_default_nettype(lines):
    """First non-comment, non-blank line must be `default_nettype none."""
    for i, raw in enumerate(lines, 1):
        s = raw.lstrip('\ufeff').strip()
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
                 "protocol errors may be silently dropped. "
                 "Must either propagate to completion status or document as intentional waiver.")


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


def check_tb_false_pass_patterns(lines):
    """Warn when $display shows data mismatch without error_cnt increment nearby."""
    code_text = '\n'.join(strip_comments(lines))
    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]
        # Look for $display with "mismatch" — a strong false-pass indicator.
        # "exp"/"expected" skipped: they appear in benign format strings
        # like $display("data=%h exp=%h", data, expected) which are
        # informational, not actual data checks.
        m = re.search(r'\$display\s*\(\s*"[^"]*\bmismatch\b', code, re.IGNORECASE)
        if not m:
            continue
        # Check next 5 lines for error_cnt++ or error_cnt <= error_cnt + 1 or $fatal or check(
        nearby = '\n'.join(lines[i:min(i+5, len(lines))])
        if not re.search(r'(error_cnt\b|fail_cnt\b|err_cnt\b).*\+(?:\s*1|=\s*1)', nearby) \
           and not re.search(r'\$fatal\b', nearby) \
           and not re.search(r'\bcheck\s*\(', nearby):
            warn('W', 'TB_FPASS1', i,
                 "$display with 'exp'/expected/mismatch' without error_cnt++ or $fatal nearby; "
                 "data check may be invisible to pass/fail logic -> false-pass risk")


def check_nvm_offset_page_reset(lines):
    """Warn when NVM offset is cleared on page accept while NVM addr = slba + offset."""
    code_text = '\n'.join(strip_comments(lines))
    lines_lower = '\n'.join(l.lower() for l in strip_comments(lines))

    has_offset_q = re.search(r'\b(nvm_offset_q|nvm_byte_offset_q|global_offset)\b', lines_lower)
    has_page_valid = re.search(r'\bpage_valid_i?\b\s*&&', lines_lower)
    offset_reset_pattern = re.search(
        r'(page_valid|page_ready|page_accept)[\s\S]*?'
        r'\b(nvm_offset_q|nvm_byte_offset_q|source_offset)\s*(?:<=\s*0|\s*<=\s*\d+\'b0)',
        lines_lower)
    addr_pattern = re.search(
        r'(nvm_addr|src_addr|lba_src).*\b(slba|lba_base).*\+\s*\{?.*\b(nvm_offset|byte_offset)',
        lines_lower)

    if has_offset_q and offset_reset_pattern and addr_pattern:
        found = False
        for i, raw in enumerate(lines, 1):
            code = raw.split('//')[0].lower()
            # Find the offset reset assignment line
            if re.search(r'\b(nvm_offset|byte_offset|source_offset)\w*\s*<=\s*(?:\d+\'b)?0\s*;', code):
                # Check preceding 5 lines for page_valid/page_ready context
                context = '\n'.join(l.split('//')[0].lower() for l in lines[max(0,i-5):i])
                if re.search(r'\b(page_valid|page_ready)\w*\s*&&', context):
                    warn('W', 'RTL_NVM1', i,
                         "NVM source offset reset to 0 under page_valid/page_ready context "
                         "while nvm_addr = slba + offset; multi-page reads will repeat source data. "
                         "Source offset must be global, not per-page.")
                    found = True
                    break
        if not found:
            # Fallback: check if any line with nvm_offset <= 0 is within begin/end of page_valid block
            pass


def check_prp_list_buffer_mismatch(lines):
    """Warn when PRP LIST_ENTRIES parameter doesn't match list buffer depth or ARLEN."""
    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]
        m = re.search(r'parameter\s+(\w*LIST_ENTRIES\w*)\s*=\s*(\d+)', code)
        if not m:
            continue
        list_entries = int(m.group(2))
        # Find list buffer depth declaration
        full_text = '\n'.join(lines)
        buf_m = re.search(r'reg\s*\[[^\]]+\]\s+(\w*list_buf\w*)\s*\[0?\s*:\s*(\d+)\]', full_text)
        if buf_m:
            buf_depth = int(buf_m.group(2)) + 1
            if list_entries > buf_depth:
                warn('W', 'RTL_PRP1', i,
                     f"LIST_ENTRIES={list_entries} but list_buf depth={buf_depth}; "
                     f"buffer cannot hold full PRP list -> overflow or insufficient entries")

        # Also check ARLEN
        arlen_m = re.search(r'list_ar_len\w*\s*=\s*(?:\d+\'d)?(\d+)', full_text)
        if arlen_m:
            arlen = int(arlen_m.group(1))
            if list_entries > 64 and arlen == 63:
                warn('W', 'RTL_PRP1', i,
                     f"LIST_ENTRIES={list_entries} but ARLEN={arlen} (64 beats); "
                     f"cannot fetch more than 64 entries per list page. "
                     f"May need multi-page PRP list chaining.")


def check_w_active_no_data_gating(lines):
    """Warn when WVALID asserts on AW handshake without FIFO/have_next gating."""
    code_text = '\n'.join(strip_comments(lines))
    # Pattern: w_active or wvalid set on AW handshake condition
    w_on_aw = re.search(
        r'(?:aw_active_q|aw_valid_o).*?(?:axi_aw_ready|aw_ready).*?begin\s+'
        r'(?:w_active_q|w_valid|m_axi_wvalid)\s*<=.*?1\'b1',
        code_text, re.DOTALL)
    if not w_on_aw:
        return

    # Check if fifo_empty or have_data check exists in same condition block
    has_data_check = re.search(
        r'(?:aw_active.*?aw_ready).*?begin\s*'
        r'.*?(?:!fifo_empty|fifo_count\s*>\s*0|have_data|have_next_wbeat).*?'
        r'(?:w_active|w_valid|wvalid)\s*<=.*?1\'b1',
        code_text, re.DOTALL)

    if not has_data_check:
        for i, raw in enumerate(lines, 1):
            code = raw.split('//')[0].lower()
            if re.search(r'w_active|w_valid|wvalid_o', code) and \
               re.search(r'<=.*1\'b1', code):
                # Find the preconditions in nearby lines
                context = '\n'.join(lines[max(0,i-10):min(len(lines),i+3)])
                if re.search(r'aw.*ready|aw_valid.*aw_ready', context, re.IGNORECASE) \
                   and not re.search(r'fifo_empty|fifo_cnt|have_data|have_next', context, re.IGNORECASE):
                    warn('W', 'RTL_WEMPTY1', i,
                         "WVALID/WACTIVE set on AW handshake without FIFO data availability check; "
                         "may assert WVALID with stale/empty data. Add !fifo_empty or have_next gate.")
                    break



def _strip_line_comment(raw):
    return _strip_string_contents(raw).split('//')[0]


def _strip_string_contents(code):
    """Replace string literal contents with empty string to avoid false matches
    inside format strings like $display("data=%h exp=%h", data, exp)."""
    return re.sub(r'"[^"\\]*(?:\\.[^"\\]*)*"', '""', code)


def _collect_always_blocks(lines, pattern):
    """Return (start_line, [(line_no, raw_line), ...]) for matching always blocks."""
    blocks = []
    in_block = False
    start_line = 0
    block = []
    depth = 0

    for i, raw in enumerate(lines, 1):
        code = _strip_line_comment(raw)
        if not in_block:
            if re.search(pattern, code):
                in_block = True
                start_line = i
                block = [(i, raw)]
                depth = len(re.findall(r'\bbegin\b', code)) - len(re.findall(r'\bend\b', code))
                if depth <= 0:
                    depth = 1
            continue

        block.append((i, raw))
        depth += len(re.findall(r'\bbegin\b', code))
        depth -= len(re.findall(r'\bend\b', code))
        if depth <= 0 and re.search(r'\bend\b', code):
            blocks.append((start_line, block))
            in_block = False
            start_line = 0
            block = []
            depth = 0

    if in_block and block:
        blocks.append((start_line, block))
    return blocks


def _block_code(block):
    return '\n'.join(_strip_line_comment(raw) for _, raw in block)


def _declared_scalar_signals(lines):
    """Return signal names declared as scalar or explicit [0:0].

    This is intentionally conservative. It covers common ANSI/non-ANSI Verilog
    one-line declarations used by generated RTL; unknown widths are not treated
    as scalar unless the declaration omits a range.
    """
    scalars = set()
    decl_re = re.compile(
        r'\b(?:input|output|inout|wire|reg|logic)\b'
        r'(?:\s+(?:wire|reg|logic|signed))*\s*'
        r'(?P<range>\[[^\]]+\])?\s*(?P<names>[^;]+);')
    ansi_port_re = re.compile(
        r'^\s*(?:input|output|inout)\b'
        r'(?:\s+(?:wire|reg|logic|signed))*\s*'
        r'(?P<range>\[[^\]]+\])?\s*(?P<name>[A-Za-z_]\w*)\s*[,)]?')
    for raw in lines:
        code = _strip_line_comment(raw).strip()
        m = decl_re.search(code)
        if m:
            width = (m.group('range') or '').replace(' ', '')
            if width and width != '[0:0]':
                continue
            for item in m.group('names').split(','):
                item = item.strip()
                name_m = re.match(r'([A-Za-z_]\w*)', item)
                if name_m:
                    scalars.add(name_m.group(1))
            continue

        m = ansi_port_re.search(code)
        if m:
            width = (m.group('range') or '').replace(' ', '')
            if not width or width == '[0:0]':
                scalars.add(m.group('name'))
    return scalars


def _is_control_name(name):
    for suffix in CONTROL_SUFFIXES:
        if re.search(rf'_{suffix}(?:_o|_q|_d|_r)?$', name):
            return True
    return False


def check_fsm_comb_multi_bit(lines):
    """RTL_STRUCTURAL_PURITY_RSP2: multi-bit datapath assignment in FSM comb decode.

    In L2 projects, RSP2 violations are E-level (hard error) because FSM/datapath
    separation is mandatory for multi-module integration.  In L0/L1, RSP2 is W-level.
    """
    scalar_signals = _declared_scalar_signals(lines)
    for start_line, block in _collect_always_blocks(lines, r'always\s*@\s*\(\s*\*\s*\)'):
        text = _block_code(block)
        # Treat as an FSM comb block only when it mentions state machinery.
        if not re.search(r'\b(cstate|nstate)\b|\bcase\s*\(\s*cstate\s*\)', text):
            continue

        for line_no, raw in block:
            code = _strip_line_comment(raw)
            m = re.match(r'\s*(\w+)\s*=\s*[^=][^;]*;', code)
            if not m:
                continue
            lhs = m.group(1)
            if lhs == 'nstate':
                continue
            if _is_control_name(lhs) and lhs in scalar_signals:
                continue
            # Sideband and datapath-like names are not control signals even if 1-bit.
            suspicious = re.search(
                r'(_addr|_data|_bytes|_cnt|_count|_ptr|_idx|_offset|_len|'
                r'_beats|_burst|_next|_last|_strb|_keep|page_[a-z]|nvm_[a-z])',
                lhs)
            if suspicious or lhs.endswith('_n'):
                level = 'E' if LEVEL == 'L2' else 'W'
                warn(level, 'RTL_STRUCTURAL_PURITY_RSP2', line_no,
                     f"'{lhs}' assigned in FSM combinational block; "
                     "FSM comb must produce only nstate and single-bit control signals. "
                     "Move datapath/sideband values to datapath logic or add a waiver.")


def check_datapath_has_cstate(lines):
    """RTL_STRUCTURAL_PURITY_RSP3 (E-level): datapath sequential blocks must not
    reference cstate or S_* state IDs. Gate datapath updates with named FSM control
    signals instead."""
    for start_line, block in _collect_always_blocks(lines, r'always\s*@\s*\(\s*posedge'):
        text = _block_code(block)
        # Skip the dedicated state register block.
        if re.search(r'\bcstate\s*<=', text):
            continue
        if not re.search(r'\bcstate\b|\bS_\w+\b', text):
            continue
        for line_no, raw in block:
            code = _strip_line_comment(raw)
            if re.search(r'\bcstate\b', code) or re.search(r'\bS_\w+\b', code):
                warn('E', 'RTL_STRUCTURAL_PURITY_RSP3', line_no,
                     f"datapath sequential block references cstate or S_*; "
                     f"gate datapath updates with named FSM control signals instead.")


def check_fsm_seq_has_datapath(lines):
    """RTL_STRUCTURAL_PURITY_RSP1: state register block must not update datapath."""
    for start_line, block in _collect_always_blocks(lines, r'always\s*@\s*\(\s*posedge'):
        text = _block_code(block)
        if not re.search(r'\bcstate\s*<=', text):
            continue
        for line_no, raw in block:
            code = _strip_line_comment(raw)
            for lhs in re.findall(r'\b(\w+)\s*<=', code):
                if lhs == 'cstate':
                    continue
                warn('E', 'RTL_STRUCTURAL_PURITY_RSP1', line_no,
                     f"'{lhs}' assigned in same sequential block as cstate; "
                     "the FSM state-register block must update only cstate. "
                     "Move this register to a datapath sequential block.")

def check_tb_unbounded_wait(lines):
    """TB_WAIT1: detect unbounded while/wait loops without cycle timeout or $fatal."""
    code_text = '\n'.join(strip_comments(lines))
    if not re.search(r'\b(module\s+tb\w*|\$display\b|initial\s+begin|\btask\b)', code_text):
        return

    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]
        # Detect single-line and multi-line while/wait constructs in testbenches.
        m = re.search(r'\bwhile\s*\(', code)
        if not m:
            m = re.search(r'\bwait\s*\(', code)
        if not m:
            continue
        if re.search(r'\bwhile\s*\([^)]*\)\s*@\s*\(\s*posedge', code) and \
           not re.search(r'(cycle|timeout|limit|max|\$fatal|\$finish)', code, re.IGNORECASE):
            warn('W', 'TB_WAIT1', i,
                 "single-line while wait has no local cycle timeout; "
                 "nearby unrelated timeout variables do not guard this loop")
            continue
        # Check nearby lines for timeout/cycle_budget/fatal/finish. The forward
        # window covers multi-line loops such as "while (!done) begin".
        ctx_start = max(0, i - 10)
        ctx_end = min(len(lines), i + 40)
        context = '\n'.join(lines[ctx_start:ctx_end])
        has_guard = re.search(
            r'(cycle_cnt|wait_cnt|timeout|MAX_CYCLES|TIMEOUT|\$fatal|\$finish|fork\s*:.*timeout)',
            context,
            re.IGNORECASE | re.DOTALL)
        guarded_condition = re.search(
            r'\bwhile\s*\([^)]*(cycle|timeout|limit|max)[^)]*\)',
            code,
            re.IGNORECASE)
        if not has_guard and not guarded_condition:
            warn('W', 'TB_WAIT1', i,
                 "unbounded while/wait without cycle timeout or $fatal; "
                 "add cycle budget (e.g. while(cond && cycle_cnt < 150000)) or timeout guard")


def check_tb_capture_without_expected(lines):
    """TB_CAPCNT1: detect cap_cnt/captured without expected_beats/expected_count reference."""
    code_text = '\n'.join(strip_comments(lines))
    cap_re = re.search(
        r'\b(cap_cnt|captured_beats|w_cap_cnt|beat_cnt)\b\s*(?:<=|=)\s*\b\1\b\s*\+\s*(?:\d+|[0-9]+\'[bdh][0-9a-fA-F]+)|'
        r'\b(cap_cnt|captured_beats|w_cap_cnt|beat_cnt)\b\s*\+\+',
        code_text)
    if not cap_re:
        return
    has_expected = re.search(r'\b(expected_beats|expected_count|expected_txns|total_beats)\b', code_text)
    if not has_expected:
        for i, raw in enumerate(lines, 1):
            code = raw.split('//')[0]
            if re.search(r'\b(cap_cnt|captured_beats|w_cap_cnt|beat_cnt)\b\s*(?:<=|=)\s*\b\1\b\s*\+', code) or \
               re.search(r'\b(cap_cnt|captured_beats|w_cap_cnt|beat_cnt)\b\s*\+\+\s*;', code):
                warn('W', 'TB_CAPCNT1', i,
                     "captured beat counter without expected_beats/expected_count reference; "
                     "testbench can pass without verifying correct number of beats received")


def check_tb_status_unchecked(lines):
    """TB_STATUS1: detect cpl_status/cpl_status_o connected but never compared."""
    code_text = '\n'.join(strip_comments(lines))
    if not _looks_like_testbench(code_text):
        return
    # Check if cpl_status is wired (declared or connected) but never checked
    has_status_decl = re.search(r'\b(cpl_status|cpl_status_o|status_o)\b', code_text)
    if not has_status_decl:
        return
    # Check if it's ever compared or error-checked
    has_status_check = re.search(
        r'\bcpl_status\w*\s*(?:!==?|==)\s*\d+\'[bh]\d+|'
        r'status\w*\s*(?:!==?|==)\s*\d+\'[bh]0+\b|'
        r'\bcheck.*status|status.*error|status_err',
        code_text)
    if not has_status_check:
        for i, raw in enumerate(lines, 1):
            code = raw.split('//')[0]
            if re.search(r'\b(cpl_status|cpl_status_o)\b', code) and \
               not re.search(r'(check|error|assert|TEST_FAIL|test_err|!==|==)', code):
                warn('W', 'TB_STATUS1', i,
                     "cpl_status is connected but never compared/checked in testbench; "
                     "completion errors silently pass. Add status verification.")


def _lhs_assignments_in_always_block(block):
    """Return {lhs: first_line} for procedural assignments in one always block."""
    lhs_lines = {}
    control_prefix = re.compile(r'^\s*(?:if|else\s+if|while|for|case)\b')
    assign_re = re.compile(r'\b([A-Za-z_]\w*)\s*(?:\[[^\]]+\])?\s*(?:<=|(?<![=!<>])=(?!=))')
    skip_lhs = {
        'if', 'else', 'for', 'while', 'case', 'begin', 'end',
        'wire', 'reg', 'logic', 'integer', 'genvar',
        'parameter', 'localparam', 'assign'
    }

    for line_no, raw in block:
        code = _strip_line_comment(raw).strip()
        if not code:
            continue
        if re.match(r'^\s*(?:assert|assume|cover)\s*\(', code):
            continue
        # Strip string contents to avoid false matches inside $display format
        # strings (e.g. "$display("data=%h exp=%h", data, exp)" would match
        # 'data' as LHS after the '=' in the format string).
        code_stripped = _strip_string_contents(code)
        # Skip pure control predicates such as "if (cnt <= max) begin".
        # Single-line guarded assignments are still recognized after the ")".
        if control_prefix.match(code):
            m_inline = re.match(r'^\s*(?:if|else\s+if|while)\s*\([^)]*\)\s*([A-Za-z_]\w*)\s*(?:<=|(?<![=!<>])=(?!=))', code_stripped)
            if m_inline:
                lhs = m_inline.group(1)
                if lhs not in skip_lhs and lhs not in lhs_lines:
                    lhs_lines[lhs] = line_no
            continue

        for m in assign_re.finditer(code_stripped):
            lhs = m.group(1)
            if lhs in skip_lhs:
                continue
            # Fix false-positive: <= inside parenthesized expressions is relational, not procedural assignment
            full_match = m.group(0)
            if full_match.rstrip().endswith('<='):
                before = code_stripped[:m.start()]
                if before.count('(') > before.count(')'):
                    continue
            if lhs not in lhs_lines:
                lhs_lines[lhs] = line_no
    return lhs_lines


def check_multi_driver(lines):
    """RTL_MULTI_DRIVER1: detect same reg/logic assigned in multiple always blocks."""
    signal_to_blocks = {}
    for start_line, block in _collect_always_blocks(lines, r'\balways\b'):
        for lhs, line_no in _lhs_assignments_in_always_block(block).items():
            signal_to_blocks.setdefault(lhs, []).append((start_line, line_no))

    for sig, hits in sorted(signal_to_blocks.items()):
        block_starts = sorted(set(start for start, _ in hits))
        if len(block_starts) < 2:
            continue
        assign_lines = ', '.join(str(line_no) for _, line_no in hits)
        block_lines = ', '.join(str(start) for start in block_starts)
        warn('E', 'RTL_MULTI_DRIVER1', hits[0][1],
             f"'{sig}' assigned in {len(block_starts)} different always blocks "
             f"(always lines {block_lines}; assignment lines {assign_lines}); "
             "multi-driven registers cause synthesis errors or simulation X. "
             "Merge into a single procedural owner or split into separate next-value signals.")
        break  # one finding per file is enough


def check_tb_fake_false_pass_audit(lines):
    """TB_FPASS_AUDIT1: detect fake false-pass audit that only displays text."""
    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]
        if not (re.search(r'\$display', code) and
                re.search(r'[Aa]udit|FALSE.?PASS|false.?pass|log.?audit', code)):
            continue

        # A real audit has conditionals/assertions/fatal/error increments in the
        # audit region itself, not just somewhere else in the testbench.
        window = '\n'.join(_strip_line_comment(l) for l in lines[i:min(len(lines), i + 25)])
        has_real_check = re.search(
            r'(\bif\s*\(|\$fatal\b|\bassert\s*\(|'
            r'(?:error_cnt|fail_cnt|total_err|test_err)\s*(?:<=|=)\s*'
            r'(?:error_cnt|fail_cnt|total_err|test_err)\s*\+\s*1|'
            r'\bcheck_\w+\s*\()',
            window)
        # Ignore the final "if total_errors==0 print ALL_TESTS_PASS" if it is
        # before the audit display and the audit body itself is display-only.
        if not has_real_check:
            warn('W', 'TB_FPASS_AUDIT1', i,
                 "false-pass audit text displayed but the audit region has no "
                 "condition, assertion, $fatal, check task, or error-count update; "
                 "audit is cosmetic only.")
            break


def check_tb_empty_if_comparisons(lines):
    """TB_EMPTY_IF1: reject empty if-statements that look like checks."""
    code_text = '\n'.join(strip_comments(lines))
    if not _looks_like_testbench(code_text):
        return

    for i, raw in enumerate(lines, 1):
        code = _strip_line_comment(raw).strip()
        if not code:
            continue
        if re.search(r'\bif\s*\([^)]*(?:==|===|!=|!==)[^)]*\)\s*;\s*$', code):
            warn('E', 'TB_EMPTY_IF1', i,
                 "empty if-statement contains a comparison but has no action; "
                 "this is cosmetic scoreboard evidence. Increment an error "
                 "counter, call $fatal, or use a real check task.")


def check_tb_wlast_boolean_only(lines):
    """TB_WLAST_BOOL1: catch WLAST checks that only reject X/Z values."""
    code_text = '\n'.join(strip_comments(lines))
    if not _looks_like_testbench(code_text):
        return
    if not re.search(r'\b(wlast|m_axi_wlast|axi_wlast)\b', code_text, re.IGNORECASE):
        return
    has_exact_wlast = re.search(
        r'\b(?:m_axi_)?wlast\b\s*(?:==|===|!=|!==)\s*'
        r'(?:expected_\w*last\w*|exp_\w*last\w*|\w*_expected_wlast)\b|'
        r'\b(?:expected_\w*last\w*|exp_\w*last\w*|\w*_expected_wlast)\b'
        r'\s*(?:==|===|!=|!==)\s*\b(?:m_axi_)?wlast\b|'
        r'\bcheck_\w+\s*\([^;)]*(?:wlast|m_axi_wlast)[^;)]*expected',
        code_text, re.IGNORECASE)
    if has_exact_wlast:
        return

    for i, raw in enumerate(lines, 1):
        code = _strip_line_comment(raw)
        if re.search(
                r'\b(?:m_axi_)?wlast\b[^;\n]*!==\s*1\'b1[^;\n]*&&'
                r'[^;\n]*\b(?:m_axi_)?wlast\b[^;\n]*!==\s*1\'b0',
                code, re.IGNORECASE):
            warn('E', 'TB_WLAST_BOOL1', i,
                 "WLAST check only proves the signal is 0 or 1; it does not "
                 "prove WLAST asserted on the expected final beat. Compare "
                 "against an expected beat index or expected_wlast signal.")


def check_tb_completion_count_exact(lines):
    """TB_CPL_COUNT1: completion count must be exact when a counter is used."""
    code_text = '\n'.join(strip_comments(lines))
    if not _looks_like_testbench(code_text):
        return
    if not re.search(r'\b(cpl_count|completion_count|done_count)\b', code_text):
        return

    has_min_only = re.search(
        r'\b(cpl_count|completion_count|done_count)\b\s*<\s*(?:\d+\'d)?1\b',
        code_text)
    has_exact = re.search(
        r'\b(cpl_count|completion_count|done_count)\b\s*(?:==|===|!=|!==)\s*'
        r'(?:expected_\w+|[A-Za-z_]\w*expected\w*|\d+\'d\d+|\d+)\b',
        code_text, re.IGNORECASE)
    has_expected_counter = re.search(
        r'\bexpected_(?:cpl|completion|done)_count\b|'
        r'\b(?:cpl|completion|done)_expected\b',
        code_text, re.IGNORECASE)

    if has_min_only and not (has_exact or has_expected_counter):
        line_no = 1
        for i, raw in enumerate(lines, 1):
            if re.search(
                    r'\b(cpl_count|completion_count|done_count)\b\s*<\s*(?:\d+\'d)?1\b',
                    _strip_line_comment(raw)):
                line_no = i
                break
        warn('E', 'TB_CPL_COUNT1', line_no,
             "completion counter is checked only as '< 1'. This permits "
             "duplicate completions to pass. Check the exact expected count "
             "and reject over-completion.")


def check_tb_xz_coverage(lines):
    """TB_XZ1: DMA/protocol TB must actively fail on X/Z in observed signals."""
    code_text = '\n'.join(strip_comments(lines))
    if not re.search(r'\bmodule\s+tb\w*|\binitial\s+begin|\btask\b', code_text):
        return
    observes_protocol_data = re.search(
        r'\b(m_axi_wdata|m_axi_awaddr|cpl_status|nvm_rd_data|sb_data|scoreboard|wdata|rdata)\b',
        code_text)
    if not observes_protocol_data:
        return
    has_xz_check = re.search(
        r'\$isunknown\b|\bhas_x\b|\bxz_check\b|unknown|'
        r'===\s*\d+\'[bhd][xXzZ]|\!==\s*\d+\'[bhd][xXzZ]',
        code_text,
        re.IGNORECASE)
    if not has_xz_check:
        warn('W', 'TB_XZ1', 1,
             "testbench observes protocol/data signals but has no $isunknown/X/Z "
             "failure check; X-injected simulations can print ALL_TESTS_PASS.")


def check_tb_sideband_trace(lines):
    """TB_SIDEBAND1: important sideband outputs must be connected and checked."""
    code_text = '\n'.join(strip_comments(lines))
    if not re.search(r'\bmodule\s+tb\w*|\binitial\s+begin|\btask\b', code_text):
        return

    critical = {
        'busy': r'\bbusy\b',
        'cpl_bytes_written': r'\bcpl_bytes_written\b',
        'cpl_status': r'\bcpl_status\b|\brcv_status\b',
        'm_axi_awaddr': r'\bm_axi_awaddr\b|\bawaddr\b|\baw_addr\b',
        'm_axi_awlen': r'\bm_axi_awlen\b|\bawlen\b|\baw_len\b',
        'm_axi_wstrb': r'\bm_axi_wstrb\b|\bwstrb\b',
    }

    # Stricter expected-value check for byte-count sidebands: assigning to a
    # local variable or displaying is NOT sufficient — must compare against
    # expected_bytes / expected_count.
    byte_count_strict = {
        'cpl_bytes_written',
    }

    for name, pattern in critical.items():
        if not re.search(pattern, code_text):
            continue
        if re.search(r'\.' + re.escape(name) + r'\s*\(\s*\)', code_text):
            for i, raw in enumerate(lines, 1):
                if re.search(r'\.' + re.escape(name) + r'\s*\(\s*\)', raw):
                    warn('W', 'TB_SIDEBAND1', i,
                         f"critical sideband '{name}' is left unconnected in the TB; "
                         "contract-to-test trace is incomplete.")
                    break
            continue

        has_check = False
        is_strict = name in byte_count_strict
        for raw in lines:
            code = _strip_line_comment(raw)
            if re.search(r'check_\w+\s*\([^;]*' + pattern, code, re.IGNORECASE):
                has_check = True
            if is_strict:
                # Strict: must compare against expected_bytes/expected_count,
                # not just any comparison or assignment to a local variable.
                if re.search(pattern + r'\s*(?:==|!=|===|!==)\s*\w*(expected|exp)\w*', code, re.IGNORECASE):
                    has_check = True
                if re.search(r'(?:expected|exp)\w*\s*(?:==|!=|===|!==)\s*' + pattern, code, re.IGNORECASE):
                    has_check = True
            else:
                if re.search(pattern + r'\s*(?:==|!=|===|!==|<|>)', code, re.IGNORECASE):
                    has_check = True
                if re.search(pattern + r'.*(?:expected|exp|mismatch|fail|error)', code, re.IGNORECASE):
                    has_check = True
                if re.search(r'(?:expected|exp)_\w*' + pattern, code, re.IGNORECASE):
                    has_check = True
        if not has_check:
            for i, raw in enumerate(lines, 1):
                if re.search(pattern, raw):
                    warn('W', 'TB_SIDEBAND1', i,
                         f"critical sideband '{name}' appears in TB but is not "
                         "compared against an expected value; add contract-to-test check or waiver.")
                    break


def check_tb_timeout_finish_only(lines):
    """TB_TIMEOUT_FATAL1: timeout block that prints TIMEOUT then calls $finish
    without $fatal or error_cnt increment is a false-pass risk."""
    code_text = '\n'.join(strip_comments(lines))
    if not _looks_like_testbench(code_text):
        return

    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]
        # Detect timeout-related display
        if not re.search(r'TIMEOUT|timeout|HANG|simulation.*timeout', code, re.IGNORECASE):
            continue
        if not re.search(r'\$display', code):
            continue
        # Look ahead for $finish without $fatal or error counter increment
        window = '\n'.join(_strip_line_comment(l) for l in lines[i:min(len(lines), i + 10)])
        has_fatal = re.search(r'\$fatal\b', window)
        has_error_inc = re.search(
            r'(error_cnt|fail_cnt|total_err|test_err|err_cnt)\s*(?:<=|=)\s*\1\s*\+',
            window)
        has_finish = re.search(r'\$finish\b', window)
        has_tests_failed = re.search(r'TESTS_FAILED|TEST_FAIL', window, re.IGNORECASE)
        if has_finish and not has_fatal and not has_error_inc and not has_tests_failed:
            warn('E', 'TB_TIMEOUT_FATAL1', i,
                 "timeout/emergency block prints TIMEOUT and calls $finish "
                 "without $fatal or error_cnt increment or TESTS_FAILED; "
                 "process exit code is still 0 — naive gate misjudges success. "
                 "Use $fatal or increment error counter and print TESTS_FAILED.")


def check_tb_completion_only(lines):
    """TB_COMPLETION_ONLY1: DMA/NVMe TB that checks completion status/bytes
    but never compares AWADDR/AWLEN/WSTRB/WLAST/BRESP."""
    code_text = '\n'.join(strip_comments(lines))
    if not _looks_like_testbench(code_text):
        return
    # Must be a DMA/NVMe context
    if not re.search(r'(axi|nvme|dma|m_axi|awaddr|awlen|wstrb|wlast|bresp)', code_text, re.IGNORECASE):
        return

    # Check for transaction-shape comparisons
    has_awaddr = re.search(
        r'(?:m_axi_awaddr|aw_addr|awaddr)\s*(?:==|===|!=|!==)|'
        r'check_\w+.*(?:awaddr|aw_addr)',
        code_text, re.IGNORECASE)
    has_awlen = re.search(
        r'(?:m_axi_awlen|aw_len|awlen)\s*(?:==|===|!=|!==)|'
        r'check_\w+.*(?:awlen|aw_len)',
        code_text, re.IGNORECASE)
    has_wstrb = re.search(
        r'(?:m_axi_wstrb|wstrb)\s*(?:==|===|!=|!==)|'
        r'check_\w+.*wstrb',
        code_text, re.IGNORECASE)
    has_wlast = re.search(
        r'(?:m_axi_wlast|wlast)\s*(?:==|===|!=|!==)|'
        r'check_\w+.*wlast',
        code_text, re.IGNORECASE)
    has_bresp = re.search(
        r'(?:m_axi_bresp|bresp)\s*(?:==|===|!=|!==)|'
        r'check_\w+.*bresp',
        code_text, re.IGNORECASE)

    if has_awaddr and has_awlen and has_wstrb and has_wlast and has_bresp:
        return  # all checked

    missing = []
    if not has_awaddr: missing.append('AWADDR')
    if not has_awlen: missing.append('AWLEN')
    if not has_wstrb: missing.append('WSTRB')
    if not has_wlast: missing.append('WLAST')
    if not has_bresp: missing.append('BRESP')

    warn('E', 'TB_COMPLETION_ONLY1', 1,
         f"DMA/NVMe testbench checks completion but never compares "
         f"transaction-shape fields: {', '.join(missing)}. "
         f"Beat count alone can false-pass. Add transaction-shape scoreboard.")


def check_parameter_hardcode(lines):
    """PARAM_HARDCODE1/PARAM_PARTSEL1: catch fake parameterization and unsafe parameter slicing."""
    code_text = '\n'.join(strip_comments(lines))
    has_capacity_param = re.search(r'\bparameter\s+\w*(?:DEPTH|COUNT|WIDTH|OUTSTANDING)\w*\b', code_text)

    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]
        if has_capacity_param and re.search(r'\$clog2\s*\(\s*512\s*\)|\[\s*\$clog2\s*\(\s*512\s*\)\s*:\s*0\s*\]', code):
            warn('W', 'PARAM_HARDCODE1', i,
                 "local capacity hardcodes 512 while the design has configurable depth/count parameters; "
                 "derive widths from the parameter or document a waiver.")

        m = re.search(r'\b([A-Z][A-Z0-9_]*)\s*\[\s*(\d+)\s*:\s*(\d+)\s*\]', code)
        if m and int(m.group(2)) >= 32:
            warn('W', 'PARAM_PARTSEL1', i,
                 f"wide part-select on untyped parameter/localparam '{m.group(1)}' can exceed its inferred width; "
                 "cast with an explicitly sized localparam/wire before slicing.")


def check_nvme_prp_list_tb_coverage(lines):
    """TB_PRP_LIST1/TB_PRP_AWADDR1: catch weak PRP-list multi-page tests."""
    code_text = '\n'.join(strip_comments(lines))
    if not re.search(r'PRP\s*list|prp_list', code_text, re.IGNORECASE):
        return
    four_page_test = re.search(r'16\s*[Kk][Bb]|16384|16\'d31|NLB\s*=\s*31|4\s*pages?', code_text, re.IGNORECASE)
    if not four_page_test:
        return

    idx_values = set()
    for raw in lines:
        code = raw.split('//')[0]
        m = re.search(r'\bprp_list_wr_idx\b\s*(?:<=|=)\s*(?:\d+\'d)?(\d+)\b', code)
        if m:
            idx_values.add(int(m.group(1)))

    if len(idx_values) < 3:
        warn('W', 'TB_PRP_LIST1', 1,
             "4-page PRP-list test appears to preload fewer than 3 data entries; "
             "PRP2 is a list pointer, not a data page, so PRP1 + three list data entries are required.")

    has_awaddr_check = any(
        re.search(r'check_\w+\s*\([^;]*(?:m_axi_awaddr|awaddr|aw_addr)', _strip_line_comment(raw), re.IGNORECASE) or
        re.search(r'(?:m_axi_awaddr|awaddr|aw_addr)\s*(?:==|===|!=|!==)', _strip_line_comment(raw), re.IGNORECASE) or
        re.search(r'(?:expected_?aw|exp_?aw|awaddr.*expected)', _strip_line_comment(raw), re.IGNORECASE)
        for raw in lines
    )
    if not has_awaddr_check:
        warn('W', 'TB_PRP_AWADDR1', 1,
             "PRP-list multi-page test does not compare AWADDR sequence against expected PRP pages; "
             "wrong PRP entries can still pass on beat count alone.")


def check_c17_arr1(lines):
    """C17_ARR1: detect unpacked reg array declarations that synthesize to distributed RAM."""
    fname = os.path.basename(FILE)
    if fname.lower().startswith('tb_') or fname.lower() == 'tb':
        return

    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]
        m = re.search(r'\b(?:reg|logic)\s+(?:\[[^\]]*\]\s+)*(\w+)\s*\[', code)
        if m:
            warn('W', 'C17_ARR1', i,
                 "unpacked reg array declaration found; "
                 "use BRAM primitive or vendor memory for deep storage. "
                 "If intentional FIFO, add waiver.")


def check_prp_stub1(lines):
    """PRP_STUB1: detect PRP/AR output tied off/stubbed."""
    code_lines = [raw.split('//')[0] for raw in lines]
    code_text = '\n'.join(code_lines)
    fname = os.path.basename(FILE).lower()

    # Scope this protocol-specific error to NVMe/PRP contexts. Generic AXI
    # modules may intentionally expose an unused AR channel and should not be
    # called a PRP-list stub.
    if not (
        re.search(r'\b(prp|nvme)\b|prp_list|list\s+pointer', code_text, re.IGNORECASE)
        or 'prp' in fname
        or 'nvme' in fname
    ):
        return

    # Find arvalid output signal names
    arvalid_names = set()
    for code in code_lines:
        m = re.search(r'\b(\w*arvalid_o)\b', code)
        if not m:
            m = re.search(r'\b(\w+_ar_valid_o)\b', code)
        if m:
            arvalid_names.add(m.group(1))

    if not arvalid_names:
        return

    for name in sorted(arvalid_names):
        assigned_one = False
        assigned_zero = False
        for code in code_lines:
            if re.search(r'\b' + re.escape(name) + r'\s*<=\s*1\'b1\b', code) or \
               re.search(r'\b' + re.escape(name) + r'\s*=\s*1\'b1\b', code):
                assigned_one = True
            if re.search(r'\b' + re.escape(name) + r'\s*<=\s*1\'b0\b', code) or \
               re.search(r'\b' + re.escape(name) + r'\s*=\s*1\'b0\b', code):
                assigned_zero = True

        if assigned_zero and not assigned_one:
            warn('E', 'PRP_STUB1', 1,
                 f"PRP/AR output '{name}' only assigned to 0; "
                 f"PRP list fetch appears stubbed/tied off")


def check_err_stub1(lines):
    """ERR_STUB1: detect error outputs always assigned to 0."""
    code_lines = [raw.split('//')[0] for raw in lines]

    # Find error output signal names: *_err_o, error_o, err_o
    err_names = set()
    for code in code_lines:
        m = re.search(r'\b(\w+_err_o|error_o|err_o)\b', code)
        if m:
            err_names.add(m.group(1))

    if not err_names:
        return

    for name in sorted(err_names):
        assigned_one = False
        assigned_zero = False
        for code in code_lines:
            if re.search(r'\b' + re.escape(name) + r'\s*<=\s*1\'b1\b', code) or \
               re.search(r'\b' + re.escape(name) + r'\s*=\s*1\'b1\b', code):
                assigned_one = True
            if re.search(r'\b' + re.escape(name) + r'\s*<=\s*1\'b0\b', code) or \
               re.search(r'\b' + re.escape(name) + r'\s*=\s*1\'b0\b', code):
                assigned_zero = True

        if assigned_zero and not assigned_one:
            warn('W', 'ERR_STUB1', 1,
                 f"error output '{name}' only assigned to 0; "
                 f"error propagation path may be stubbed")


def check_prp_stub2(lines):
    """PRP_STUB2 (E-level): detect comments in PRP-related RTL files that reveal
    fake/stubbed PRP implementation."""
    fname = os.path.basename(FILE).lower()
    code_text = '\n'.join(raw.split('//')[0] for raw in lines)

    # Skip testbench files (tb_ prefix or tb/ directory)
    if fname.startswith('tb_') or fname.startswith('tb'):
        return
    dirpath = os.path.dirname(FILE)
    if os.path.basename(dirpath).lower() == 'tb':
        return

    # Step 1: only check PRP-related files
    if 'prp' not in fname and not (
        re.search(r'\bprp1\b', code_text, re.IGNORECASE) and
        re.search(r'\bprp2\b', code_text, re.IGNORECASE)
    ):
        return

    # Step 2: scan all lines for comment patterns
    for i, raw in enumerate(lines, 1):
        parts = raw.split('//', 1)
        if len(parts) < 2:
            continue
        comment = parts[1].strip()
        if not comment:
            continue

        # Pattern 1: "Simplified" as exact word (case-insensitive)
        if re.search(r'\bsimplified\b', comment, re.IGNORECASE):
            warn('E', 'PRP_STUB2', i,
                 "PRP/RTL has stubbed/simplified logic comment; the design does not appear to support full PRP traversal. Mark as Blocking Gap (R1) -- cannot claim PASS.")
            return

        # Pattern 2: "Full implementation" followed by "NOT" within 5 words
        fi_match = re.search(r'\bfull\s+implementation\b', comment, re.IGNORECASE)
        if fi_match:
            after_fi = comment[fi_match.end():]
            words = after_fi.split()
            first_five = ' '.join(words[:5])
            if re.search(r'\bNOT\b', first_five, re.IGNORECASE):
                warn('E', 'PRP_STUB2', i,
                     "PRP/RTL has stubbed/simplified logic comment; the design does not appear to support full PRP traversal. Mark as Blocking Gap (R1) -- cannot claim PASS.")
                return

        # Pattern 3: "NOT supported" (case-insensitive)
        if re.search(r'\bnot\s+supported\b', comment, re.IGNORECASE):
            warn('E', 'PRP_STUB2', i,
                 "PRP/RTL has stubbed/simplified logic comment; the design does not appear to support full PRP traversal. Mark as Blocking Gap (R1) -- cannot claim PASS.")
            return

        # Pattern 4: "NOT implemented" (case-insensitive)
        if re.search(r'\bnot\s+implemented\b', comment, re.IGNORECASE):
            warn('E', 'PRP_STUB2', i,
                 "PRP/RTL has stubbed/simplified logic comment; the design does not appear to support full PRP traversal. Mark as Blocking Gap (R1) -- cannot claim PASS.")
            return


def check_width_bound1(lines):
    """WIDTH_BOUND1 (W-level): detect part-selects that may exceed declared width,
    injecting 'bx with Icarus."""
    code_lines = [raw.split('//')[0] for raw in lines]

    # Collect parameter/localparam declarations with numeric values
    params = {}
    for code in code_lines:
        m = re.search(r'\b(?:parameter|localparam)\s+(\w+)\s*=\s*(\d+)', code)
        if m:
            name = m.group(1)
            value = int(m.group(2))
            if name not in params:
                params[name] = value

    # Scan each line for dangerous part-selects
    for i, raw in enumerate(lines, 1):
        code = raw.split('//')[0]
        if not code.strip():
            continue

        # Pattern 0: PAGE_SIZE[WIDE_NAME-1:0] where WIDE_NAME >= 64
        m0 = re.search(r'\bPAGE_SIZE\s*\[\s*(\w+)\s*-\s*1\s*:\s*0\s*\]', code)
        if m0:
            wide_param = m0.group(1)
            if wide_param in params and params[wide_param] >= 64:
                warn('W', 'WIDTH_BOUND1', i,
                     f"parameter 'PAGE_SIZE' is <={32} bits but used in part-select "
                     f"[{wide_param}-1:0] (={params[wide_param]} bits); "
                     "out-of-bound bits replaced with 'bx by Icarus. "
                     "Zero-extend before part-select or cast to wider width first.")
                return

        # Pattern 1: PAGE_SIZE[63:0] always flagged
        if re.search(r'\bPAGE_SIZE\s*\[\s*63\s*:\s*0\s*\]', code):
            warn('W', 'WIDTH_BOUND1', i,
                 "parameter 'PAGE_SIZE' is N bits wide but used in part-select [63:0]; "
                 "out-of-bound bits replaced with 'bx by Icarus. "
                 "Use zero-extend: { {(N){1'b0}}, param} or cast to wider width first.")
            return

        # Pattern 2 & 3: small-value parameters used in [63:0]
        for param_name, value in params.items():
            if value >= 65536:
                continue
            pattern = r'\b' + re.escape(param_name) + r'\s*\[\s*63\s*:\s*0\s*\]'
            if re.search(pattern, code):
                warn('W', 'WIDTH_BOUND1', i,
                     f"parameter '{param_name}' is {value} ({value.bit_length()} bits) but used in part-select [63:0]; "
                     f"out-of-bound bits replaced with 'bx by Icarus. "
                     "Zero-extend before part-select or cast to wider width first.")
                return


def check_datapath_direct_cstate_decode(lines):
    """RTL_STRUCTURAL_PURITY_RSP4 (E-level): detect output/datapath assignments
    that directly decode cstate or S_* instead of using named controls."""
    code_lines = strip_comments(lines)

    # Continuous assigns that reference cstate or S_*
    for i, code in enumerate(code_lines, 1):
        # Skip nstate assignments which legitimately decode state.
        if re.match(r'\s*assign\s+nstate\s*=', code):
            continue

        m = re.match(r'\s*assign\s+(\w+)\s*=\s*(.+)', code)
        if m:
            rhs = m.group(2)
            if re.search(r'\bcstate\b', rhs) or re.search(r'\bS_\w+\b', rhs):
                lhs = m.group(1)
                warn('E', 'RTL_STRUCTURAL_PURITY_RSP4', i,
                     f"output/datapath '{lhs}' directly decodes cstate/S_*; "
                     "use a named control signal from the FSM combinational decode instead.")

    # Procedural assignments inside combinational always blocks
    for start_line, block in _collect_always_blocks(lines, r'always\s*@\s*\(\s*\*\s*\)'):
        text = _block_code(block)
        if not re.search(r'\bcstate\b|\bS_\w+\b', text):
            continue

        for line_no, raw in block:
            code = _strip_line_comment(raw)

            # Skip nstate assignments
            if re.match(r'\s*nstate\s*=', code):
                continue

            # Detect procedural assignment that references cstate/S_* in RHS
            m = re.match(r'\s*(\w+)\s*=\s*[^=].*', code)
            if m:
                lhs = m.group(1)
                rhs = code[code.index('=') + 1:] if '=' in code else ''
                if re.search(r'\bcstate\b', rhs) or re.search(r'\bS_\w+\b', rhs):
                    warn('E', 'RTL_STRUCTURAL_PURITY_RSP4', line_no,
                         f"output/datapath '{lhs}' directly decodes cstate/S_*; "
                         "use a named control signal from the FSM combinational decode instead.")


def check_prp_list_fake1(lines):
    """PRP_LIST_FAKE1 (E-level): detect fake PRP list traversal in NVMe/PRP context."""
    fname = os.path.basename(FILE).lower()
    code_text = '\n'.join(strip_comments(lines))

    # Skip testbench files (tb_ prefix or tb/ directory)
    if fname.startswith('tb_') or fname.startswith('tb'):
        return
    dirpath = os.path.dirname(FILE)
    if os.path.basename(dirpath).lower() == 'tb':
        return

    # Only check PRP-related files
    if 'prp' not in fname and not (
        re.search(r'\bprp1\b', code_text, re.IGNORECASE) and
        re.search(r'\bprp2\b', code_text, re.IGNORECASE)
    ):
        return

    for i, raw in enumerate(lines, 1):
        parts = raw.split('//', 1)
        if len(parts) < 2:
            continue
        comment = parts[1].strip()
        if not comment:
            continue

        # Pattern 1: "Simplified" comment on a line with advance/PAGE_SIZE/host_addr
        if re.search(r'\bsimplified\b', comment, re.IGNORECASE):
            full_line = parts[0] + ' ' + comment
            if re.search(r'\b(advance|PAGE_SIZE|host_addr)\b', full_line, re.IGNORECASE):
                keyword = re.search(r'\b(advance|PAGE_SIZE|host_addr)\b', full_line, re.IGNORECASE).group()
                warn('E', 'PRP_LIST_FAKE1', i,
                     f"false PRP list traversal: simplified with {keyword}. "
                     "PRP2 list data entries are not fetched; "
                     "host addresses are faked with PAGE_SIZE arithmetic. "
                     "Blocking Gap (R1).")
                continue

        # Pattern 2: "would fetch from PRP2 list" in comment
        if re.search(r'would\s+fetch\s+from\s+PRP2\s+list', comment, re.IGNORECASE):
            warn('E', 'PRP_LIST_FAKE1', i,
                 "false PRP list traversal: would fetch from PRP2 list. "
                 "PRP2 list data entries are not fetched; "
                 "host addresses are faked with PAGE_SIZE arithmetic. "
                 "Blocking Gap (R1).")
            continue

        # Pattern 3: "Full PRP list traversal would fetch" in comment
        if re.search(r'Full\s+PRP\s+list\s+traversal\s+would\s+fetch', comment, re.IGNORECASE):
            warn('E', 'PRP_LIST_FAKE1', i,
                 "false PRP list traversal: Full PRP list traversal would fetch. "
                 "PRP2 list data entries are not fetched; "
                 "host addresses are faked with PAGE_SIZE arithmetic. "
                 "Blocking Gap (R1).")
            continue

        # Pattern 4: "advance by PAGE_SIZE" in comment
        if re.search(r'advance\s+by\s+PAGE_SIZE', comment, re.IGNORECASE):
            warn('E', 'PRP_LIST_FAKE1', i,
                 "false PRP list traversal: advance by PAGE_SIZE. "
                 "PRP2 list data entries are not fetched; "
                 "host addresses are faked with PAGE_SIZE arithmetic. "
                 "Blocking Gap (R1).")
            continue

        # Pattern 5: "Simplified" near "PRP" (within 5 words in the comment)
        if re.search(r'\bsimplified\b', comment, re.IGNORECASE):
            words = re.findall(r'\b\w+\b', comment)
            for j, w in enumerate(words):
                if re.search(r'\bsimplified\b', w, re.IGNORECASE):
                    window = ' '.join(words[max(0, j - 5):j + 6])
                    if re.search(r'\bPRP\b', window, re.IGNORECASE):
                        warn('E', 'PRP_LIST_FAKE1', i,
                             "false PRP list traversal: simplified PRP. "
                             "PRP2 list data entries are not fetched; "
                             "host addresses are faked with PAGE_SIZE arithmetic. "
                             "Blocking Gap (R1).")
                        break


def check_axi_wdata_source1(lines):
    """AXI_WDATA_SOURCE1 (E-level): detect AXI write modules where WVALID
    asserts without checking data FIFO availability."""
    code_lines = strip_comments(lines)
    code_text = '\n'.join(code_lines)

    # Only check AXI write-related files
    w_channel_valid_re = (
        r'\b((?:m_axi_|s_axi_)?wvalid\w*|'
        r'(?:m_axi_|s_axi_)?w_valid\w*|'
        r'w_active\w*)\b'
    )
    has_wvalid = bool(re.search(w_channel_valid_re, code_text))
    has_wdata = bool(re.search(r'\b(m_axi_wdata_o|w_data)\b', code_text))
    if not (has_wvalid and has_wdata):
        return

    for start_line, block in _collect_always_blocks(lines, r'\balways\b'):
        text = _block_code(block)

        # Check if WVALID/w_active is set to 1 in this block
        wvalid_assigns = []
        for line_no, raw in block:
            code = _strip_line_comment(raw)
            m = re.search(
                w_channel_valid_re + r'\s*(?:<=|=)\s*1\'b1',
                code)
            if m:
                wvalid_assigns.append((line_no, m.group(1)))
        if not wvalid_assigns:
            continue

        # Check if this block handles page_accept/start/aw_handshake context.
        # Leading \b avoids mid-identifier false matches; no trailing \b because
        # identifiers like aw_ready_i and aw_active_q have _ which is a \w char.
        has_aw_context = bool(re.search(
            r'\b(page_accept|page_valid|start|aw_active|aw_handshake|aw_ready|awvalid)',
            text))
        if not has_aw_context:
            continue

        # Check for data availability check
        has_data_check = bool(re.search(
            r'(!?\s*fifo_empty\b|fifo_count\s*[>!]\s*0|'
            r'\bhave_data\b|\bhave_next\b|\bhave_next_wbeat\b|'
            r'\bfull_burst\b|\bburst_buffer\b|'
            r'\bwdata_valid\b|\bdata_valid\b|\bdata_available\b)',
            text))

        if not has_data_check:
            for line_no, signal in wvalid_assigns:
                warn('E', 'AXI_WDATA_SOURCE1', line_no,
                     f"AXI W data source: '{signal}' asserted on page/start/aw "
                     "without FIFO data availability check "
                     "(no !fifo_empty/count>0/have_data/burst_buffer). "
                     "May drive stale/X data onto W channel.")


def check_nvm_stray_data1(lines):
    """NVM_STRAY_DATA1 (W-level): detect NVM read master modules where data is
    accepted into FIFO without collect/active gating."""
    fname = os.path.basename(FILE).lower()
    code_text = '\n'.join(strip_comments(lines))

    # Only check NVM-related files (substring match because nvm in test_nvm_stray
    # is adjacent to _ which is a \w char, so \b boundaries would not match).
    if 'nvm' not in fname and 'nvm' not in code_text.lower():
        return

    # Find lines matching ready=!full and wr_en=data_valid patterns
    ready_lines = []

    for i, raw in enumerate(lines, 1):
        code = _strip_line_comment(raw)
        if re.search(r'\b\w*(?:ready|rd_data_ready)\w*\s*=\s*(!|~)\s*\w*(?:fifo_full|dfifo_full)\w*', code):
            ready_lines.append(i)

    if not ready_lines:
        return

    # Check each ready line's 10-line context for wr_en pattern and gating signal
    for rl in ready_lines:
        ctx_start = max(0, rl - 6)
        ctx_end = min(len(lines), rl + 5)
        context = '\n'.join(strip_comments(lines)[ctx_start:ctx_end])

        # Check if wr_en pattern is in the context
        has_wr_en = bool(re.search(
            r'\b\w*(?:wr_en|dfifo_wr_en)\w*\s*=\s*\w*(?:data_valid|nvm_data_fire)\w*',
            context))
        if not has_wr_en:
            continue

        # Check for absence of gating signals in context
        has_gating = bool(re.search(
            r'\b(collect|active|trans_active|page_active)\b',
            context, re.IGNORECASE))
        if not has_gating:
            warn('W', 'NVM_STRAY_DATA1', rl,
                 "NVM read data accepted into FIFO without collect/active gating; "
                 "data may flow when no transaction is active. "
                 "Add page_active/collect_en gating to dfifo_wr_en_o.")
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

    code_text = ''.join(lines)
    norm_path = filepath.replace('\\', '/').lower()
    is_tb = (
        _looks_like_testbench(code_text) or
        os.path.basename(norm_path).startswith('tb_') or
        '/tb/' in norm_path
    )

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
    check_multi_driver(lines)
    check_tb_fake_false_pass_audit(lines)
    check_tb_empty_if_comparisons(lines)
    check_tb_wlast_boolean_only(lines)
    check_tb_completion_count_exact(lines)
    check_tb_xz_coverage(lines)
    check_tb_sideband_trace(lines)
    check_parameter_hardcode(lines)
    check_nvme_prp_list_tb_coverage(lines)
    check_tb_false_pass_patterns(lines)
    check_nvm_offset_page_reset(lines)
    check_prp_list_buffer_mismatch(lines)
    check_w_active_no_data_gating(lines)
    if not is_tb:
        check_fsm_comb_multi_bit(lines)
        check_datapath_has_cstate(lines)
        check_fsm_seq_has_datapath(lines)
    check_tb_unbounded_wait(lines)
    check_tb_timeout_finish_only(lines)
    check_tb_completion_only(lines)
    check_tb_capture_without_expected(lines)
    check_tb_status_unchecked(lines)
    check_c17_arr1(lines)
    check_prp_stub1(lines)
    check_prp_stub2(lines)
    check_width_bound1(lines)
    check_err_stub1(lines)
    if not is_tb:
        check_datapath_direct_cstate_decode(lines)
    check_prp_list_fake1(lines)
    check_axi_wdata_source1(lines)
    check_nvm_stray_data1(lines)



def main():
    global OUT, LEVEL
    parser = argparse.ArgumentParser(
        description=(
            "Run RTL style, false-pass, protocol-trap, and structural-purity checks. "
            "Any finding causes a nonzero exit so the script can be used as a gate."
        )
    )
    parser.add_argument('--level', choices=['L0', 'L1', 'L2'], default='L1',
                        help='Project complexity level (default: L1). '
                             'L2 escalates RSP2 to E-level.')
    parser.add_argument('files', nargs='*', help='Verilog/SystemVerilog files to check')
    args = parser.parse_args()

    LEVEL = args.level

    if not args.files:
        parser.print_help()
        sys.exit(2)

    for path in args.files:
        check_file(path)

    if OUT:
        for line in OUT:
            print(line)
        errors = sum(1 for o in OUT if o.startswith('[E]'))
        warns = sum(1 for o in OUT if o.startswith('[W]'))
        print(f"\n{len(OUT)} finding(s): {errors} error(s), {warns} warning(s)")
        sys.exit(1)

    print("All checks PASS")


if __name__ == '__main__':
    main()
