#!/usr/bin/env bash
# publish.sh — regenerate every generated artifact, or check that they are current.
# Adapted from dialogues-skills/scripts/publish.sh; python3 (stdlib) instead of uv.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
PY="${PYTHON:-python3}"

GENERATED_FILES=(
  "agentsmd/AGENTS.md"
  "README.md"
  ".cursor-plugin/plugin.json"
  ".codex-plugin/plugin.json"
  "mcp.json"
  "mcp.cursor.json"
  "gemini-extension.json"
)

file_sig() {
  local path="$1"
  if [[ -f "$path" ]]; then
    "$PY" -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$path"
  else
    echo "__MISSING__"
  fi
}

run_generate() {
  "$PY" -I scripts/generate_manifests.py
  "$PY" -I scripts/generate_agents.py
}

default_base_ref() {
  if [[ -n "${PUBLISH_BASE_REF:-}" ]]; then
    echo "$PUBLISH_BASE_REF"
  elif git rev-parse --verify --quiet origin/main >/dev/null; then
    echo "origin/main"
  else
    echo "main"
  fi
}

run_publish() {
  local base_ref
  base_ref="$(default_base_ref)"
  if git rev-parse --verify --quiet "$base_ref" >/dev/null; then
    "$PY" -I scripts/plugin_versions.py bump-if-needed "$base_ref"
  else
    echo "No base ref ($base_ref) yet; versions left as they are."
  fi
  run_generate
}

run_check() {
  local before=() changed=()
  for path in "${GENERATED_FILES[@]}"; do
    before+=("$(file_sig "$path")")
  done
  run_generate
  for i in "${!GENERATED_FILES[@]}"; do
    local path="${GENERATED_FILES[$i]}"
    if [[ "${before[$i]}" != "$(file_sig "$path")" ]]; then
      changed+=("$path")
    fi
  done
  if [[ ${#changed[@]} -gt 0 ]]; then
    echo "Generated artifacts are outdated."
    echo "Run: ./scripts/publish.sh"
    echo
    echo "Changed files:"
    printf '%s\n' "${changed[@]}"
    exit 1
  fi
  "$PY" -I scripts/generate_manifests.py --check
  "$PY" -I scripts/plugin_versions.py check
  "$PY" -I scripts/check_schema.py
  for f in bin/* lib/*.sh skills/*/scripts/*.sh; do
    sh -n "$f"
  done
  bash -n scripts/publish.sh
  echo "All generated artifacts are up to date."
}

case "${1:-}" in
  "")
    run_publish
    echo "Publish artifacts generated successfully."
    ;;
  "--check")
    run_check
    ;;
  "-h"|"--help")
    cat <<'EOF'
Usage:
  ./scripts/publish.sh         Generate all publish artifacts
  ./scripts/publish.sh --check Verify generated artifacts are up to date

Set PUBLISH_BASE_REF to override the base used for automatic version bumps.

This script regenerates:
  - .cursor-plugin/plugin.json, .codex-plugin/plugin.json (from .claude-plugin/plugin.json + plugin.json)
  - mcp.json, mcp.cursor.json, gemini-extension.json (from .mcp.json)
  - agentsmd/AGENTS.md and the README.md skills table (from skills/*/SKILL.md)

Versioned manifests are validated with scripts/plugin_versions.py; plugin.json and
mcp.json against the vendored Agent Plugins 1.0.0 schemas with scripts/check_schema.py.
EOF
    ;;
  *)
    echo "Unknown option: $1" >&2
    echo "Use --help for usage." >&2
    exit 2
    ;;
esac
