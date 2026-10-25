#!/bin/bash
# Clove (native AIL build) against the usual tools, on one file.
#   bench.sh FILE     from the repository root; AIL=/path/to/ail (default ../ail)
# Builds clove.ail natively, then times gzip, xz, zstd and 7z where installed.
# For several kinds of data at once, with memory, use tools/bench-matrix.sh.
set -eu
f=${1:?usage: bench.sh FILE}
f=$(cd "$(dirname "$f")" && pwd)/$(basename "$f")
cd "$(git rev-parse --show-toplevel)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"${AIL:-../ail}/ail" build clove.ail -o "$tmp/clove" >/dev/null
echo "== clove (AIL, native) =="; "$tmp/clove" bench "$f"
size=$(wc -c <"$f")
t() { # name, command writing the compressed file to $tmp/out
  local s e
  s=$(date +%s%N); "$@" >/dev/null 2>&1 || return 0; e=$(date +%s%N)
  printf '%-10s %12d bytes  ratio %.3f  %6d ms\n' "$name" "$(wc -c <"$tmp/out")" \
    "$(echo "$size / $(wc -c <"$tmp/out")" | bc -l)" $(((e - s) / 1000000))
}
echo "== tools (single file) =="
name=gzip-9;   command -v gzip >/dev/null && t sh -c "gzip -9 -c '$f' >$tmp/out"
name=zstd-19;  command -v zstd >/dev/null && t sh -c "zstd -19 -T0 -q -c '$f' >$tmp/out"
name=xz-6;     command -v xz   >/dev/null && t sh -c "xz -6 -T0 -c '$f' >$tmp/out"
name=xz-9e;    command -v xz   >/dev/null && t sh -c "xz -9e -T0 -c '$f' >$tmp/out"
for mx in 5 9; do
  name=7z-mx$mx; command -v 7z >/dev/null && t sh -c "rm -f $tmp/o.7z; 7z a -bd -y -mx$mx $tmp/o.7z '$f' && mv $tmp/o.7z $tmp/out"
done
