"""Guarded simulation wrapper: runs vvp with timeout and artifact size limits.

Replaces bare vvp invocation with a guarded run that captures output, enforces
a timeout, and checks for oversized VCD/FST/log artifacts.
The wrapper does not synthesize simulation PASS markers; `ALL_TESTS_PASS` and
`SIMULATION_DONE` must come from the testbench output captured in the log.

Usage:
    python scripts/run_sim_guarded.py [--timeout-sec SEC] [--max-vcd-mb MB]
        [--max-log-mb MB] [--log LOGFILE] [--cwd DIR] -- <vvp> [vvp_args ...]

Defaults: timeout-sec=30, max-vcd-mb=50, max-log-mb=20.

Exit codes:
    0  simulation completed within timeout, command exit=0, artifact sizes OK
    1  timeout expired
    2  command failed (non-zero exit)
    3  VCD/log size limit exceeded
"""
import argparse
import io
import os
import subprocess
import sys
import time


try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except (AttributeError, io.UnsupportedOperation):
    try:
        sys.stdout = io.TextIOWrapper(
            sys.stdout.buffer, encoding='utf-8', errors='replace')
        sys.stderr = io.TextIOWrapper(
            sys.stderr.buffer, encoding='utf-8', errors='replace')
    except AttributeError:
        pass


def _format_size_mb(num_bytes: int) -> str:
    """Return a human-readable string like '1.50 MB'."""
    return f"{num_bytes / (1024 * 1024):.2f} MB"


def _find_wave_files(directory: str) -> list[tuple[str, int]]:
    """Return [(filename, size_bytes)] for .vcd/.fst files under *directory*."""
    results: list[tuple[str, int]] = []
    try:
        for fname in os.listdir(directory):
            if fname.endswith(('.vcd', '.fst')):
                fpath = os.path.join(directory, fname)
                try:
                    results.append((fname, os.path.getsize(fpath)))
                except OSError:
                    pass
    except FileNotFoundError:
        pass
    return results


def _safe_cmd_display(cmd_args: list[str]) -> str:
    """Return a command summary that cannot inject PASS/FAIL log markers."""
    if not cmd_args:
        return "<empty>"
    exe = os.path.basename(cmd_args[0])
    return f"{exe} <{max(0, len(cmd_args) - 1)} arg(s)>"


def _append_log(log_path: str, line: str) -> None:
    """Append one UTF-8 line to the simulation log if possible."""
    try:
        with open(log_path, 'a', encoding='utf-8', errors='replace') as f:
            f.write(line)
            if not line.endswith('\n'):
                f.write('\n')
    except OSError as e:
        print(f"RUN_SIM_GUARDED: WARNING - cannot append log: {e}",
              file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Guarded simulation wrapper with timeout and artifact limits.")
    parser.add_argument('--timeout-sec', type=int, default=30,
                        help='Simulation timeout in seconds (default: 30)')
    parser.add_argument('--max-vcd-mb', type=int, default=50,
                        help='Maximum VCD/FST file size in MB (default: 50)')
    parser.add_argument('--max-log-mb', type=int, default=20,
                        help='Maximum log file size in MB (default: 20)')
    parser.add_argument('--log', type=str, default=None,
                        help='Log file path (default: sim/sim_output.log under cwd)')
    parser.add_argument('--cwd', type=str, default=None,
                        help='Working directory (default: current directory)')
    args, remaining = parser.parse_known_args()

    # Locate the -- separator; everything after it is the sub-command.
    cmd_args = remaining
    if '--' in remaining:
        idx = remaining.index('--')
        cmd_args = remaining[idx + 1:]

    if not cmd_args:
        parser.error("Missing vvp command.  Use: ... -- <vvp> [vvp_args ...]")

    # On Windows, .vvp files cannot be executed directly -- prepend 'vvp'
    # so the command becomes vvp <file>.vvp [args...].
    # On Linux, .vvp is typically invoked as ./file.vvp or vvp file.vvp;
    # preserve existing behavior for non-Windows.
    if sys.platform == 'win32' and cmd_args[0].endswith('.vvp'):
        cmd_args = ['vvp'] + cmd_args

    # Resolve working directory.
    work_dir = os.path.abspath(args.cwd) if args.cwd else os.getcwd()

    # Resolve log file path.
    if args.log:
        log_path = args.log
    else:
        log_path = os.path.join(work_dir, 'sim', 'sim_output.log')

    log_dir = os.path.dirname(log_path)
    if log_dir:
        os.makedirs(log_dir, exist_ok=True)

    max_vcd_bytes = args.max_vcd_mb * 1024 * 1024
    max_log_bytes = args.max_log_mb * 1024 * 1024

    cmd_display = _safe_cmd_display(cmd_args)
    print(f"RUN_SIM_GUARDED: command={cmd_display} "
          f"timeout={args.timeout_sec}s cwd={work_dir}")

    # ------------------------------------------------------------------ #
    # Run the vvp command with a timeout.
    # ------------------------------------------------------------------ #
    start_time = time.time()
    output_text = ""
    exit_code = 0
    timed_out = False

    try:
        result = subprocess.run(
            cmd_args,
            cwd=work_dir,
            capture_output=True,
            text=False,  # work with raw bytes, decode manually
            timeout=args.timeout_sec,
        )
        exit_code = result.returncode
        out_bytes = result.stdout
        if result.stderr:
            out_bytes += result.stderr
        output_text = out_bytes.decode('utf-8', errors='replace')
    except subprocess.TimeoutExpired as e:
        timed_out = True
        out_bytes = e.stdout or b''
        if e.stderr:
            out_bytes += e.stderr
        output_text = out_bytes.decode('utf-8', errors='replace')
        output_text += (
            f"\n[TIMEOUT] Process killed after "
            f"{time.time() - start_time:.1f}s "
            f"(limit {args.timeout_sec}s)\n")

    elapsed = time.time() - start_time

    wrapper_summary: list[str] = []
    wrapper_summary.append(
        f"RUN_SIM_GUARDED: command={cmd_display} "
        f"timeout={args.timeout_sec}s cwd={work_dir}")
    if timed_out:
        wrapper_summary.append(
            f"RUN_SIM_GUARDED: TIMEOUT elapsed={elapsed:.1f}s")
    elif exit_code != 0:
        wrapper_summary.append(
            f"RUN_SIM_GUARDED: FAIL command_exit={exit_code} elapsed={elapsed:.1f}s")
    else:
        wrapper_summary.append(
            f"RUN_SIM_GUARDED: command_exit=0 elapsed={elapsed:.1f}s")

    # Write the captured output plus wrapper summary to the log file.
    try:
        with open(log_path, 'w', encoding='utf-8', errors='replace') as f:
            f.write(output_text)
            if output_text and not output_text.endswith('\n'):
                f.write('\n')
            f.write('\n'.join(wrapper_summary))
            f.write('\n')
    except OSError as e:
        print(f"RUN_SIM_GUARDED: WARNING - cannot write log: {e}",
              file=sys.stderr)

    # ------------------------------------------------------------------ #
    # Check artifact sizes.
    # ------------------------------------------------------------------ #
    size_exceeded = False

    # Log file size.
    log_size = 0
    try:
        log_size = os.path.getsize(log_path)
        if log_size > max_log_bytes:
            print(f"RUN_SIM_GUARDED: FAIL - log size "
                  f"{_format_size_mb(log_size)} exceeds limit "
                  f"{_format_size_mb(max_log_bytes)}")
            size_exceeded = True
    except OSError:
        pass

    # Wave files -- check cwd first, then sim/ subdirectory.
    wave_files: list[tuple[str, int]] = []
    for d in (work_dir, os.path.join(work_dir, 'sim')):
        wave_files.extend(_find_wave_files(d))

    for wf_name, wf_size in wave_files:
        if wf_size > max_vcd_bytes:
            print(f"RUN_SIM_GUARDED: FAIL - {wf_name} size "
                  f"{_format_size_mb(wf_size)} exceeds limit "
                  f"{_format_size_mb(max_vcd_bytes)}")
            size_exceeded = True

    # ------------------------------------------------------------------ #
    # Summary.
    # ------------------------------------------------------------------ #
    vcd_sizes = ', '.join(
        f"{name}={_format_size_mb(sz)}" for name, sz in wave_files)
    log_str = _format_size_mb(log_size) if log_size > 0 else "N/A"

    if timed_out:
        print(f"RUN_SIM_GUARDED: TIMEOUT elapsed={elapsed:.1f}s "
              f"vcd=[{vcd_sizes}] log={log_str}")
        print("TIMEOUT")
        sys.exit(1)

    if exit_code != 0:
        print(f"RUN_SIM_GUARDED: FAIL vvp_exit={exit_code} "
              f"vcd=[{vcd_sizes}] log={log_str}")
        sys.exit(2)

    if size_exceeded:
        _append_log(log_path, "RUN_SIM_GUARDED_FAIL: SIZE_LIMIT_EXCEEDED")
        print(f"RUN_SIM_GUARDED: FAIL vvp_exit={exit_code} "
              f"vcd=[{vcd_sizes}] log={log_str} "
              f"(size limit exceeded)")
        sys.exit(3)

    print(f"RUN_SIM_GUARDED: PASS vvp_exit={exit_code} "
          f"vcd=[{vcd_sizes}] log={log_str}")
    sys.exit(0)


if __name__ == '__main__':
    main()
