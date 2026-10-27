#!/usr/bin/env bash
# Fails when kit code writes a raw colour. Every colour comes from the
# palette in bb_tokens (BubbleBuffer/bb-ui); widgets read BbTheme roles or
# AppColors.
#
# Vendored from BubbleBuffer/bb-ui, scripts/check-raw-colours.sh at tag
# v0.4.0. Sync: when the bb-ui pin changes, diff this file against that tag.
# Only the checked paths differ (bb-ui checks packages/bb_ui and apps; here
# the kit's own packages and the gallery app are checked).
#
# Checked: packages/agent_kit* and apps/. Not checked: generated files
# (*.g.dart) and tests (test/ folders). Colors.transparent is Material and
# not used; kTransparent from bb_tokens is the UI name.
#
# Usage: scripts/check-raw-colours.sh
# Test:  scripts/test-check-raw-colours.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

pattern='Color[[:space:]]*\([[:space:]]*(0x|[0-9])|Color\.fromARGB|Color\.fromRGBO|Color\.from\('
hits=$(
  while IFS= read -r -d '' file; do
    case "$file" in
      *.g.dart|*/test/*) continue ;;
      *.dart) [[ -f "$file" ]] && grep -nHE "$pattern" -- "$file" || true ;;
    esac
  done < <(git ls-files -z --cached --others --exclude-standard -- 'packages/agent_kit*' apps)
)

if [[ -n $hits ]]; then
  echo "Raw colours in kit code (use a BbTheme role or a palette role instead):" >&2
  echo "$hits" >&2
  exit 1
fi
echo "No raw colours in packages/agent_kit* or apps/."
