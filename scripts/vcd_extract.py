#!/usr/bin/env python3
"""VCD waveform extraction and analysis tool for RTL debug.

Usage:
    python vcd_extract.py <vcd_file> --signals <name1>,<name2> [--range <start>:<end>]
    python vcd_extract.py <vcd_file> --transitions <signal_name>
    python vcd_extract.py <vcd_file> --protocol axi-write
    python vcd_extract.py <vcd_file> --find-violation valid-drop --signals valid,ready
"""

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path


def parse_vcd_header(lines):
    """Parse VCD header to extract signal definitions and timescale."""
    signals = {}  # id -> {name, width, scope}
    timescale = "1s"
    scope_stack = []
    current_scope = ""

    for line in lines:
        line = line.strip()
        if line.startswith("$timescale"):
            # $timescale 1s $end
            parts = line.split()
            if len(parts) >= 2:
                timescale = parts[1]
        elif line.startswith("$scope"):
            # $scope module tb $end
            parts = line.split()
            if len(parts) >= 3:
                scope_stack.append(parts[2])
                current_scope = ".".join(scope_stack)
        elif line.startswith("$upscope"):
            if scope_stack:
                scope_stack.pop()
                current_scope = ".".join(scope_stack)
        elif line.startswith("$var"):
            # $var wire 1 ! signal_name $end
            # $var wire 32 4 signal_name [31:0] $end
            parts = line.split(None, 4)
            if len(parts) >= 5:
                var_type = parts[1]
                width = int(parts[2])
                var_id = parts[3]
                # Signal name may contain spaces (e.g., "signal_name [31:0]")
                rest = parts[4]
                if rest.endswith(" $end"):
                    rest = rest[:-5]
                elif rest.endswith("$end"):
                    rest = rest[:-4]
                name = rest.strip()
                signals[var_id] = {
                    "name": name,
                    "width": width,
                    "scope": current_scope,
                    "fullname": f"{current_scope}.{name}" if current_scope else name,
                }
        elif line.startswith("$enddefinitions"):
            break

    return signals, timescale


def parse_vcd_values(lines, signal_ids=None):
    """Parse VCD value changes. Returns list of (timestamp, id, value)."""
    changes = []
    current_time = 0

    for line in lines:
        line = line.strip()
        if not line:
            continue
        if line.startswith("#"):
            try:
                current_time = int(line[1:])
            except ValueError:
                pass
        elif line.startswith("b"):
            # Multi-bit: b<value> <id>
            parts = line.split()
            if len(parts) == 2:
                val, var_id = parts[0][1:], parts[1]
                if signal_ids is None or var_id in signal_ids:
                    changes.append((current_time, var_id, val))
        elif len(line) >= 2 and line[0] in "01xzXZ":
            # Scalar: <value><id>
            val, var_id = line[0], line[1:]
            if signal_ids is None or var_id in signal_ids:
                changes.append((current_time, var_id, val))

    return changes


def find_signal_ids(signals, names):
    """Find signal IDs matching given names (partial match supported)."""
    result = {}
    for var_id, info in signals.items():
        sig_name = info["name"]
        # Remove array index for matching: "signal_name [31:0]" -> "signal_name"
        base_name = re.sub(r"\s*\[.*\]$", "", sig_name)
        for target in names:
            if target == base_name or target == sig_name or target in sig_name:
                result[var_id] = info
    return result


def extract_signal_timeline(changes, signal_ids):
    """Extract timeline for specific signals as list of (time, signal_name, value)."""
    timeline = []
    for time, var_id, value in changes:
        if var_id in signal_ids:
            name = signal_ids[var_id]["name"]
            timeline.append((time, name, value))
    return timeline


def find_transitions(changes, signal_id, signals):
    """Find all transitions (value changes) for a signal."""
    transitions = []
    last_val = None
    for time, var_id, value in changes:
        if var_id == signal_id:
            if last_val is not None and value != last_val:
                transitions.append((time, last_val, value))
            last_val = value
    return transitions


def format_value(val_str, width):
    """Format a binary value string for display."""
    if val_str in ("x", "z", "X", "Z"):
        return val_str
    try:
        if val_str.startswith("b"):
            val_str = val_str[1:]
        if len(val_str) <= 32:
            return f"0x{int(val_str, 2):0{(width + 3) // 4}X}"
        else:
            return f"0x{int(val_str, 2):X}" if val_str.isdigit() else val_str
    except (ValueError, IndexError):
        return val_str


def reconstruct_axi_write(changes, signals):
    """Reconstruct AXI write channel sequence from VCD changes."""
    # Find signal IDs for AXI write signals
    axi_names = ["awvalid", "awready", "wvalid", "wready", "wlast",
                  "bvalid", "bready", "awaddr", "wdata"]
    sig_map = {}
    for var_id, info in signals.items():
        name_lower = info["name"].lower().replace("_", "").replace(" ", "")
        for target in axi_names:
            target_clean = target.replace("_", "")
            if target_clean in name_lower:
                if target not in sig_map:
                    sig_map[target] = {"id": var_id, "info": info}

    if not sig_map:
        return "No AXI write signals found in VCD."

    # Build signal timelines
    timelines = defaultdict(dict)  # signal_name -> {time: value}
    for time, var_id, value in changes:
        for name, sinfo in sig_map.items():
            if var_id == sinfo["id"]:
                timelines[name][time] = value

    # Find clock period (approximate from awvalid transitions)
    if "awvalid" in timelines:
        times = sorted(timelines["awvalid"].keys())
        if len(times) >= 2:
            clock_period = times[1] - times[0]
        else:
            clock_period = 1
    else:
        clock_period = 1

    # Reconstruct events
    all_times = set()
    for tl in timelines.values():
        all_times.update(tl.keys())
    all_times = sorted(all_times)

    events = []
    aw_handshake = None
    w_beats = 0
    w_started = False
    b_response = None

    for t in all_times:
        awv = timelines.get("awvalid", {}).get(t, "0")
        awr = timelines.get("awready", {}).get(t, "0")
        wv = timelines.get("wvalid", {}).get(t, "0")
        wr = timelines.get("wready", {}).get(t, "0")
        wl = timelines.get("wlast", {}).get(t, "0")
        bv = timelines.get("bvalid", {}).get(t, "0")
        br = timelines.get("bready", {}).get(t, "0")

        if awv == "1" and awr == "1" and aw_handshake is None:
            aw_handshake = t
            events.append(f"  t={t}: AW handshake (address accepted)")

        if wv == "1" and wr == "1":
            if not w_started:
                w_started = True
            w_beats += 1
            if wl == "1":
                events.append(f"  t={t}: WLAST (beat {w_beats}, burst complete)")
                w_started = False
                w_beats = 0

        if bv == "1" and br == "1" and b_response is None:
            b_response = t
            events.append(f"  t={t}: B response (write complete)")

    if not events:
        return "No AXI write transactions found."

    result = ["AXI Write Channel Reconstruction:"]
    result.extend(events)

    # Check for violations
    if aw_handshake and w_started and not b_response:
        result.append("  WARNING: W burst started but B response not seen")
    if aw_handshake is None and w_started:
        result.append("  WARNING: W beats without AW handshake")

    return "\n".join(result)


def find_stall_data_change(changes, signals, valid_name="valid", ready_name="ready", data_name="data"):
    """Find cycles where data changes while valid=1 and ready=0 (H1 violation)."""
    valid_ids = find_signal_ids(signals, [valid_name])
    ready_ids = find_signal_ids(signals, [ready_name])
    data_ids = find_signal_ids(signals, [data_name])

    if not valid_ids or not ready_ids or not data_ids:
        return f"Could not find signals '{valid_name}', '{ready_name}', and/or '{data_name}'"

    valid_id = list(valid_ids.keys())[0]
    ready_id = list(ready_ids.keys())[0]
    data_id = list(data_ids.keys())[0]

    # Build timelines
    valid_tl = {}
    ready_tl = {}
    data_tl = {}
    for time, var_id, value in changes:
        if var_id == valid_id:
            valid_tl[time] = value
        elif var_id == ready_id:
            ready_tl[time] = value
        elif var_id == data_id:
            data_tl[time] = value

    # Find all timestamps
    all_times = sorted(set(valid_tl.keys()) | set(ready_tl.keys()) | set(data_tl.keys()))

    last_valid = "0"
    last_ready = "0"
    last_data = None
    violations = []

    for t in all_times:
        v = valid_tl.get(t, last_valid)
        r = ready_tl.get(t, last_ready)
        d = data_tl.get(t, last_data)

        # Check: valid was 1, ready was 0, data changed
        if last_valid == "1" and last_ready == "0" and d != last_data and last_data is not None:
            violations.append(f"  t={t}: DATA changed during stall (valid=1, ready=0): {last_data} -> {d}")

        last_valid = v
        last_ready = r
        last_data = d

    if not violations:
        return f"No stall-data-change violations found."

    result = [f"Found {len(violations)} stall-data-change violation(s) (H1):"]
    result.extend(violations)
    return "\n".join(result)


def find_valid_drop_violation(changes, signals, valid_name="valid", ready_name="ready"):
    """Find cycles where valid drops while ready is low (protocol violation)."""
    valid_ids = find_signal_ids(signals, [valid_name])
    ready_ids = find_signal_ids(signals, [ready_name])

    if not valid_ids or not ready_ids:
        return f"Could not find signals '{valid_name}' and/or '{ready_name}'"

    valid_id = list(valid_ids.keys())[0]
    ready_id = list(ready_ids.keys())[0]

    # Build timelines
    valid_tl = {}
    ready_tl = {}
    for time, var_id, value in changes:
        if var_id == valid_id:
            valid_tl[time] = value
        elif var_id == ready_id:
            ready_tl[time] = value

    # Find all timestamps
    all_times = sorted(set(valid_tl.keys()) | set(ready_tl.keys()))

    last_valid = "0"
    last_ready = "0"
    violations = []

    for t in all_times:
        v = valid_tl.get(t, last_valid)
        r = ready_tl.get(t, last_ready)

        # Check: valid was 1, ready was 0, valid drops to 0
        if last_valid == "1" and last_ready == "0" and v == "0":
            violations.append(f"  t={t}: VALID dropped while READY=0 (protocol violation)")

        last_valid = v
        last_ready = r

    if not violations:
        return f"No '{valid_name} drop' violations found."

    result = [f"Found {len(violations)} valid-drop violation(s):"]
    result.extend(violations)
    return "\n".join(result)


def main():
    parser = argparse.ArgumentParser(description="VCD waveform extraction and analysis")
    parser.add_argument("vcd_file", help="Path to VCD file")
    parser.add_argument("--signals", help="Comma-separated signal names to extract")
    parser.add_argument("--range", help="Time range start:end")
    parser.add_argument("--transitions", help="Find all transitions of this signal")
    parser.add_argument("--protocol", choices=["axi-write", "axi-read", "apb"],
                        help="Reconstruct protocol sequence")
    parser.add_argument("--find-violation", choices=["valid-drop", "stall-data-change"],
                        help="Find protocol violations")
    parser.add_argument("--list-signals", action="store_true",
                        help="List all signals in the VCD")
    parser.add_argument("--head", type=int, default=50,
                        help="Max output lines (default 50)")

    args = parser.parse_args()

    vcd_path = Path(args.vcd_file)
    if not vcd_path.exists():
        print(f"Error: file not found: {vcd_path}", file=sys.stderr)
        sys.exit(1)

    # Read VCD file
    with open(vcd_path, "r", errors="replace") as f:
        lines = f.readlines()

    # Find header end
    header_end = 0
    for i, line in enumerate(lines):
        if line.strip().startswith("$enddefinitions"):
            header_end = i + 1
            break

    header_lines = lines[:header_end]
    data_lines = lines[header_end:]

    # Parse header
    signals, timescale = parse_vcd_header(header_lines)

    if args.list_signals:
        print(f"Timescale: {timescale}")
        print(f"Total signals: {len(signals)}")
        print()
        for var_id, info in sorted(signals.items(), key=lambda x: x[1]["name"]):
            print(f"  [{var_id}] {info['name']} ({info['width']}bit) @ {info['scope']}")
        return

    # Determine which signals to extract
    if args.signals:
        target_names = [s.strip() for s in args.signals.split(",")]
        target_ids = find_signal_ids(signals, target_names)
        if not target_ids:
            print(f"Error: no signals matching {target_names}", file=sys.stderr)
            print("Available signals:", file=sys.stderr)
            for var_id, info in list(signals.items())[:20]:
                print(f"  {info['name']}", file=sys.stderr)
            sys.exit(1)
        signal_ids = set(target_ids.keys())
    else:
        target_ids = signals
        signal_ids = None  # parse all

    # Parse value changes
    changes = parse_vcd_values(data_lines, signal_ids)

    # Apply time range filter
    if args.range:
        parts = args.range.split(":")
        t_start = int(parts[0]) if parts[0] else 0
        t_end = int(parts[1]) if len(parts) > 1 and parts[1] else float("inf")
        changes = [(t, v, val) for t, v, val in changes if t_start <= t <= t_end]

    # Dispatch to operation
    if args.transitions:
        target = args.transitions
        ids = find_signal_ids(signals, [target])
        if not ids:
            print(f"Signal '{target}' not found")
            sys.exit(1)
        var_id = list(ids.keys())[0]
        trans = find_transitions(changes, var_id, signals)
        print(f"Transitions of '{signals[var_id]['name']}':")
        for t, old, new in trans[:args.head]:
            print(f"  t={t}: {old} -> {new}")
        if len(trans) > args.head:
            print(f"  ... ({len(trans)} total, showing first {args.head})")

    elif args.protocol == "axi-write":
        print(reconstruct_axi_write(changes, signals))

    elif args.find_violation == "valid-drop":
        parts = args.signals.split(",") if args.signals else ["valid", "ready"]
        valid_name = parts[0].strip()
        ready_name = parts[1].strip() if len(parts) > 1 else "ready"
        print(find_valid_drop_violation(changes, signals, valid_name, ready_name))

    elif args.find_violation == "stall-data-change":
        parts = args.signals.split(",") if args.signals else ["valid", "ready", "data"]
        valid_name = parts[0].strip()
        ready_name = parts[1].strip() if len(parts) > 1 else "ready"
        data_name = parts[2].strip() if len(parts) > 2 else "data"
        print(find_stall_data_change(changes, signals, valid_name, ready_name, data_name))

    else:
        # Default: extract signal timeline
        timeline = extract_signal_timeline(changes, target_ids)
        print(f"Signal timeline ({len(timeline)} changes):")
        for t, name, val in timeline[:args.head]:
            info = target_ids.get(None) or {"width": 1}
            # Find width for this signal
            for vid, inf in target_ids.items():
                if inf["name"] == name:
                    info = inf
                    break
            display_val = format_value(val, info["width"])
            print(f"  t={t:>12}  {name:30s} = {display_val}")
        if len(timeline) > args.head:
            print(f"  ... ({len(timeline)} total, showing first {args.head})")


if __name__ == "__main__":
    main()
