# clove: an archiver with its own compressor, written entirely in AIL

Clove is a command-line archiver (add, extract, list, test) built on a new
compression algorithm: a bitwise context-mixing model with a long-range match
model, written only in AIL with integer arithmetic, so every machine produces the
same bytes. It is the larger program for comparing AIL with C and with 7-Zip.

```sh
./ail run clove.ail a out.clove src/ notes.txt    # add (block size with -b KB)
./ail run clove.ail l --json out.clove            # list (--json for agents)
./ail run clove.ail t out.clove                   # test: decode every block, check CRCs
./ail run clove.ail x out.clove dir               # extract
./ail run clove.ail read out.clove a.txt --range 0:4096   # part of one file, decoding only its blocks
./ail run clove.ail bench corpus.txt              # ratio, speed, round-trip check
bench.sh corpus.txt                               # native build vs gzip/xz/zstd/7z
```

## Archive format (`CLV2`)

All integers are little-endian. The whole index is at the front, so one read finds
any block of any file.

```
"CLV2" | u32 file count | u32 block count | u32 block size
per file:  u16 name length | name (UTF-8, relative, no "..") | u64 size | u32 first block | u32 block count
per block: u64 offset into the data | u32 packed length | u32 CRC32 of the raw block | u8 engine (0 stored, 1 cm)
data: the packed blocks, in order
```

Blocks (default 128 KB) are independent, so `a`, `x`, `t` and `read` work one block per
core with `par for`, and `read FILE --range A:B` decodes only the blocks it needs.

## Error rules

- `clove.usage`: a command line the tool can't act on; the message says what is missing.
- `clove.format`: the archive is not CLV2, is truncated, or a block fails its CRC.

## The codec (`cm/cm.ail`; the code is the spec)

- Models: order 0, 1, 2, 3, 4 and 6 context tables of adaptive probabilities (22-bit
  probability plus a hit count that sets the learning rate), and a match model that
  follows the longest recent repeat of the last 5 bytes and predicts its next bit.
- Mixer: logistic mixing of the models' logits; weight sets chosen by the partial byte
  and whether a match is active; online gradient learning.
- Coder: carry-less 32-bit binary arithmetic coder, 12-bit probabilities.
- Not yet: SSE/APM stages, word and sparse contexts, a second mixer layer, per-file
  type detection.
