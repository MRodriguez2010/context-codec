#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: codec.sh <command> [options]

Context Codec — streaming compression protocol for AI agent conversations.

Commands:
  init               Initialize codec workspace
  status             Show current digest state, turn count, compression ratio
  digest             Display the full current digest
  ratio              Show compression metrics
  validate           Validate digest format
  reset              Reset digest and metrics to initial state
  archive            Archive current turn
  check-limit        Check if digest is within token limit
  info               Quick digest metadata

Options:
  -d, --dir PATH       Codec data directory (default: ~/.openclaw/workspace/.context-codec)
  -a, --agent NAME     Target specific agent
  -h, --help           Show this help

Piping:
  echo "<new digest>" | codec.sh update     Write new digest from stdin
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEC_DIR="${HOME}/.openclaw/workspace/.context-codec"
AGENT=""
COMMAND=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)    CODEC_DIR="${2-}"; shift 2 ;;
    -a|--agent)  AGENT="${2-}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          EXTRA_ARGS+=("$1"); shift ;;
    *)
      if [[ -z "$COMMAND" ]]; then
        COMMAND="$1"; shift
      else
        EXTRA_ARGS+=("$1"); shift
      fi
      ;;
  esac
done

if [[ -z "$COMMAND" ]]; then
  usage
  exit 0
fi

AGENT_ARGS=()
if [[ -n "$AGENT" ]]; then
  AGENT_ARGS=(-a "$AGENT")
fi
DIR_ARGS=(-d "$CODEC_DIR")

case "$COMMAND" in
  init)
    bash "$SCRIPT_DIR/codec-init.sh" "${DIR_ARGS[@]}" "${AGENT_ARGS[@]}" "${EXTRA_ARGS[@]}"
    ;;

  status)
    echo "Context Codec Status"
    echo "===================="
    echo ""

    bash "$SCRIPT_DIR/codec-digest.sh" info "${DIR_ARGS[@]}" "${AGENT_ARGS[@]}" 2>/dev/null || echo "(no digest found)"
    echo ""
    bash "$SCRIPT_DIR/codec-metrics.sh" ratio "${DIR_ARGS[@]}" "${AGENT_ARGS[@]}" 2>/dev/null || echo "(no metrics found)"
    ;;

  digest)
    bash "$SCRIPT_DIR/codec-digest.sh" read "${DIR_ARGS[@]}" "${AGENT_ARGS[@]}"
    ;;

  ratio)
    bash "$SCRIPT_DIR/codec-metrics.sh" status "${DIR_ARGS[@]}" "${AGENT_ARGS[@]}"
    ;;

  validate)
    bash "$SCRIPT_DIR/codec-digest.sh" validate "${DIR_ARGS[@]}" "${AGENT_ARGS[@]}"
    ;;

  reset)
    bash "$SCRIPT_DIR/codec-digest.sh" reset "${DIR_ARGS[@]}" "${AGENT_ARGS[@]}"
    bash "$SCRIPT_DIR/codec-metrics.sh" reset "${DIR_ARGS[@]}" "${AGENT_ARGS[@]}"
    echo "Digest and metrics reset to initial state"
    ;;

  archive)
    bash "$SCRIPT_DIR/codec-digest.sh" archive-turn "${DIR_ARGS[@]}" "${AGENT_ARGS[@]}"
    ;;

  update)
    bash "$SCRIPT_DIR/codec-digest.sh" update "${DIR_ARGS[@]}" "${AGENT_ARGS[@]}"
    ;;

  check-limit)
    bash "$SCRIPT_DIR/codec-digest.sh" check-limit "${DIR_ARGS[@]}" "${AGENT_ARGS[@]}"
    ;;

  info)
    bash "$SCRIPT_DIR/codec-digest.sh" info "${DIR_ARGS[@]}" "${AGENT_ARGS[@]}"
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Run 'codec.sh --help' for usage" >&2
    exit 1
    ;;
esac
