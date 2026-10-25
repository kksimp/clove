#!/bin/bash
# Clove's gate: ail check, fmt --check and the tests, with the AIL checkout pinned in .ail-version.
#   tools/check.sh            from the repository root; AIL=/path/to/ail (default ../ail)
# Prints only failures; the last line is `CHECK GREEN` or `CHECK RED (N)`.
set -u
cd "$(git rev-parse --show-toplevel)"
ail_dir=${AIL:-../ail}
pin=$(cat .ail-version)
have=$(git -C "$ail_dir" rev-parse --short=8 HEAD 2>/dev/null || echo none)
[ "$have" = "${pin:0:8}" ] || echo "note: $ail_dir is at $have, .ail-version pins $pin"
ail="$ail_dir/ail"
fails=0
red() { fails=$((fails+1)); echo "RED $1"; }
files=$(git ls-files '*.ail')
# shellcheck disable=SC2086
"$ail" fmt --check $files >/dev/null 2>&1 || red "fmt: run $ail fmt on the files above"
"$ail" check . >/dev/null 2>&1 || red "$ail check ."
for f in $(grep -l '^@test' $files); do "$ail" test "$f" >/dev/null 2>&1 || red "$ail test $f"; done
for f in $(git ls-files '*.sh'); do bash -n "$f" || red "bash -n $f"; done
[ $fails = 0 ] && echo "CHECK GREEN" || echo "CHECK RED ($fails)"
[ $fails = 0 ]
