# Clove design note (draft 2026-10-25)

## Status (2026-11-08)

| Part | State |
|---|---|
| CLV3 container: index at the front, one solid stream, independent blocks, CRC32 per block, per-entry kind, mode, time and newline counts | on branch `solid` (job CLOVE24) |
| Engine `fast` (LZ77 + canonical Huffman, byte-aligned bit stream, 12-bit tables) | on branch `fast-engine` (job CLOVE25) |
| Engine `lz` / `opt` (LZ77 + LZMA-style range coder; `opt` parses optimally with a binary tree) | implemented; `opt` ties 7z -mx9 on text, beats it on executables |
| Engine `max` (context mixing: 8 hashed contexts, match model, 2 mixers, 2 SSE, instruction contexts for executables) | implemented; 8-30% smaller than xz -9e; about 0.7 MB/s on 3 cores |
| Incompressible blocks stored without coding (`probe/`) | on branch `store-probe` (job CLOVE23) |
| `a`, `x`, `l`, `t`, `read --range`, `grep` with the trigram trailer, `describe`, MCP `serve`, `bench`, `--json`, rule IDs in errors | implemented |
| Streamed add and extract (one batch of blocks in memory) | on branch `solid` |
| `x --in-place`, modes, times and links restored | on branch `attrs`; waits for AIL ADR 0977 (`std.fs` attribute calls) and a new pin |
| Executable filters (x86-64, ARM64 branch targets) | implemented |
| Deflate-inside recompression; shared learned prior; per-block automatic engine choice | planned |

## In-place extraction (Kaleb, 2026-11-07)

A zip or 7z archive must stay whole until the last file is out: its directory is at the
end and its streams decode front to back, so extracting needs the archive plus the whole
output on disk. Clove's index is at the front and every block is independent, so
`x --in-place` decodes from the **last** block backwards: each block's bytes go to the
files they belong to at their own offsets (`fs.write_at`; a file touched first by its tail
is created at full length, sparse where the file system allows), then the archive is cut
to the start of that block (`fs.truncate`). The space needed beyond the output is one
block (1-4 MB) plus the index. A stopped run leaves a shorter archive whose index still
describes every block; running again extracts the blocks it still holds and the files
written earlier are untouched where they were already right.

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
