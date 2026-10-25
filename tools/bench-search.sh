#!/bin/bash
# What `clove grep` avoids against extract + grep, on logs and prose.
#   tools/bench-search.sh [MAX_MB]      AIL=/path/to/ail (default ../ail)
# One Markdown table per corpus: for each query, matching lines, blocks decoded of total,
# seconds for `clove grep`, seconds for `clove x` + grep -c, and the index share of the archive.
set -eu
cd "$(git rev-parse --show-toplevel)"
ail_dir=$(cd "${AIL:-../ail}" && pwd)
cap=$(( ${1:-8} * 1048576 ))
tmp=$(mktemp -d "${TMPDIR:-/tmp}/clove-bs.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
"$ail_dir/ail" build clove.ail -o "$tmp/clove" >/dev/null
now() { python3 -c 'import time;print(time.time())'; }
field() { grep -o "\"$1\": [0-9]*" | head -1 | grep -o '[0-9]*$'; }
c="$tmp/c"; mkdir -p "$c"
awk -v n="$cap" 'BEGIN{srand(1); while (s < n) { l = sprintf("2026-10-25T12:%02d:%02d level=%s req=%d path=/api/v1/items/%d ms=%d\n", int(rand()*60), int(rand()*60), (rand()<.9?"info":"warn"), int(rand()*1e6), int(rand()*500), int(rand()*900)); if (s > n/2 && !done) { l = "2026-10-25T12:30:00 level=error FATAL signature-7f3a in worker\n"; done = 1 } printf "%s", l; s += length(l) } }' >"$c/logs"
cat "$ail_dir"/docs/*.md "$ail_dir"/docs/*/*.md | head -c "$cap" >"$c/prose"
bench() { # file, then queries
  f=$1; shift
  size=$(wc -c <"$c/$f")
  "$tmp/clove" a "$tmp/$f.clove" "$c/$f" >/dev/null
  asize=$(wc -c <"$tmp/$f.clove")
  ibytes=$("$tmp/clove" describe --json "$tmp/$f.clove" | field bytes)
  echo; echo "### $f: $size bytes -> $asize archive, index $ibytes bytes ($(echo "100 * $ibytes / $asize" | bc -l | cut -c1-4)% of the archive)"; echo
  echo "| query | lines | blocks decoded / total | clove grep s | extract + grep s |"
  echo "|---|---:|---:|---:|---:|"
  for q in "$@"; do
    t0=$(now); j=$("$tmp/clove" grep --json --max 1000000 "$tmp/$f.clove" "$q"); t1=$(now)
    rm -rf "$tmp/x"; mkdir "$tmp/x"
    "$tmp/clove" x "$tmp/$f.clove" "$tmp/x" >/dev/null; n=$(grep -r -c -F -- "$q" "$tmp/x" | awk -F: '{s+=$NF} END{print s+0}'); t2=$(now)
    got=$(echo "$j" | grep -o '"line":' | wc -l | tr -d ' ')
    [ "$got" = "$n" ] || echo "MISMATCH $q: clove $got, grep $n" >&2
    printf '| `%s` | %s | %s / %s | %.2f | %.2f |\n' "$q" "$got" "$(echo "$j" | field decoded)" "$(echo "$j" | field blocks)" "$(echo "$t1 - $t0" | bc -l)" "$(echo "$t2 - $t1" | bc -l)"
  done
}
bench logs "signature-7f3a" "req=424242" "level=warn" "level=info" "ms"
bench prose "ClassifiedDocument" "archive" "the" "ail"
