#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: codec-digest.sh <command> [options]

Manage the context-codec running digest.

Commands:
  read              Print current digest to stdout
  validate          Check digest format, report issues
  tokens            Estimate token count of current digest
  check-limit       Exit 0 if under max_tokens, exit 1 if over (prints count)
  update            Write new digest content from stdin
  archive-turn      Archive current turn to turns/T{N}.md
  backup            Copy current digest to digest.bak.md
  reset             Reset digest to initial state
  info              Show digest metadata (turn, goal, state)

Options:
  -d, --dir PATH       Codec data directory (default: ~/.openclaw/workspace/.context-codec)
  -a, --agent NAME     Use agent-specific digest
  -h, --help           Show this help
USAGE
}

CODEC_DIR="${HOME}/.openclaw/workspace/.context-codec"
AGENT=""
COMMAND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)    CODEC_DIR="${2-}"; shift 2 ;;
    -a|--agent)  AGENT="${2-}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *)
      if [[ -z "$COMMAND" ]]; then
        COMMAND="$1"; shift
      else
        echo "Unexpected argument: $1" >&2; usage; exit 1
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

DIGEST_FILE="$TARGET_DIR/digest.md"
CONFIG_FILE="$TARGET_DIR/config.json"
METRICS_FILE="$TARGET_DIR/metrics.json"

estimate_tokens() {
  local text="$1"
  local words
  words=$(printf '%s' "$text" | wc -w | tr -d ' ')
  local chars
  chars=$(printf '%s' "$text" | wc -c | tr -d ' ')
  # Approximate: tokens ~ words * 1.3, but also account for punctuation/symbols
  # A more accurate heuristic: chars / 4 (GPT-style) averaged with words * 1.3
  local by_chars=$(( chars / 4 ))
  local by_words=$(( (words * 13 + 5) / 10 ))
  echo $(( (by_chars + by_words) / 2 ))
}

get_max_tokens() {
  if [[ -f "$CONFIG_FILE" ]]; then
    local max
    max=$(grep -o '"max_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG_FILE" | grep -o '[0-9]*' | head -1)
    echo "${max:-2000}"
  else
    echo "2000"
  fi
}

extract_field() {
  local field="$1"
  local content="$2"
  printf '%s\n' "$content" | grep -i "^### ${field}:" | sed "s/^### ${field}:[[:space:]]*//" | head -1
}

extract_header() {
  local content="$1"
  printf '%s\n' "$content" | head -1
}

get_turn_number() {
  local header="$1"
  printf '%s' "$header" | grep -o 'Turn [0-9]*' | grep -o '[0-9]*' | head -1
}

REQUIRED_SECTIONS=("GOAL" "STATE" "CONTEXT" "PENDING" "ARTIFACTS" "TOOL_CACHE")

case "$COMMAND" in
  read)
    if [[ ! -f "$DIGEST_FILE" ]]; then
      echo "No digest found at $DIGEST_FILE" >&2
      exit 1
    fi
    cat "$DIGEST_FILE"
    ;;

  validate)
    if [[ ! -f "$DIGEST_FILE" ]]; then
      echo "FAIL: No digest found at $DIGEST_FILE" >&2
      exit 1
    fi
    content=$(cat "$DIGEST_FILE")
    errors=0

    header=$(extract_header "$content")
    if ! printf '%s' "$header" | grep -q "^## DIGEST"; then
      echo "FAIL: Missing DIGEST header (first line should start with '## DIGEST')"
      ((errors++))
    fi

    if ! printf '%s' "$header" | grep -q "Turn [0-9]"; then
      echo "FAIL: Missing turn number in header"
      ((errors++))
    fi

    for section in "${REQUIRED_SECTIONS[@]}"; do
      if ! printf '%s\n' "$content" | grep -qi "^### ${section}:"; then
        echo "FAIL: Missing section: ### $section"
        ((errors++))
      fi
    done

    tokens=$(estimate_tokens "$content")
    max=$(get_max_tokens)
    if [[ $tokens -gt $max ]]; then
      echo "WARN: Digest is ~${tokens} tokens, exceeds max_tokens=${max}"
    fi

    if [[ $errors -eq 0 ]]; then
      echo "OK: Digest format is valid (~${tokens} tokens)"
      exit 0
    else
      echo "Found $errors format error(s)"
      exit 1
    fi
    ;;

  tokens)
    if [[ ! -f "$DIGEST_FILE" ]]; then
      echo "0"
      exit 0
    fi
    content=$(cat "$DIGEST_FILE")
    estimate_tokens "$content"
    ;;

  check-limit)
    if [[ ! -f "$DIGEST_FILE" ]]; then
      echo "0"
      exit 0
    fi
    content=$(cat "$DIGEST_FILE")
    tokens=$(estimate_tokens "$content")
    max=$(get_max_tokens)
    echo "$tokens/$max"
    if [[ $tokens -gt $max ]]; then
      exit 1
    else
      exit 0
    fi
    ;;

  update)
    mkdir -p "$TARGET_DIR"
    new_content=$(cat)
    if [[ -z "$new_content" ]]; then
      echo "No content provided on stdin" >&2
      exit 1
    fi

    if [[ -f "$DIGEST_FILE" ]]; then
      cp "$DIGEST_FILE" "$DIGEST_FILE.prev"
    fi

    printf '%s\n' "$new_content" > "$DIGEST_FILE"

    tokens=$(estimate_tokens "$new_content")
    echo "Digest updated (~${tokens} tokens)"
    ;;

  archive-turn)
    if [[ ! -f "$DIGEST_FILE" ]]; then
      echo "No digest to archive" >&2
      exit 1
    fi
    content=$(cat "$DIGEST_FILE")
    header=$(extract_header "$content")
    turn=$(get_turn_number "$header")
    turn=${turn:-0}

    padded=$(printf 'T%03d' "$turn")
    turn_file="$TARGET_DIR/turns/${padded}.md"

    if [[ -f "$turn_file" ]]; then
      echo "Turn file $turn_file already exists, skipping"
      exit 0
    fi

    mkdir -p "$TARGET_DIR/turns"
    cp "$DIGEST_FILE" "$turn_file"
    echo "Archived turn $turn to $turn_file"
    ;;

  backup)
    if [[ ! -f "$DIGEST_FILE" ]]; then
      echo "No digest to backup" >&2
      exit 1
    fi
    cp "$DIGEST_FILE" "$DIGEST_FILE.bak"
    echo "Backed up to $DIGEST_FILE.bak"
    ;;

  reset)
    TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    cat > "$DIGEST_FILE" << EOF
## DIGEST v1 | Turn 0 | $TIMESTAMP
### GOAL: awaiting first message
### STATE: fresh session
### CONTEXT: (none)
### PENDING: (none)
### ARTIFACTS: (none)
### TOOL_CACHE: (empty)
EOF
    echo "Digest reset to initial state"
    ;;

  info)
    if [[ ! -f "$DIGEST_FILE" ]]; then
      echo "No digest found" >&2
      exit 1
    fi
    content=$(cat "$DIGEST_FILE")
    header=$(extract_header "$content")
    turn=$(get_turn_number "$header")
    tokens=$(estimate_tokens "$content")
    max=$(get_max_tokens)
    goal=$(extract_field "GOAL" "$content")
    state=$(extract_field "STATE" "$content")

    num_turns=$(find "$TARGET_DIR/turns" -maxdepth 1 -name 'T*.md' 2>/dev/null | wc -l | tr -d ' ')

    echo "Turn:       ${turn:-0}"
    echo "Goal:       ${goal:-(none)}"
    echo "State:      ${state:-(none)}"
    echo "Tokens:     ~${tokens}/${max}"
    echo "Archived:   ${num_turns} turns"
    echo "Digest:     $DIGEST_FILE"
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    usage
    exit 1
    ;;
esac
