#!/usr/bin/env bash
# Tests scripts/check-raw-colours.sh in a throwaway git repository: clean
# code passes; each kind of raw colour fails in each checked folder; generated
# files, tests and other packages are ignored.
#
# Usage: scripts/test-check-raw-colours.sh
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)/check-raw-colours.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q
mkdir scripts
cp "$src" scripts/check-raw-colours.sh

failures=0
expect() { # expect <pass|fail> <description> <path> <content>
  local want=$1 desc=$2 path=$3 content=$4 rc=0
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  bash scripts/check-raw-colours.sh >/dev/null 2>&1 || rc=$?
  rm -f "$path"
  if [[ $want == pass && $rc -ne 0 ]] || [[ $want == fail && $rc -eq 0 ]]; then
    echo "FAIL: $desc (wanted $want, exit $rc)" >&2
    failures=$((failures + 1))
  else
    echo "ok: $desc"
  fi
}

clean='final c = theme.colors.surface;'
expect pass 'no files' packages/agent_kit/lib/a.dart "$clean"
expect fail 'hex literal in agent_kit' packages/agent_kit/lib/a.dart 'const c = Color(0xFF112233);'
expect fail 'hex literal with spaces' packages/agent_kit/lib/a.dart 'const c = Color ( 0xFF112233 );'
expect fail 'fromARGB in agent_kit_core' packages/agent_kit_core/lib/a.dart 'final c = Color.fromARGB(255, 1, 2, 3);'
expect fail 'fromRGBO in agent_kit_bubblepaw' packages/agent_kit_bubblepaw/lib/a.dart 'final c = Color.fromRGBO(1, 2, 3, 1);'
expect fail 'Color.from in the gallery' apps/gallery/lib/a.dart 'final c = Color.from(alpha: 1, red: 0, green: 0, blue: 0);'
expect fail 'decimal literal' apps/gallery/lib/a.dart 'final c = Color(4278190080);'
expect pass 'palette roles' apps/gallery/lib/a.dart "$clean"
expect pass 'generated file ignored' packages/agent_kit/lib/a.g.dart 'const c = Color(0xFF112233);'
expect pass 'test folder ignored' packages/agent_kit/test/a_test.dart 'const c = Color(0xFF112233);'
expect pass 'other package ignored' packages/other/lib/a.dart 'const c = Color(0xFF112233);'

if ((failures > 0)); then
  echo "$failures case(s) failed" >&2
  exit 1
fi
echo "All cases passed."
