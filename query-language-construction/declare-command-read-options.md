# DECLARE Read Options

The `DECLARE` command accepts three optional directives that affect how a declared file source is read and its lifecycle:

```rql
DECLARE field type STREAM name, rate BINFILE | TEXTFILE source
    [DISPOSABLE]
    [ONESHOT]
    [HOLD]
```

The directives are independent and can be combined freely. They apply only to replayed files (`BINFILE`, `TEXTFILE`). The live source `DEVICE` takes none of them - see the [matrix](#options-and-source-kinds-matrix) at the end of the chapter.

## ONESHOT

Without `ONESHOT`, a file is read in an infinite loop - once the end of the file is reached, the read position returns to the beginning. `ONESHOT` disables the loop: the file is read exactly once, and once exhausted the stream returns records with every field marked `NULL`. The record bytes are zeroed, but the null markers distinguish missing data from a numeric zero. Exhausting the file neither ends the process nor deletes the file.

```rql
DECLARE measurement INTEGER STREAM burst, 0.1 BINFILE 'data.dat' ONESHOT
```

Use case: one-off loading of historical data into the system.

The `--until-eof` (`-u`) option of `xretractor` reads all files as if every declaration carried `ONESHOT`, and stops processing once the first of them is exhausted.

## DISPOSABLE

When the source's storage is closed - at the end of the process or when the plan is replaced - the system deletes the input file named in the declaration itself, the stream descriptor (`.desc`) and the metadata files (`.meta`, `.meta.shadow`), if they exist. The deletion depends neither on the end of the data nor on `ONESHOT`: a file read in a loop is deleted at closing as well, even if it was not read to the end.

```rql
DECLARE temp INTEGER STREAM one_time, 0.1 BINFILE 'temp.dat' DISPOSABLE ONESHOT
```

The combination `DISPOSABLE ONESHOT` is useful for temporary one-off input, but it is not required.

## HOLD

The file is opened when the plan starts, but physical data reading is held until the first request for this stream's data - fetching data by a query or preparing a record for a client (e.g. an Ad Hoc query). Merely listing the plan does not release the hold. Until the stream is queried, the system shows zero values for it; the first record of the file is read in the next step after the release. The hold is one-off - it does not return when the consumers go away.

```rql
DECLARE sparse INTEGER STREAM optional_stream, 1.0 BINFILE 'sparse.dat' HOLD
```

Use case: keeping the start of a recording until it is first needed, e.g. on user request via `xqry`. The combination `ONESHOT HOLD` replays the file once, from the moment of the first request.

## Comparison table

| Directive     | Read loop | Deletes files at closing | Delayed read start |
| ------------- | :-------: | :----------------------: | :-----------------: |
| _(default)_   | yes       | no                       | no                   |
| `ONESHOT`     | no        | no                       | no                   |
| `DISPOSABLE`  | yes       | yes                      | no                   |
| `HOLD`        | yes       | no                       | yes                  |

## Options and source kinds matrix

| Option       | `BINFILE` | `TEXTFILE` | `DEVICE` |
| ------------ | :-------: | :--------: | :------: |
| `ONESHOT`    | yes       | yes        | no       |
| `DISPOSABLE` | yes       | yes        | no       |
| `HOLD`       | yes       | yes        | no       |

`DEVICE` with any of these directives is a compile error naming the stream and the option, e.g. `DECLARE s: DEVICE does not take HOLD`. The reasons: a live source has no beginning to return to; holding the reads does not stop the producer, it only builds up a backlog; and `DISPOSABLE` would delete the path of the device or FIFO, whose lifecycle does not belong to the reader.

The deprecated `FILE` form resolved as `DEVICE` (a `/dev/...` path) refuses `DISPOSABLE` and `HOLD`, and accepts `ONESHOT` unchanged - see [Deprecated FILE form](declare-command.md#deprecated-file-form).
