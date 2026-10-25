#!/bin/bash
# Search layer smoke test: archive a corpus, then check `grep`, `describe`, `read` and `serve`
# against grep(1) and the files themselves.
#   tools/smoke-search.sh            AIL=/path/to/ail (default ../ail)
# Prints only failures; the last line is `SMOKE GREEN` or `SMOKE RED (N)`.
set -u
cd "$(git rev-parse --show-toplevel)"
ail="${AIL:-../ail}/ail"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/clove-smoke.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fails=0
red() { fails=$((fails+1)); echo "RED $1"; }
clove() { "$ail" run clove.ail "$@"; }

cp clove.ail README.md docs/design.md "$tmp/" 2>/dev/null
head -c 300000 /dev/urandom > "$tmp/random.bin"
cat README.md README.md docs/design.md clove.ail clove.ail clove.ail > "$tmp/long.txt"

for bs in 4 32 128; do
  a="$tmp/t$bs.clove"
  clove a -b $bs "$a" "$tmp/clove.ail" "$tmp/README.md" "$tmp/long.txt" "$tmp/random.bin" >/dev/null || red "add -b $bs"
  clove t "$a" >/dev/null || red "test -b $bs"
  for pat in "archive" "Bloom" "trigram index" "CLV2" "zzzqqq-not-there" "ar"; do
    want=$(grep -n -F "$pat" "$tmp/clove.ail" | cut -d: -f1 | tr '\n' ' ')
    got=$(clove grep --max 100000 --file "${tmp#/}/clove.ail" "$a" "$pat" | cut -d: -f2 | tr '\n' ' ')
    [ "$want" = "$got" ] || red "grep -b $bs '$pat' lines: want [$want] got [$got]"
  done
  want=$(grep -n -i -F "BLOOM" "$tmp/long.txt" | wc -l | tr -d ' ')
  got=$(clove grep -i --max 100000 --file "${tmp#/}/long.txt" "$a" "BLOOM" | wc -l | tr -d ' ')
  [ "$want" = "$got" ] || red "grep -i -b $bs count: want $want got $got"
  clove describe --json "$a" | grep -q '"trigram": true' || red "describe -b $bs has no index"
  clove grep --json "$a" "CLV2" | grep -q '"indexed": true' || red "grep --json -b $bs"
done

a="$tmp/t4.clove"
want=$(grep -c -F "needle-that-is-absent" "$tmp/long.txt")
clove grep --json "$a" "needle-that-is-absent" | grep -q '"decoded": 0' || red "an absent text should decode no block"
clove describe --json "$a" | grep -q '"kind": "binary"' || red "random.bin should be binary"
clove read "$a" "${tmp#/}/long.txt" --range 100:200 --out "$tmp/part" >/dev/null
head -c 200 "$tmp/long.txt" | tail -c 100 | cmp -s - "$tmp/part" || red "read --range"

# a match that straddles a block boundary: 4 KB blocks, the word split at 4096
{ head -c 4090 /dev/zero | tr '\0' 'x'; printf 'straddle-word'; head -c 5000 /dev/zero | tr '\0' 'y'; } > "$tmp/edge.txt"
clove a -b 4 "$tmp/edge.clove" "$tmp/edge.txt" >/dev/null || red "add edge"
clove grep "$tmp/edge.clove" "straddle-word" | grep -q "straddle-word" || red "boundary match missed"

# short queries (1 and 2 bytes) cannot use the trigram filter and must scan; UTF-8 text is matched as bytes
printf 'caf\xc3\xa9 au lait\nna\xc3\xafve\nplain\ncaf\xc3\xa9\n' > "$tmp/utf.txt"
clove a -b 4 "$tmp/utf.clove" "$tmp/utf.txt" >/dev/null || red "add utf"
for pat in "x" "ai" $'caf\xc3\xa9' $'\xc3\xaf'; do
  want=$(grep -n -F -- "$pat" "$tmp/utf.txt" | cut -d: -f1 | tr '\n' ' ')
  got=$(clove grep "$tmp/utf.clove" "$pat" | cut -d: -f2 | tr '\n' ' ')
  [ "$want" = "$got" ] || red "short or UTF-8 query '$pat': want [$want] got [$got]"
done
clove grep -i "$tmp/utf.clove" $'CAF\xc3\x89' | grep -q . && red "-i folds ASCII only: a non-ASCII byte must not match its upper case"
# -i folds ASCII across a block boundary
clove a -b 4 "$tmp/edge2.clove" "$tmp/edge.txt" >/dev/null
clove grep -i "$tmp/edge2.clove" "STRADDLE-WORD" | grep -q "straddle-word" || red "-i boundary match missed"
# binary blocks are skipped unless -a
clove grep --json "$a" "zzzqqq-not-there" | grep -q '"skipped_binary": [1-9]' || red "binary blocks should be counted as skipped"

# serve: initialize, list the tools, grep through a tool call
resp=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"clove_grep\",\"arguments\":{\"archive\":\"$a\",\"pattern\":\"CLV2\"}}}" \
  | clove serve)
echo "$resp" | grep -q '"id": 1' || red "serve initialize"
echo "$resp" | grep -q 'clove_grep' || red "serve tools/list"
echo "$resp" | grep -q '"id": 3.*"isError": false' || red "serve tools/call"

[ $fails = 0 ] && echo "SMOKE GREEN" || echo "SMOKE RED ($fails)"
[ $fails = 0 ]
