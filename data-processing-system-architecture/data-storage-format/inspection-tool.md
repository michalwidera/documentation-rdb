# Inspection Tool: `xtrdb -s`

The command `xtrdb -s <path>` displays a complete picture of an artifact's storage state — without starting the `xretractor` process, without entering interactive mode. Just point it at the base path (without extension), and the tool finds the associated files on its own: `.desc`, binary data, `.meta`, `.shadow`, cyclic segments, and rotated files.

> **_NOTE:_** The functionality described here is covered by the test: `issue153_storagemap_meta_cases`, described in the appendix [Integration Tests](../../appendices/integration-tests.md).

## Purpose and use cases

| Situation | What `xtrdb -s` gives you |
| -------- | ------------------- |
| Post-crash diagnosis | You can immediately see whether the data file is consistent with the metadata — differing record counts signal a problem |
| Retention verification | The DATA TOTAL section shows the segment breakdown and the current fill level of the circular buffer |
| Modification control | The SHADOW section reveals the number of uncommitted changes — `Updates: N` means `merge()` has not been run |
| Data-quality analysis | The META bar, with the symbols `=`, `-`, `~`, `X`, shows the null/gap pattern without parsing the binary file |
| Rotation-history audit | The ROTATED FILES section lists old versions of the file after successive rotations |

The command is **read-only** — it does not modify any file. It can also be run while `xretractor` is not running.

## What the map shows

The whole report is framed with box-drawing characters. The top part is a three-column overview map:

```
┌──────────────────────────────────────────────────────────────┐
│   Storage map: <name>                                        │
├──────────────────────────────────────────────────────────────┤
│ [shadow]   │ [binary data] │ [meta index]                    │
├────────────┼───────────────┼─────────────────────────────────┤
│ ...        │ ...           │ ...                             │
├────────────┴───────────────┴─────────────────────────────────┤
│   SECTION  ...                                                │
└──────────────────────────────────────────────────────────────┘
```

Each row of the map corresponds to one RLE segment or one data segment:

| Column | Content |
| ---- | --------- |
| `[shadow]` | For an artifact without retention: the number of unwritten modifications (`N updates`). For segmented retention: the segment label `sN` with its modification count. |
| `[binary data]` | The record-index range in the binary file (`begin-end`), or the segment label `sN begin-end`. Rows for a transmission gap have this field empty. |
| `[meta index]` | Description of the RLE segment from the `.meta` file: number of records and the null pattern in the form `[====]`. |

Below the map come further sections:

| Section | Description |
| ---- | --------- |
| `DESCRIPTOR` | Path and size of the `.desc` file, the field list with types and sizes, the record size in bytes. |
| `DATA` | Number of records, path to the data file. With retention (`RETENTION`): the segment breakdown, the policy (segment count and capacity), the maximum allowed buffer size, the list of `_segment_*` files. |
| `META` | Number of RLE segments and records in the index, a graphical bar showing the null pattern over time. |
| `SHADOW` | Path and size of the shadow file, and the number of uncommitted modifications. |
| `ROTATED FILES` | Files from previous rotations (`.old1`, `.old2`, …) with their sizes. |

### META bar legend

```
[====] — data with no null values
[----] — partial nulls (at least one field is null)
[~~~~] — all fields are null (nullfill)
[XXXX] — transmission gap
```

---

## Example 1 — a simple artifact

Stream `measurement` with two fields, 100 records, no modifications, no gaps:

```
{
  INTEGER  ts
  FLOAT    value
  TYPE     DEFAULT
}
```

```
$ xtrdb -s measurement
```

```
┌──────────────────────────────────────────────────────────────┐
│   Storage map: measurement                                   │
├──────────────────────────────────────────────────────────────┤
│ [shadow]   │ [binary data] │ [meta index]                    │
├────────────┼───────────────┼─────────────────────────────────┤
│            │ 0-100         │ [====] 100 records, no nulls    │
├────────────┴───────────────┴─────────────────────────────────┤
│   DESCRIPTOR  measurement.desc                          43 B │
│   INTEGER  ts                                            4 B │
│   FLOAT  value                                           4 B │
│   Record size:                                           8 B │
├──────────────────────────────────────────────────────────────┤
│   DATA        measurement                               800 B │
│   Records: 100                                               │
├──────────────────────────────────────────────────────────────┤
│   META        measurement.meta                           26 B │
│   Segments: 1   Records: 100                                 │
│   [==========================100===========================] │
│   Legend: [====] data  [----] partial null                   │
│           [~~~~] nullfill  [XXXX] gap                        │
├──────────────────────────────────────────────────────────────┤
│   SHADOW      measurement.shadow (missing)                0 B │
└──────────────────────────────────────────────────────────────┘
```

Interpretation: one RLE segment, no gaps, no nulls, no shadow file present. The binary file is exactly 100 × 8 = 800 bytes.

---

## Example 2 — an artifact with a transmission gap and a modification

Stream `sensor` with three fields. After 50 records there was a gap (10 interval units), then 30 records arrived with partial gaps in the `pressure` field. Two records were later modified (a shadow file is present):

```
{
  INTEGER  ts
  FLOAT    temp
  FLOAT    pressure
  TYPE     DEFAULT
}
```

```
$ xtrdb -s sensor
```

```
┌──────────────────────────────────────────────────────────────┐
│   Storage map: sensor                                        │
├──────────────────────────────────────────────────────────────┤
│ [shadow]   │ [binary data] │ [meta index]                    │
├────────────┼───────────────┼─────────────────────────────────┤
│            │ 0-50          │ [====] 50 records, no nulls     │
│            │               │ [XXXX] 10 records, gap          │
│ 2 updates  │ 50-80         │ [----] 30 records, some nulls   │
├────────────┴───────────────┴─────────────────────────────────┤
│   DESCRIPTOR  sensor.desc                                52 B │
│   INTEGER  ts                                            4 B │
│   FLOAT  temp                                            4 B │
│   FLOAT  pressure                                        4 B │
│   Record size:                                          12 B │
├──────────────────────────────────────────────────────────────┤
│   DATA        sensor                                   960 B │
│   Records: 80                                                │
├──────────────────────────────────────────────────────────────┤
│   META        sensor.meta                                60 B │
│   Segments: 3   Records: 80                                  │
│   [===========50===========][XXgap:10XX][-------30---------] │
│   Legend: [====] data  [----] partial null                   │
│           [~~~~] nullfill  [XXXX] gap                        │
├──────────────────────────────────────────────────────────────┤
│   SHADOW      sensor.shadow                              26 B │
│   Updates: 2                                                 │
└──────────────────────────────────────────────────────────────┘
```

Interpretation: the binary file contains 80 records (the gap takes no space in the data file); the gap is encoded solely in `.meta`. The `[binary data]` column shows an empty range for the gap segment — there is no binary data for it. The `pressure` field in records 50–79 has null values in some records (`[----]`). The shadow file contains 2 modifications that have not yet been merged into the main file.

---

## Example 3 — an artifact with segmented retention

Stream `buffer` with cyclic retention: up to 10 segments of 100 records each (1000 records total). Currently 280 records have been written, across three segments:

```
{
  DOUBLE   value
  TYPE     DEFAULT
  RETENTION 1000 100
}
```

```
$ xtrdb -s buffer
```

```
┌──────────────────────────────────────────────────────────────┐
│   Storage map: buffer                                        │
├──────────────────────────────────────────────────────────────┤
│ [shadow]   │ [binary data] │ [meta index]                    │
├────────────┼───────────────┼─────────────────────────────────┤
│ s0         │ s0 0-100      │ [====] 100 records, no nulls    │
│ s1         │ s1 100-200    │ [====] 100 records, no nulls    │
│ s2         │ s2 200-280    │ [====] 80 records, no nulls     │
├────────────┴───────────────┴─────────────────────────────────┤
│   DESCRIPTOR  buffer.desc                                48 B │
│   DOUBLE  value                                          8 B │
│   Record size:                                           8 B │
├──────────────────────────────────────────────────────────────┤
│   DATA TOTAL  rec=280 src=0 seg=280                   2240 B │
│   Records: 280                                               │
│   Source: buffer   Segments: buffer_segment_*                │
│   Segmented data (RETENTION): 3                              │
│   Policy: segments=10 capacity=100                            │
│   Retention cap records: 1000                                │
│   Retention cap bytes: 8000                                  │
│   Total records: 280                                         │
│     current=0  segments=280                                  │
│   Total bytes: 2240                                          │
│     current=0  segments=2240                                 │
│     [0] buffer_segment_0 rec:100 range:0-100                 │
│     [1] buffer_segment_1 rec:100 range:100-200               │
│     [2] buffer_segment_2 rec:80 range:200-280                │
├──────────────────────────────────────────────────────────────┤
│   META        buffer.meta                                26 B │
│   Segments: 1   Records: 280                                 │
│   [=========================280===========================]  │
│   Legend: [====] data  [----] partial null                   │
│           [~~~~] nullfill  [XXXX] gap                        │
├──────────────────────────────────────────────────────────────┤
│   SHADOW      buffer.shadow (missing)                     0 B │
└──────────────────────────────────────────────────────────────┘
```

Interpretation: the `[binary data]` column shows each segment with its `sN` label and its global index range. The DATA TOTAL section gives a full breakdown: `src=0` (no records outside the segments), `seg=280` (all records within segments). Once the buffer fills up (10 segments × 100 = 1000 records), the oldest segment will be deleted and a new one appended.
