#!/usr/bin/env bash
# Fails when kit code writes a raw colour. Every colour comes from the
# generated palette (packages/bb_tokens/lib/src/colors.g.dart, see
# packages/bb_tokens/README.md); widgets read BbTheme roles or AppColors.
#
# Checked: packages/agent_kit, packages/bb_ui and apps/. Not checked: generated
# files (*.g.dart), tests (test/ folders) and packages/bb_tokens itself, which
# is where the few base constants (kTransparent, kMaskOpaque) live.
# Colors.transparent is Material and not used; kTransparent is the kit's name.
#
# Usage: scripts/check-raw-colours.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

pattern='Color\(\s*0x|Color\.fromARGB|Color\.fromRGBO|Color\.from\('
hits=$(git grep -nE "$pattern" -- \
  'packages/agent_kit/*.dart' 'packages/bb_ui/*.dart' 'apps/*.dart' \
  ':(exclude)*.g.dart' ':(exclude)*/test/*' || true)

if [[ -n $hits ]]; then
  echo "Raw colours in kit code (use a BbTheme role or a palette role instead):" >&2
  echo "$hits" >&2
  exit 1
fi
echo "No raw colours in packages/agent_kit, packages/bb_ui or apps/."
