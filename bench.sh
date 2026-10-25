#!/bin/bash
# Clove (native AIL build) against the usual tools, on one file.
#   bench.sh FILE     from the repository root
# Builds clove.ail natively (./ail build), then times gzip, xz, zstd and 7z where installed.
set -eu
f=${1:?usage: bench.sh FILE}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$(git rev-parse --show-toplevel)"
./ail build clove.ail -o "$tmp/clove" >/dev/null
echo "== clove (AIL, native) =="; "$tmp/clove" bench "$f"
size=$(wc -c <"$f")
t() { # name, command writing the compressed file to $tmp/out
  local s e
  s=$(date +%s%N); "$@" >/dev/null 2>&1 || return 0; e=$(date +%s%N)
  printf '%-10s %12d bytes  ratio %.3f  %6d ms\n' "$name" "$(wc -c <"$tmp/out")" \
    "$(echo "$size / $(wc -c <"$tmp/out")" | bc -l)" $(((e - s) / 1000000))
}
echo "== tools (single file, their own defaults) =="
name=gzip-6;  command -v gzip >/dev/null && t sh -c "gzip -6 -c '$f' >$tmp/out"
name=xz-6;    command -v xz   >/dev/null && t sh -c "xz -6 -T0 -c '$f' >$tmp/out"
name=zstd-9;  command -v zstd >/dev/null && t sh -c "zstd -9 -T0 -q -c '$f' >$tmp/out"
name=7z;      command -v 7z   >/dev/null && t sh -c "rm -f $tmp/out; 7z a -bd -y $tmp/out.7z '$f' && mv $tmp/out.7z $tmp/out"
