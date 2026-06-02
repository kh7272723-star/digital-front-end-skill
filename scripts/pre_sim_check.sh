#!/bin/bash
# pre_sim_check.sh — unified pre-simulation gate
# Runs: yosys synthesis → rtl_style_check → per-module standalone compile
# Exit code 0 = all checks pass. Exit code 1 = violations found.

set -e

YOSYS=${YOSYS:-yosys}
IVERILOG=${IVERILOG:-iverilog}
STYLE_CHECK="python $(dirname $0)/rtl_style_check.py"

TOTAL_FAILS=0

usage() {
    echo "Usage: $0 --top <top_module> [--yosys] [--style] [--compile] <file1.v> [file2.v ...]"
    echo "       $0 --all --top <top_module> <files...>"
    exit 2
}

RUN_YOSYS=0
RUN_STYLE=0
RUN_COMPILE=0
TOP_MODULE=""
FILES=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)   RUN_YOSYS=1; RUN_STYLE=1; RUN_COMPILE=1; shift ;;
        --yosys) RUN_YOSYS=1; shift ;;
        --style) RUN_STYLE=1; shift ;;
        --compile) RUN_COMPILE=1; shift ;;
        --top)    TOP_MODULE="$2"; shift 2 ;;
        *.v)      FILES+=("$1"); shift ;;
        *)        shift ;;
    esac
done

if [[ ${#FILES[@]} -eq 0 ]]; then
    usage
fi

echo "=== pre_sim_check ==="
echo "Files: ${FILES[@]}"
echo ""

# ── yosys synthesis ──────────────────────────────────
if [[ $RUN_YOSYS -eq 1 ]]; then
    if [[ -z "$TOP_MODULE" ]]; then
        echo "[SKIP] yosys: no --top specified"
    else
        echo "── yosys synthesis (top=$TOP_MODULE) ──"
        YOSYS_OUT=$(mktemp)
        if $YOSYS -p "read_verilog ${FILES[@]}; synth -top $TOP_MODULE; check -assert; stat" 2>&1 | tee "$YOSYS_OUT"; then
            LATCHES=$(grep -c '$_DLATCH_' "$YOSYS_OUT" || true)
            if [[ "$LATCHES" -gt 0 ]]; then
                echo "[FAIL] yosys: $LATCHES latch cell(s) found — fix before simulation"
                TOTAL_FAILS=$((TOTAL_FAILS + 1))
            else
                echo "[PASS] yosys: 0 latches"
            fi
        else
            echo "[FAIL] yosys: synthesis errors"
            TOTAL_FAILS=$((TOTAL_FAILS + 1))
        fi
        rm -f "$YOSYS_OUT"
        echo ""
    fi
fi

# ── rtl_style_check ──────────────────────────────────
if [[ $RUN_STYLE -eq 1 ]]; then
    echo "── rtl_style_check ──"
    STYLE_OUT=$(mktemp)
    if $STYLE_CHECK "${FILES[@]}" > "$STYLE_OUT" 2>&1; then
        echo "[PASS] rtl_style_check: no violations"
    else
        ERRORS=$(grep -c '^\[E\]' "$STYLE_OUT" || true)
        WARNS=$(grep -c '^\[W\]' "$STYLE_OUT" || true)
        cat "$STYLE_OUT"
        if [[ "$ERRORS" -gt 0 ]]; then
            echo "[FAIL] rtl_style_check: $ERRORS error(s) — fix before simulation"
            TOTAL_FAILS=$((TOTAL_FAILS + 1))
        else
            echo "[WARN] rtl_style_check: $WARNS warning(s) — review before simulation"
        fi
    fi
    rm -f "$STYLE_OUT"
    echo ""
fi

# ── per-module standalone compile ────────────────────
if [[ $RUN_COMPILE -eq 1 ]]; then
    echo "── standalone compile (per-module) ──"
    for f in "${FILES[@]}"; do
        if $IVERILOG -g2012 -o /dev/null "$f" 2>/dev/null; then
            echo "  [PASS] $f"
        else
            echo "  [FAIL] $f — has undeclared dependencies or incomplete logic"
            TOTAL_FAILS=$((TOTAL_FAILS + 1))
        fi
    done
    echo ""
fi

# ── summary ──────────────────────────────────────────
if [[ $TOTAL_FAILS -eq 0 ]]; then
    echo "=== ALL CHECKS PASS ==="
    exit 0
else
    echo "=== $TOTAL_FAILS CHECK(S) FAILED ==="
    exit 1
fi
