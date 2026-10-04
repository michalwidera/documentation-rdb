# DECLARE Command

The DECLARE command is used to declare a data source.

Its syntax is described as follows:

```rql
DECLARE field type[N] [, field type[N]]
STREAM name, rate
BINFILE | TEXTFILE | DEVICE source
[TIMEOUT time]
[DISPOSABLE]
[ONESHOT]
[HOLD]
```

![DECLARE command syntax diagram](../assets/railroad-declare.svg)

_Fig. 3. DECLARE command syntax diagram_

The railroad diagram in Fig. 3 was generated from the `declare_statement` rule in the system's ANTLR4 grammar (`RQL.g4`). The diagram is read by following the lines from left to right: rounded green boxes are keywords and symbols entered literally, rectangles are values supplied by the user. A loop looping back through a comma means multiple field declarations are possible; the branch at the rate shows it can be written as a fraction (numerator/denominator) or as a single number; the branch before the source is the choice of the source kind (`BINFILE`, `TEXTFILE`, `DEVICE` or the deprecated `FILE`); the track bypassing TIMEOUT means the read deadline is optional, and its value - like the rate - is written as a fraction or a number; tracks bypassing DISPOSABLE, ONESHOT, and HOLD mean each of these directives is optional.

## Source kinds

The data format follows from the keyword, never from the name or extension of the path:

| Keyword    | What it reads                                                                                   | File kind at the path              | After the end of data                                  |
| ---------- | ----------------------------------------------------------------------------------------------- | ---------------------------------- | ------------------------------------------------------ |
| `BINFILE`  | raw binary records whose size follows from the fields                                           | regular file only                  | back to the beginning (loop), with `ONESHOT` end of source |
| `TEXTFILE` | text: values separated by whitespace, the `NULL` token marks a missing value                    | regular file only                  | as `BINFILE`                                           |
| `DEVICE`   | raw binary records from a live source; it interprets neither text nor the `NULL` token, a zero byte is zero | character device or FIFO           | no writer: `NULL` records until data comes back; with `ONESHOT` end of source |

```rql
DECLARE MLII INTEGER, V1 INTEGER STREAM ecg, 1/360 BINFILE 'rec205'
DECLARE bp_coef INTEGER[25] STREAM bpf, 1 TEXTFILE 'bp_coef.txt'
DECLARE sample BYTE STREAM sensor, 0.02 DEVICE '/dev/urandom'
```

The extension selects nothing: `BINFILE 'bytes.txt'` reads raw bytes, and `TEXTFILE 'values.dat'` parses text.

`DEVICE` is a live source, so it takes neither `DISPOSABLE` nor `HOLD` - these directives apply to replayed files (`BINFILE`, `TEXTFILE`), see [Read Options](declare-command-read-options.md). It does take `ONESHOT` and its own `TIMEOUT` clause, described in [Reading a DEVICE source and TIMEOUT](#reading-a-device-source-and-timeout). Opening a FIFO declared as `DEVICE` does not wait for a writer - the plan starts, and the writer may connect later.

The words `BINFILE`, `TEXTFILE`, `DEVICE` and `TIMEOUT` are reserved - no stream or field may be named that way (in lowercase either).

### File kind check

Before the plan starts - also on a plan reload (`xqry --reset`) and on an ad hoc import (`xqry -a`) - the system checks the kind of file at the path of every declaration, without opening it. A path of the wrong kind (a directory, a block device, a socket, a FIFO for `BINFILE`/`TEXTFILE`, a regular file for `DEVICE`) refuses the plan with the stream name and the path, e.g.:

```
xretractor: stream 'src': BINFILE 'feed.fifo' is a FIFO, not a regular file
```

A path that does not exist is not a refusal: the stream then yields `NULL` records. Whether read warnings are available depends on the build mode, as described below for `DEVICE`. Compilation with `-c` does not perform this check - it does not have to run on the machine with the data.

## Reading a DEVICE source and TIMEOUT

Reading a `DEVICE` source never waits without end and never holds up the rest of the system. The device or FIFO is opened and read without blocking, and the only waiting happens before the slot is computed, outside the data model locks. An `xqry` client therefore gets its answer also while the engine waits for device data, and the waiting time does not enter the measured slot computation time (E1).

The optional `TIMEOUT` clause gives the read deadline in seconds. The value is written the same way as the stream rate - as a fraction, a number with a point, or an integer:

```rql
DECLARE a BYTE STREAM s0, 1/50 DEVICE '/dev/sensor0'
DECLARE b BYTE STREAM s1, 1/50 DEVICE '/dev/sensor1' TIMEOUT 1/100
DECLARE c BYTE STREAM s2, 1/50 DEVICE '/dev/sensor2' TIMEOUT 0
```

| Value | Meaning |
| ----- | ------- |
| `TIMEOUT 0` | an immediate attempt: no complete record in a due slot gives a `NULL` record without waiting |
| `TIMEOUT t`, `t > 0` | one deadline for the whole record, counted from the start of the due slot; after it a `NULL` record |
| no clause | the deadline from the `timeout_s` key in the `[sources]` section of `retractor.toml`, and 0 without that key |

An explicit clause wins over the configuration - including an explicit `TIMEOUT 0`, which switches off a positive value from `retractor.toml` for a single source. A negative value is an error: there is no "wait forever" deadline. A deadline longer than a day is a plan error as well, and so is `TIMEOUT` on `BINFILE`, `TEXTFILE` and the deprecated `FILE` (on `FILE` with a hint to declare the source with an explicit `DEVICE`). The configuration key is described in [Command-line options - xretractor](../appendices/command-line-options/xretractor.md#configuration-file-toml).

Reading properties:

- **The deadline is not renewed.** A system call interrupted by a signal and a spurious wakeup do not extend the wait - the deadline is fixed from the start of the slot.
- **Several sources wait in parallel.** All `DEVICE` sources due in a slot wait together, so the slot grows by at most the largest deadline, not by their sum.
- **An incomplete record survives the deadline.** Bytes that arrived before the deadline wait in the source buffer; a record completed later goes to the next due slot. Only a record that is incomplete at the moment the writer disconnects is dropped - the record boundary is lost together with the writer, so the next writer starts a new record.
- **The moment of reading.** A `DEVICE` record consumed in slot k is read at the start of slot k, not at the end of the previous slot as for `BINFILE` and `TEXTFILE`. The logical record indices are the same: the same bytes given as `BINFILE` and through a FIFO as `DEVICE` give the same results, also behind operators that join streams of different rates.
- **End of data.** The end of data is decided only by a read returning zero bytes (a FIFO without a writer, a hung-up terminal). Without `ONESHOT` it means "there is no writer right now": the slot gets a `NULL` record, the source stays open, and a writer connecting again resumes the data. With `ONESHOT` (also in `--until-eof` mode) exhaustion is the first end of data **after** at least one byte was received - an end before the first data is a writer that has not connected yet. A writer that connects and disconnects without writing therefore does not end the run.
- **A read error** other than a momentary lack of data (e.g. an unplugged USB device) gives `NULL` records without exhausting the source. Reopening an unplugged device is not supported.
- **Mode without a clock.** In `--no-clock` (`-f`) mode the deadline of every `DEVICE` source is 0: real seconds have no conversion to virtual time. One immediate attempt in every due slot remains, so a FIFO with data written up front gives a repeatable run.

Dropped incomplete records and changes in the `DEVICE` connection state (no writer, resumed data, read error) have diagnostics at the `WARN` level. These warnings are available in the log in a `Debug` build; in `Release`, they are disabled at compile time by `SPDLOG_ACTIVE_LEVEL=SPDLOG_LEVEL_ERROR`. The absence of a warning in `Release` therefore does not confirm a successful read or complete records. Diagnostics at the `ERROR` level remain available.

The effective deadline of every `DEVICE` source and its origin (`RQL`, `config`, `default` or `no-clock`) goes to the engine log when the plan starts and on an ad hoc import, e.g. `DEVICE stream 's1': effective TIMEOUT 0.01 s (RQL)`. The `xretractor -c` listing shows an explicit clause in the same form as the rate, e.g. `timeout=1/100`.

> **⚠️ Warning** Limits of real time:
>
> * Reading without blocking does not protect against a driver that blocks inside the read call despite the non-blocking mode. Such a device needs isolation in a separate process or thread.
> * A deadline longer than the stream rate overruns the slot. Compilation then prints a warning, e.g. `DECLARE s1: TIMEOUT 0.05 s (RQL) is longer than the interval 0.02 s; waiting overruns the slot`, taking the value from `retractor.toml` into account as well.
> * Every clocked mode, with the `--realtime` option and without it, schedules slots against a fixed anchor of the time axis. Waiting for a `DEVICE` source that fits in the slot together with the computation does not shift the following slots. A longer wait delays the next slots, which are then made up without sleeping; if waiting and computation persistently exceed the period, the backlog grows - see [Slot schedule](../query-execution/query-tree-traversal-algorithm.md#slot-schedule).
> * The schedule does not synchronize the device clock. A producer persistently faster than the plan still builds a backlog in the source buffer. A persistently slower one lacks samples: this gives `NULL` records in the ticks in which a record did not arrive in time, and `TIMEOUT` can at most turn them into a delay growing together with the shortfall.

> **_NOTE:_** Reading a `DEVICE` source, `TIMEOUT` and the end of data are covered by the `device_timeout` test and by the `ut_faccbindev` unit test.

## Field types

Every field has a name and a type. Available types:

| Type      | Size | Description                        |
| --------- | ---- | ----------------------------------- |
| `BYTE`    | 1 B  | unsigned 8-bit integer               |
| `INTEGER` | 4 B  | signed 32-bit integer                |
| `UINT`    | 4 B  | unsigned 32-bit integer              |
| `FLOAT`   | 4 B  | 32-bit floating-point number         |
| `DOUBLE`  | 8 B  | 64-bit floating-point number         |
| `STRING`  | N B  | fixed-length byte string of length N |

### Field arrays (`type[N]`)

Any field can be given an array multiplier `[N]` - the field then occupies `N × type_size` bytes and creates `N` consecutive positions in the record schema:

```rql
DECLARE coef INTEGER[25] STREAM filter, 1 TEXTFILE 'coefficients.txt'
```

The field `coef INTEGER[25]` creates a record of size 25 × 4 = 100 bytes and gives access to indices `filter[0]` … `filter[24]`. This is the standard way of passing coefficient arrays (e.g. FIR filters) into the system.

Multiple fields of different types can be combined in a single record:

```rql
DECLARE id UINT, value FLOAT, name STRING[16] \
STREAM measurement, 0.1 \
BINFILE 'sensor.dat'
```

Record size: 4 + 4 + 16 = 24 bytes.

RetractorDB, running under Linux, reads and writes data to files. On Linux, access to most resources is carried out through access to various kinds of files. This approach unifies the way data is accessed.

An example of a command that creates an object in RetractorDB returning random values from the /dev/random stream 10 times per second, with values of type int, looks as follows:

```rql
DECLARE random_field INTEGER STREAM random_stream, 0.1 DEVICE '/dev/random'
```

A file declared as `TEXTFILE` is interpreted as a continuous, unbounded data file read line by line. Upon reaching the end of the file, reading resumes from the beginning. Basic support for the format is provided - if we specify two integer fields in the declaration, and the file contains two integer values separated by a space, those values will be read as consecutive elements of the record.

```rql
DECLARE field_1 INTEGER STREAM cyclic_stream, 0.1 TEXTFILE 'file.txt'
```

> **_NOTE:_** The functionality described here is covered by the test: `Pattern7`, described in the appendix [Integration Tests](../appendices/integration-tests.md).

A file declared as `BINFILE` is read as a sequence of raw records, also in a loop: after the last record has been read, the read position moves back to the beginning of the file.

The three optional directives (`ONESHOT`, `DISPOSABLE`, `HOLD`) control the lifecycle of file sources - a detailed description and comparison table can be found in the chapter [Read Options](declare-command-read-options.md).

## Deprecated `FILE` form

`DECLARE ... FILE 'path'` is still accepted for backward compatibility. The source kind is then chosen by a fixed rule from the path - the same rule the system applied before the explicit keywords existed. The rows of the table are checked in order:

| Path in `FILE`                                                                         | Kind after translation |
| -------------------------------------------------------------------------------------- | ---------------------- |
| contains `.txt` anywhere, regardless of case (`data.txt`, `X.TXT`, `/x.txt.d/rec`)     | `TEXTFILE`             |
| starts with `/dev/`                                                                    | `DEVICE`               |
| any other                                                                              | `BINFILE`              |

After translation the rules of the chosen kind apply, including the file kind check. A `FILE` pointing at a FIFO outside `/dev` is refused with a hint of the right keyword:

```
xretractor: stream 'src': BINFILE 'feed.fifo' is a FIFO, not a regular file (deprecated FILE resolved this path as BINFILE; declare it with DEVICE)
```

A `FILE` declaration resolved as `DEVICE` gets the whole `DEVICE` reading described above and takes `ONESHOT`, but not `DISPOSABLE`, `HOLD` or `TIMEOUT` - its deadline comes only from `[sources] timeout_s` or is 0. New plans should use the explicit keywords - the `FILE` form will be removed from the language in the future. `FILE` in the `SELECT` command still only names the result file and is not a deprecated form.

The warning about the deprecated form is silent by default, so existing plans do not change the program output. With `--verbose` (`-v`) `xretractor` prints one warning per declaration to stderr - at startup and in `-c` mode:

```
xretractor: warning: line 3: DECLARE core: FILE 'data.txt' is deprecated, resolved as TEXTFILE
```

On an ad hoc import (`xqry -a`) and on a plan reload (`xqry --reset`) the server's `--verbose` decides, and the warning goes to the server's stderr.

## Source descriptor

The system writes the descriptor of every declaration in the storage directory as `<stream_name>.desc`: the fields, the path (`REF`) and the type (`TYPE BINFILE`, `TYPE TEXTSOURCE` or `TYPE DEVICE`). The descriptor stays between runs and on the next start it must match the plan also in type and path. Changing the source kind or the path while the descriptor is kept refuses the plan with the stream name:

```
xretractor: stream 'src': temp/src.desc was written for source 'v.txt' and the plan reads 'w.txt'; remove temp/src.desc to start the stream afresh
```

The exception is a descriptor written by earlier versions of the system for a regular binary file: it had `TYPE DEVICE`. If apart from the type it matches the plan, the start replaces it with a descriptor carrying `TYPE BINFILE`.

> **_NOTE:_** Source kinds, the file kind check, the deprecated form and the descriptor are covered by the test `source_kinds`.

> **ℹ️ Info**
>
> Support for NULL values (per field) is implemented in RetractorDB. Null metadata is stored in the `.meta` file alongside the binary data, managed by the `metaData` class.
