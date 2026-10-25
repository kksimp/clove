# clove: an archiver with its own compressor, written entirely in AIL

Clove is a command-line archiver (add, extract, list, test) built on a new
compression algorithm: a bitwise context-mixing model with a long-range match
model, written only in AIL with integer arithmetic, so every machine produces the
same bytes. It is the larger program for comparing AIL with C and with 7-Zip.

```sh
./ail run clove.ail a out.clove src/ notes.txt    # add (block size with -b KB)
./ail run clove.ail l out.clove                   # list
./ail run clove.ail t out.clove                   # test: decode every block, check CRCs
./ail run clove.ail x out.clove dir               # extract
./ail run clove.ail bench corpus.txt              # ratio, speed, round-trip check
bench.sh corpus.txt                               # native build vs gzip/xz/zstd/7z
```

## Archive format (`CLV1`)

All integers are little-endian.

```
"CLV1"
entry*  until end of file:
  u16 name length | name (UTF-8, relative, no "..", no leading "/")
  u64 size | u32 block size | u32 block count
  per block: u32 compressed length | u32 CRC32 of the raw block
  the blocks' bytes, in order
```

A block whose compressed length equals its raw length is stored raw. Blocks are
independent (default 4 MB), so compression, decoding and testing run one block per
core with `par for`.

## The codec (`cm/cm.ail`; the code is the spec)

- Models: order 0, 1, 2, 3, 4 and 6 context tables of adaptive probabilities (22-bit
  probability plus a hit count that sets the learning rate), and a match model that
  follows the longest recent repeat of the last 5 bytes and predicts its next bit.
- Mixer: logistic mixing of the models' logits; weight sets chosen by the partial byte
  and whether a match is active; online gradient learning.
- Coder: carry-less 32-bit binary arithmetic coder, 12-bit probabilities.
- Not yet: SSE/APM stages, word and sparse contexts, a second mixer layer, per-file
  type detection.
