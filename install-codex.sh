#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/scripts/bootstrap-codex-cli-macos.sh"

if [[ ! -f "$BOOTSTRAP_SCRIPT" ]]; then
  echo "[error] Bootstrap script was not found:"
  echo "        $BOOTSTRAP_SCRIPT"
  exit 1
fi

FORWARDED_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      FORWARDED_ARGS+=("--dry-run")
      shift
      ;;
    -h|--help)
      echo "Usage:"
      echo "  ./install-codex.sh"
      echo "  ./install-codex.sh --dry-run"
      echo
      echo "This launcher runs scripts/bootstrap-codex-cli-macos.sh."
      exit 0
      ;;
    *)
      FORWARDED_ARGS+=("$1")
      shift
      ;;
  esac
done

echo "Starting Codex CLI bootstrap..."
/bin/bash "$BOOTSTRAP_SCRIPT" "${FORWARDED_ARGS[@]}"
