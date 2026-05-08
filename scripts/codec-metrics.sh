#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: codec-metrics.sh <command> [options]

Track and display context-codec compression metrics.

Commands:
  record            Record a turn's compression stats (requires --turn, --raw, --compressed)
  ratio             Show cumulative compression ratio
  status            Show full metrics summary
  reset             Reset metrics to zero
  export            Export metrics as JSON to stdout

Options:
  -d, --dir PATH           Codec data directory (default: ~/.openclaw/workspace/.context-codec)
  -a, --agent NAME         Use agent-specific metrics
  -t, --turn N             Turn number for record command
  -r, --raw N              Raw token count for record command
  -c, --compressed N       Compressed token count for record command
  -h, --help               Show this help
USAGE
}

CODEC_DIR="${HOME}/.openclaw/workspace/.context-codec"
AGENT=""
COMMAND=""
TURN=""
RAW=""
COMPRESSED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)         CODEC_DIR="${2-}"; shift 2 ;;
    -a|--agent)       AGENT="${2-}"; shift 2 ;;
    -t|--turn)        TURN="${2-}"; shift 2 ;;
    -r|--raw)         RAW="${2-}"; shift 2 ;;
    -c|--compressed)  COMPRESSED="${2-}"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    -*)               echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *)
      if [[ -z "$COMMAND" ]]; then
        COMMAND="$1"; shift
      else
        echo "Unexpected argument: $1" >&2; exit 1
      fi
      ;;
  esac
done

if [[ -z "$COMMAND" ]]; then
  echo "No command specified" >&2
  usage
  exit 1
fi

if [[ -n "$AGENT" ]]; then
  TARGET_DIR="$CODEC_DIR/agents/$AGENT"
else
  TARGET_DIR="$CODEC_DIR"
fi

METRICS_LOG="$TARGET_DIR/metrics.log"
METRICS_FILE="$TARGET_DIR/metrics.json"

ensure_log() {
  mkdir -p "$TARGET_DIR"
  if [[ ! -f "$METRICS_LOG" ]]; then
    touch "$METRICS_LOG"
  fi
}

compute_totals() {
  ensure_log
  local total_raw=0
  local total_comp=0
  local count=0
  local last_turn=0

  while IFS=$'\t' read -r t r c ts; do
    total_raw=$((total_raw + r))
    total_comp=$((total_comp + c))
    last_turn=$t
    ((count++))
  done < "$METRICS_LOG"

  echo "$count $last_turn $total_raw $total_comp"
}

case "$COMMAND" in
  record)
    if [[ -z "$TURN" || -z "$RAW" || -z "$COMPRESSED" ]]; then
      echo "record requires --turn, --raw, and --compressed" >&2
      exit 1
    fi
    ensure_log

    local_ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    printf '%s\t%s\t%s\t%s\n' "$TURN" "$RAW" "$COMPRESSED" "$local_ts" >> "$METRICS_LOG"

    if [[ $RAW -gt 0 ]]; then
      turn_ratio=$(awk "BEGIN { printf \"%.1f\", $RAW / ($COMPRESSED > 0 ? $COMPRESSED : 1) }")
      savings=$(awk "BEGIN { printf \"%.0f\", (1 - $COMPRESSED / $RAW) * 100 }")
    else
      turn_ratio="0"
      savings="0"
    fi

    echo "Recorded turn $TURN: ${RAW} -> ${COMPRESSED} tokens (${turn_ratio}:1, ${savings}% savings)"
    ;;

  ratio)
    read -r count last_turn total_raw total_comp <<< "$(compute_totals)"

    if [[ $total_comp -gt 0 ]]; then
      ratio=$(awk "BEGIN { printf \"%.1f\", $total_raw / $total_comp }")
      savings=$(awk "BEGIN { printf \"%.0f\", (1 - $total_comp / $total_raw) * 100 }")
    else
      ratio="0"
      savings="0"
    fi

    echo "Compression ratio: ${ratio}:1 (${savings}% savings over ${count} turns)"
    echo "Raw tokens:        ${total_raw}"
    echo "Compressed tokens: ${total_comp}"
    ;;

  status)
    read -r count last_turn total_raw total_comp <<< "$(compute_totals)"

    if [[ $total_comp -gt 0 ]]; then
      ratio=$(awk "BEGIN { printf \"%.1f\", $total_raw / $total_comp }")
      savings=$(awk "BEGIN { printf \"%.0f\", (1 - $total_comp / $total_raw) * 100 }")
    else
      ratio="0"
      savings="0"
    fi

    saved=$((total_raw - total_comp))

    echo "Context Codec Metrics"
    echo "====================="
    echo "Turns recorded:    $count"
    echo "Last turn:         $last_turn"
    echo "Raw tokens:        $total_raw"
    echo "Compressed tokens: $total_comp"
    echo "Tokens saved:      $saved"
    echo "Compression ratio: ${ratio}:1"
    echo "Savings:           ${savings}%"

    num_archived=$(find "$TARGET_DIR/turns" -maxdepth 1 -name 'T*.md' 2>/dev/null | wc -l | tr -d ' ')
    echo "Archived turns:    $num_archived"
    ;;

  reset)
    > "$METRICS_LOG" 2>/dev/null || true
    rm -f "$METRICS_FILE" 2>/dev/null || true
    echo "Metrics reset"
    ;;

  export)
    read -r count last_turn total_raw total_comp <<< "$(compute_totals)"

    if [[ $total_comp -gt 0 ]]; then
      ratio=$(awk "BEGIN { printf \"%.1f\", $total_raw / $total_comp }")
    else
      ratio="0"
    fi

    echo "{"
    echo "  \"current_turn\": $last_turn,"
    echo "  \"total_turns\": $count,"
    echo "  \"total_raw_tokens\": $total_raw,"
    echo "  \"total_compressed_tokens\": $total_comp,"
    echo "  \"overall_ratio\": $ratio,"
    echo "  \"turns\": ["

    first=true
    while IFS=$'\t' read -r t r c ts; do
      if [[ "$first" == true ]]; then
        first=false
      else
        echo ","
      fi
      local_ratio=$(awk "BEGIN { printf \"%.1f\", $r / ($c > 0 ? $c : 1) }")
      printf '    {"turn":%s,"raw":%s,"compressed":%s,"ratio":%s,"ts":"%s"}' "$t" "$r" "$c" "$local_ratio" "$ts"
    done < "$METRICS_LOG"

    echo ""
    echo "  ]"
    echo "}"
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    usage
    exit 1
    ;;
esac
