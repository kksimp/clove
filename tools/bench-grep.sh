#!/bin/bash
# `clove grep` against extract + grep(1) and against zstd -dc | grep, on many log files.
#   tools/bench-grep.sh [FILES] [MB_EACH]      from the repository root; AIL=/path/to/ail (default ../ail)
# Corpus: FILES (default 64) generated log files of MB_EACH (default 1) MB, with one rare error
# line planted in one file. Archives at 1 MB (fast default) and 128 KB blocks. For each query:
# hits, seconds, blocks decoded of total, bytes decompressed, and peak RSS. Rare, medium, common and
# short (under three bytes, so no index help) queries cover best and worst cases. Prints
# MISMATCH and exits 1 when clove grep and grep(1) disagree on a hit count.
set -eu
cd "$(git rev-parse --show-toplevel)"
ail_dir=$(cd "${AIL:-../ail}" && pwd)
nf=${1:-64}; each=$(( ${2:-1} * 1048576 ))
tmp=$(mktemp -d "${TMPDIR:-/tmp}/clove-gb.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
"$ail_dir/ail" build clove.ail -o "$tmp/clove" >/dev/null
c="$tmp/logs"; mkdir -p "$c"
for i in $(seq 1 "$nf"); do
  awk -v n="$each" -v seed="$i" -v rare=$(( i == nf / 2 + 1 )) 'BEGIN{srand(seed); while (s < n) {
    l = sprintf("2026-10-25T12:%02d:%02d level=%s req=%d path=/api/v1/items/%d ms=%d\n", int(rand()*60), int(rand()*60), (rand()<.9?"info":"warn"), int(rand()*1e6), int(rand()*500), int(rand()*900))
    if (rare && s > n / 2 && !done) { l = "2026-10-25T12:30:00 level=error code=E7731 disk quota exceeded on vol3\n"; done = 1 }
    printf "%s", l; s += length(l) } }' >"$c/app-$i.log"
done
total=$(cat "$c"/*.log | wc -c | tr -d ' ')
ns() { date +%s%N; }
tm=/usr/bin/time; [ "$(uname)" = Darwin ] && tmflag=-l || tmflag=-v
# peak RSS in MB from a time log, either GNU (-v) or BSD (-l)
rss() { awk '/Maximum resident set size/{print int($NF/1024)} /maximum resident set size/{print int($1/1048576)}' "$1" | head -1; }
secs() { echo "($2 - $1) / 1000000000" | bc -l; }
tar -C "$tmp" -cf "$tmp/logs.tar" logs
zstd -q -19 -T0 "$tmp/logs.tar" -o "$tmp/logs.tar.zst" 2>/dev/null || true
queries=("E7731 disk quota" "items/42 ms=17" "level=warn" "ms")
fail=0
got=()
echo "corpus: $nf files, $total bytes"
echo
echo "| archive | query | hits | seconds | blocks decoded | bytes decompressed | peak MB |"
echo "|---|---|---:|---:|---:|---:|---:|"
for kb in 1024 128; do
  a="$tmp/l$kb.clove"
  "$tmp/clove" a -m fast -b $kb "$a" "$c" >/dev/null
  ix=$("$tmp/clove" describe --json "$a" | grep -o '"index": {[^}]*}' | grep -o '"bytes": [0-9]*' | grep -o '[0-9]*$')
  echo "| clove -b $kb: $(wc -c <"$a" | tr -d ' ') B, index $ix B | | | | | | |"
  for i in "${!queries[@]}"; do
    q=${queries[$i]}
    s=$(ns)
    $tm $tmflag "$tmp/clove" grep --json --max 100000000 "$a" "$q" >"$tmp/out.json" 2>"$tmp/t1"
    e=$(ns)
    hits=$(grep -o '"line": ' "$tmp/out.json" | wc -l | tr -d ' ')
    got[$i]=$hits
    blk=$(grep -o '"blocks": [0-9]*' "$tmp/out.json" | tail -1 | grep -o '[0-9]*$')
    dec=$(grep -o '"decoded": [0-9]*' "$tmp/out.json" | tail -1 | grep -o '[0-9]*$')
    printf '| clove -b %s | `%s` | %s | %.2f | %s / %s | ~%s | %s |\n' "$kb" "$q" "$hits" "$(secs $s $e)" "$dec" "$blk" "$(( dec * kb * 1024 < total ? dec * kb * 1024 : total ))" "$(rss "$tmp/t1")"
  done
  for i in "${!queries[@]}"; do
    q=${queries[$i]}
    s=$(ns)
    $tm $tmflag "$tmp/clove" x "$a" "$tmp/x" >/dev/null 2>"$tmp/t1"
    hits=$(grep -r -n -F -- "$q" "$tmp/x" | wc -l | tr -d ' ')
    rm -rf "$tmp/x"
    e=$(ns)
    [ "$hits" = "${got[$i]}" ] || { echo "MISMATCH -b $kb \`$q\`: clove ${got[$i]}, grep $hits"; fail=1; }
    printf '| clove x + grep | `%s` | %s | %.2f | all | %s | %s |\n' "$q" "$hits" "$(secs $s $e)" "$total" "$(rss "$tmp/t1")"
  done
done
if [ -f "$tmp/logs.tar.zst" ]; then
  for q in "${queries[@]}"; do
    s=$(ns)
    hits=$(zstd -dc "$tmp/logs.tar.zst" | grep -a -F -- "$q" | wc -l | tr -d ' ')
    e=$(ns)
    printf '| zstd -dc tar + grep | `%s` | %s | %.2f | all | %s | |\n' "$q" "$hits" "$(secs $s $e)" "$total"
  done
fi
exit $fail
