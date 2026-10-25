#!/bin/bash
# Clove's two engines against gzip, zstd, xz and 7z on several kinds of data.
#   tools/bench-matrix.sh [MAX_MB]      from the repository root; AIL=/path/to/ail (default ../ail)
# Corpora (built in a temp dir, each capped at MAX_MB, default 8): AIL source code, docs prose,
# repetitive logs, random bytes, already-compressed (tar.gz), and executables (ELF/Mach-O).
# Prints one Markdown table: size, ratio, compress and decompress seconds, peak RSS (MB).
set -eu
cd "$(git rev-parse --show-toplevel)"
ail_dir=$(cd "${AIL:-../ail}" && pwd)
cap=$(( ${1:-8} * 1048576 ))
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"$ail_dir/ail" build clove.ail -o "$tmp/clove" >/dev/null
tm=/usr/bin/time; [ "$(uname)" = Darwin ] && tmflag=-l || tmflag=-v
c="$tmp/corpus"; mkdir -p "$c"
find "$ail_dir/compiler" -name '*.ail' -print0 | sort -z | xargs -0 cat | head -c "$cap" >"$c/source"
cat "$ail_dir"/docs/*.md "$ail_dir"/docs/*/*.md | head -c "$cap" >"$c/prose"
awk -v n="$cap" 'BEGIN{srand(1); while (s < n) { l = sprintf("2026-10-25T12:%02d:%02d level=%s req=%d path=/api/v1/items/%d ms=%d\n", int(rand()*60), int(rand()*60), (rand()<.9?"info":"warn"), int(rand()*1e6), int(rand()*500), int(rand()*900)); printf "%s", l; s += length(l) } }' >"$c/logs"
head -c "$cap" /dev/urandom >"$c/random"
tar -C "$ail_dir" -cf - docs compiler 2>/dev/null | gzip -6 | head -c "$cap" >"$c/gzipped"
for b in "$tmp/clove" "$ail_dir"/ail-bin/* /usr/bin/* ; do [ -f "$b" ] && head -c 4 "$b" | grep -q $'\x7fELF\|\xcf\xfa\xed\xfe' && cat "$b"; done 2>/dev/null | head -c "$cap" >"$c/exe"
# rss KB from a time log, either GNU (-v) or BSD (-l)
rss() { awk '/Maximum resident set size/{print int($NF/1024)} /maximum resident set size/{print int($1/1048576)}' "$1" | head -1; }
row() { # corpus tool bytes csec dsec rssMB
  printf '| %s | %s | %d | %.3f | %.2f | %.2f | %s |\n' "$1" "$2" "$3" "$(echo "$size / $3" | bc -l)" "$4" "$5" "$6"
}
secs() { echo "($2 - $1) / 1000000000" | bc -l; }
echo "| corpus | tool | bytes | ratio | compress s | decompress s | peak MB |"
echo "|---|---|---:|---:|---:|---:|---:|"
for f in "$c"/*; do
  name=$(basename "$f"); size=$(wc -c <"$f")
  for m in fast max; do
    s=$(date +%s%N)
    $tm $tmflag "$tmp/clove" a -m $m -b 4096 "$tmp/a.clove" "$f" >/dev/null 2>"$tmp/t1"
    e=$(date +%s%N)
    $tm $tmflag "$tmp/clove" x "$tmp/a.clove" "$tmp/x" >/dev/null 2>"$tmp/t2"
    e2=$(date +%s%N)
    cmp -s "$f" "$tmp/x/${f#/}" || echo "| $name | clove-$m | ROUND TRIP FAILED | | | | |"
    r1=$(rss "$tmp/t1"); r2=$(rss "$tmp/t2")
    row "$name" "clove-$m" "$(wc -c <"$tmp/a.clove")" "$(secs $s $e)" "$(secs $e $e2)" "$((r1 > r2 ? r1 : r2))"
    rm -rf "$tmp/a.clove" "$tmp/x"
  done
  for t in "gzip -9" "zstd -19 -T0" "xz -9e -T0" "7z"; do
    cmd=${t%% *}; command -v "$cmd" >/dev/null || continue
    s=$(date +%s%N)
    if [ "$cmd" = 7z ]; then $tm $tmflag 7z a -bd -y -mx9 "$tmp/o.7z" "$f" >/dev/null 2>"$tmp/t1"; out="$tmp/o.7z"
    else $tm $tmflag $t -c "$f" >"$tmp/o" 2>"$tmp/t1"; out="$tmp/o"; fi
    e=$(date +%s%N)
    if [ "$cmd" = 7z ]; then $tm $tmflag 7z x -bd -y -o"$tmp/d" "$out" >/dev/null 2>"$tmp/t2"
    else $tm $tmflag $cmd -dc "$out" >/dev/null 2>"$tmp/t2"; fi
    e2=$(date +%s%N)
    r1=$(rss "$tmp/t1"); r2=$(rss "$tmp/t2")
    row "$name" "${t% -T0}" "$(wc -c <"$out")" "$(secs $s $e)" "$(secs $e $e2)" "$((r1 > r2 ? r1 : r2))"
    rm -rf "$tmp/o" "$tmp/o.7z" "$tmp/d"
  done
done
