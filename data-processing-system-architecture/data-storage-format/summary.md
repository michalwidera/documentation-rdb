# Summary: Rationale for the Chosen Structure

This chapter draws together the conclusions from every part of the data-storage-format documentation and explains why the adopted file structure is minimal and sufficient for a real-time time-series recording system.

## The file set and accessor types

Every artifact or substrate consists of up to five files — the binary data file, the `.desc` descriptor, the `.meta` index, the `.shadow` data shadow, and the `.meta.shadow` index shadow. The last two form a pair: the data shadow preserves the originally recorded content, and the index shadow preserves the null patterns that go with it, so correcting a record does not desynchronize data from metadata. The `TYPE` field in the descriptor selects the `FileInterface` implementation: `DEFAULT` (data + shadow + retention), `MEMORY` (RAM only, ephemerides), `DEVICE` / `TEXTSOURCE` (read-only external sources), and intermediate variants. The accessor is chosen once, when `storage` is initialized — the RQL query logic knows nothing about storage details.

## Artifact files

**The descriptor (`.desc`)** defines the record schema in ANTLR4 grammar: field names, types (`BYTE`, `INTEGER`, `FLOAT`, `DOUBLE`, `RATIONAL`, `STRING`), array sizes, retention policy (`RETENTION`, `RETMEMORY`), and accessor type (`TYPE`). The record size `R` is the sum, in bytes, of all data fields — the meta-descriptor's own fields take no space in the record. Having the descriptor alongside the data means self-description: the `xtrdb` tool, or any code, can interpret an artifact without access to the source code.

**The binary data file** is a flat sequence of fixed-length `R`-byte records with no header. Record `i` always sits at offset `i × R`. An `append` operation writes to the end; an `update` operation — when a `.shadow` file is present — goes to the shadow file, rather than overwriting the main file.

**The metadata file (`.meta`)** stores a compressed RLE index of null values and transmission gaps. Each RLE entry describes a run of consecutive records sharing an identical null pattern: an `isGap` flag, a `recordCount`, the bitset size, and the bitset itself. A transmission gap (`gap`) exists only in `.meta` — the binary file does not record it and stays dense. The managing class is `rdb::metaData`: it buffers the current segment in `currentEntry_`, writes a segment to disk only when the pattern changes, and the `DiskTailState` state (lazy overwrite of the last on-disk entry) ensures the file size does not grow under continuous, uniform data arrival. After a restart, `loadIndex()` restores the state and brings the last non-gap segment back into memory, allowing the RLE run to continue. The file I/O itself is handled by `MetaIndexStore`, and gap detection by `GapDetector`.

**The shadow file (`.shadow`)** collects record modifications as a sequence of `(position, data)` entries. Reading a record checks `.shadow` from the end (the most recent modification wins); if there's no entry, it reads from the main file. Deleting `.shadow` fully restores the original state. The `merge()` operation writes the corrections back into the main file and clears the shadow file.

**The index shadow file (`.meta.shadow`)** is the counterpart of `.shadow` at the null-pattern level. It appears for stores that maintain a data shadow: the `makeMetaIndex()` factory then injects a `storageShadow` object into `storage` instead of the base `metaData`, and that object routes updates to its `metaShadow` member. Without this file, correcting a record would change its null pattern in `.meta` even though the original content still sits untouched in the main file — the "data ↔ metadata" pair would drift apart on the first `merge()` or shadow discard.

## The rotation mechanism

The `ROTATION rdb_counter` directive turns on session-history preservation mode. `PersistentCounter` stores a monotonically increasing session number `N`. Rotation is a process spread out over time: at the **start** of session N, `detectStartupState()` detects an inconsistency (data file empty, `.meta` non-empty) and renames `.meta` to `.meta.oldN`; at session **shutdown**, the `posixBinaryFile` destructor renames the data file to `.oldN` and the shadow file to `.shadow.oldN`. As a consequence of this ordering there is an offset of 1: `.meta.oldN` contains the metadata for session `N−1`, while `.oldN` contains the data for session `N`. Without the `ROTATION` directive, artifact files are deleted on every startup.

## The inspection tool `xtrdb -s`

The command `xtrdb -s <path>` is the only tool for inspecting storage state without starting `xretractor`. The report consists of an overview map (columns: shadow, binary data, meta index) and detailed sections: `DESCRIPTOR`, `DATA` (or `DATA TOTAL` for segmented retention), `META` with an RLE bar, `SHADOW` with the count of uncommitted modifications, and `ROTATED FILES` with the rotation history. The META bar uses four symbols: `=` (data, no nulls), `-` (partial nulls), `~` (nullfill), `X` (gap). The tool is read-only and works while the `xretractor` process is not running.

---

## Comparison of approaches

| Property  | Raw binary file | RetractorDB structure |
| ----------- | ------------------- | --------------------- |
| Self-description | none — requires external documentation | yes — the `.desc` descriptor travels with the data |
| Transmission-gap handling | none — gaps are invisible or represented by fake records | yes — `.meta` records gaps without extending the data file |
| Per-field null values | none — zero and null are indistinguishable | yes — a null bitset in `.meta` |
| Correction of historical data | destructive | non-destructive — `.shadow` |
| Restoring the original after a correction | impossible | yes — delete `.shadow` |
| Multiple storage strategies | none | yes — the `TYPE` field in the descriptor |
| Cost for gap-free, null-free data | — | minimal: `.meta` ≈ a 17 B header + 1 RLE entry |
