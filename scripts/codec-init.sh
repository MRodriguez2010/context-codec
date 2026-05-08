#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: codec-init.sh [options]

Initialize context-codec workspace structure.

Options:
  -d, --dir PATH       Codec data directory (default: ~/.openclaw/workspace/.context-codec)
  -a, --agent NAME     Initialize for a specific agent (creates agents/<name>/ subtree)
  -f, --force          Overwrite existing config/digest (default: skip if exists)
  -m, --max-tokens N   Set digest max_tokens (default: 2000)
  -h, --help           Show this help
USAGE
}

CODEC_DIR="${HOME}/.openclaw/workspace/.context-codec"
AGENT=""
FORCE=false
MAX_TOKENS=2000

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)        CODEC_DIR="${2-}"; shift 2 ;;
    -a|--agent)      AGENT="${2-}"; shift 2 ;;
    -f|--force)      FORCE=true; shift ;;
    -m|--max-tokens) MAX_TOKENS="${2-}"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -n "$AGENT" ]]; then
  TARGET_DIR="$CODEC_DIR/agents/$AGENT"
else
  TARGET_DIR="$CODEC_DIR"
fi

mkdir -p "$TARGET_DIR/turns"

write_if_missing() {
  local file="$1"
  local content="$2"
  if [[ "$FORCE" == true ]] || [[ ! -f "$file" ]]; then
    printf '%s\n' "$content" > "$file"
    echo "Created $file"
  else
    echo "Skipped $file (exists, use --force to overwrite)"
  fi
}

write_if_missing "$TARGET_DIR/config.json" '{
  "version": "1.0.0",
  "encoding": {
    "tool_output": true,
    "agent_reasoning": true,
    "user_messages": false
  },
  "digest": {
    "max_tokens": '"$MAX_TOKENS"',
    "update_strategy": "delta_merge",
    "archive_turns": true
  },
  "metrics": {
    "track_compression_ratio": true,
    "track_token_savings": true
  }
}'

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
write_if_missing "$TARGET_DIR/digest.md" "## DIGEST v1 | Turn 0 | $TIMESTAMP
### GOAL: awaiting first message
### STATE: fresh session
### CONTEXT: (none)
### PENDING: (none)
### ARTIFACTS: (none)
### TOOL_CACHE: (empty)"

write_if_missing "$TARGET_DIR/metrics.json" '{
  "session_start": "'"$TIMESTAMP"'",
  "current_turn": 0,
  "turns": [],
  "total_raw_tokens": 0,
  "total_compressed_tokens": 0,
  "overall_ratio": 0
}'

echo ""
echo "Context Codec initialized at $TARGET_DIR"
