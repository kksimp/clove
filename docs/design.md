# Clove design note (draft 2026-10-25)

## Status (2026-10-25)

| Part | State |
|---|---|
| CLV2 container: index at the front, independent blocks, CRC32 per block | implemented |
| Engine `fast` (LZ77 + LZMA-style range-coded model) | implemented; ratio below 7-Zip's |
| Engine `max` (context mixing: 8 hashed contexts, match model, 2 mixers, 2 SSE) | implemented; 8.7% below 7z -mx9 on enwik8 (20 MB), far slower |
| `a`, `x`, `l`, `t`, `bench`, `read --range`, `--json` on `l` and `t`, rule IDs in errors | implemented |
| Validated index parsing, path-safety rules, archive-level tests | implemented |
| `grep`, `describe`, trigram index, MCP `serve` | in progress (separate branch) |
| 4 KB-aligned blocks | planned, not built |
| Shared learned prior | planned, not built |
| Per-block automatic engine choice | planned (the engine byte exists; the writer uses `-m`) |
| Executable filters and instruction contexts; deflate-inside recompression | planned |

Everything below "The design" describes the target; the table says what exists.

Goal (Kaleb, 2026-10-25): a novel compression algorithm for modern hardware, with
AI-first features such as grep, designed SSD-first. All AIL, integer-only, so output
is identical on every machine.

## Why existing archivers fit the wrong machine

7-Zip, xz and zstd were shaped by spinning disks and one fast core: one long stream,
decode in order, an index (if any) at the end. A modern machine has an NVMe drive that
reads multi-GB/s at deep queues, 8+ cores, and an AI agent that wants "the 3 files that
mention X", not the whole archive.

## The design

1. **Independent small blocks, 4 KB aligned.** Default 128 KB raw, each block starts
   on a 4 KB boundary so reads are page and direct-I/O friendly and any block decodes
   with one read. A block index (offset, raw/packed length, CRC, flags) sits in a
   fixed-size footer *and* is repeated at the start, so a reader needs one seek.
2. **Shared learned prior.** Small blocks normally lose ratio because each starts with
   an empty model. Clove trains a compact prior (order-1/2 tables, a dictionary of the
   most useful strings, mixer weights) from a sample of the archive once, stores it in
   the header, and every block starts from it. Blocks stay independent, parallel and
   random-access, and recover most of the cross-block context a solid stream had.
3. **Two engines per block, chosen by the writer.** `fast`: LZ with a long dictionary
   from the prior plus a table-driven entropy coder, built to decode at SSD speed.
   `max`: the context-mixing engine already in `cm/`, for cold data. A flag per block
   lets one archive mix both (hot files fast, archives of logs max).
4. **Compressed-domain grep.** Each block carries a small trigram Bloom filter in the
   index. `grep` reads the index, skips blocks that cannot match, and decodes only the
   rest, all blocks in parallel. An agent can ask "which files contain X" in
   milliseconds on an archive it never extracted.
5. **Agent interface.** Every command has `--json`; errors cite a rule ID and a fix;
   `describe` prints the archive's files, types and index; `read FILE --range A:B`
   decodes only the blocks covering the range; `serve` exposes add/list/read/grep as
   MCP tools.

## What is novel

The combination: prior-primed independent blocks (solid-stream ratio with random access),
per-block engine choice, and a trigram index that makes search a compressed-domain
operation. Each part exists somewhere; the archive format that joins them for
SSD-and-agent workloads does not.

## Open choices

See the decision cards in the Clove thread: engine tiering, block size, prior training.

## Rejected

- One solid CM stream: best ratio, but 0.5 MB/s decode and no random access.
- zstd-style frame with an external dictionary file: the dictionary must travel
  separately; we embed the prior.
- A separate index file: easily lost; the index lives in the archive.

## rANS coders (opt v2 step V2a, 2026-11-09)

`rans/rans.ail` holds the two entropy coders the planned opt v2 codec needs; no archive format uses them yet.
- Static: normalised counts (total 2^12), FSE spread, one table lookup per symbol, two interleaved 32-bit states, byte-wise renormalisation.
- Adaptive: 16-symbol (nibble) tables per context, one state. The probabilities keep a total of exactly 2^16 and move 1/32 toward each coded symbol. Rejected: counts with increment 32 halved when the total passes 2^12. Byte-wise rANS renormalises exactly only when the total divides the state range, so a halved count table (an arbitrary total) cannot be coded by it; a bit-wise or range-coder fallback would give up the speed rANS is chosen for.
- Tests: round trips on random, skewed and single-symbol streams for both, and a speed test that prints MB/s on 8 MB of nibbles.
