#!/usr/bin/env bash
#
# logging-smoke-test.sh — Empirically measure which Apple logging mechanisms are
# visible to slog and to the underlying unified log (`log stream` / `log show`).
#
# Fires one tagged line through every logging mechanism (via slog-test-emitter
# --smoke) and greps each marker across every capture path to build a matrix.
#
# Usage: scripts/logging-smoke-test.sh
#
set -uo pipefail
cd "$(dirname "$0")/.."

NONCE="smk-$$-${RANDOM}"
OUT="$(mktemp -d -t slog-smoke)"
EMITTER=".build/debug/slog-test-emitter"
SLOG=".build/debug/slog"
PROC="slog-test-emitter"
PRED="processImagePath CONTAINS \"slog-test-emitter\""

echo "==> Building (debug)…"
swift build >/dev/null 2>&1 || { echo "build failed"; swift build; exit 1; }

echo "==> nonce=$NONCE   out=$OUT"

# --- Start concurrent live captures BEFORE emitting ---------------------------
# Ground truth: everything the unified log sees from this process, all levels.
/usr/bin/log stream --style ndjson --info --debug --signpost \
  --predicate "$PRED" >"$OUT/gt_stream.txt" 2>/dev/null &
GT_PID=$!

# slog stream, subsystem-filtered (auto-debug ON). Self-terminates via --capture
# so stdio buffers flush cleanly (a hard kill would lose block-buffered output).
"$SLOG" stream --subsystem com.slog.smoke --timeout 12s --capture 5s \
  >"$OUT/slog_stream_sub.txt" 2>/dev/null &
SS_PID=$!

# slog stream, process-filtered (auto-debug OFF — no subsystem set).
"$SLOG" stream --process "$PROC" --timeout 12s --capture 5s \
  >"$OUT/slog_stream_proc.txt" 2>/dev/null &
SP_PID=$!

echo "==> Waiting for streams to warm up…"
sleep 5

# --- Emit the smoke batch repeatedly through every mechanism ------------------
# A one-shot batch races stream startup latency (slog spawns `log stream` and
# gates --capture on the first matched entry). Emitting several batches across
# the window guarantees the live streams overlap at least one batch.
echo "==> Emitting smoke batches…"
: >"$OUT/emit_stdout.txt"; : >"$OUT/emit_stderr.txt"
for _ in 1 2 3 4 5 6; do
  "$EMITTER" --smoke "$NONCE" >>"$OUT/emit_stdout.txt" 2>>"$OUT/emit_stderr.txt"
  sleep 1
done

echo "==> Letting slog streams capture + flush…"
wait "$SS_PID" "$SP_PID" 2>/dev/null
kill "$GT_PID" 2>/dev/null
wait "$GT_PID" 2>/dev/null

# --- Historical (disk) captures -----------------------------------------------
echo "==> Querying historical (log show / slog show)…"
/usr/bin/log show --last 2m --style ndjson --info --debug --signpost \
  --predicate "$PRED" >"$OUT/gt_show.txt" 2>/dev/null

"$SLOG" show --last 2m --subsystem com.slog.smoke >"$OUT/slog_show_sub.txt" 2>/dev/null
"$SLOG" show --last 2m --process "$PROC"          >"$OUT/slog_show_proc.txt" 2>/dev/null

# --- Build the matrix ---------------------------------------------------------
has() { grep -Fq "SMOKE|$NONCE|$1" "$2" 2>/dev/null && echo "YES" || echo " . "; }

FILES=("emit_stdout.txt" "emit_stderr.txt" "gt_stream.txt" "gt_show.txt" \
       "slog_stream_sub.txt" "slog_stream_proc.txt" "slog_show_sub.txt" "slog_show_proc.txt")

IDS=(print_stdout debugprint_stdout filehandle_stderr fputs_stderr nslog \
     oslog_default oslog_info oslog_debug oslog_error oslog_fault \
     logger_trace logger_debug logger_info logger_notice logger_warning \
     logger_error logger_critical logger_fault logger_private logger_public \
     signpost_begin signpost_event)

echo
printf '%-20s | %s | %s | %s | %s | %s | %s | %s | %s\n' \
  "mechanism|id" "stdout" "stderr" "GTstrm" "GTshow" "slgSTRsub" "slgSTRprc" "slgSHWsub" "slgSHWprc"
printf '%s\n' "-------------------------------------------------------------------------------------------------------"
for id in "${IDS[@]}"; do
  row="$(printf '%-20s' "$id")"
  for f in "${FILES[@]}"; do
    row="$row |  $(has "$id" "$OUT/$f") "
  done
  echo "$row"
done

echo
echo "==> Redaction check (logger_private line):"
grep -F "SMOKE|$NONCE|logger_private" "$OUT/gt_stream.txt" | head -1 | sed 's/^/   gt_stream: /' || echo "   (not captured)"
echo "   secret leaked in gt_stream? $(grep -Fq "SECRET-$NONCE" "$OUT/gt_stream.txt" 2>/dev/null && grep -F "logger_private" "$OUT/gt_stream.txt" | grep -Fq "SECRET-$NONCE" && echo YES || echo 'NO (redacted as <private>)')"

echo
echo "==> Artifacts in $OUT"
