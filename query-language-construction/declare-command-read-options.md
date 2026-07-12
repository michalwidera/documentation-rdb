# DECLARE Read Options

The `DECLARE` command accepts three optional directives that affect how the declared source is read and its lifecycle:

```
DECLARE field type STREAM name, rate FILE source
    [DISPOSABLE]
    [ONESHOT]
    [HOLD]
```

## ONESHOT

Without `ONESHOT`, a data source is read in an infinite loop — once the end of the file is reached, the read position returns to the beginning. `ONESHOT` disables the loop: the file is read exactly once, and once exhausted the stream returns zero or empty values.

```
DECLARE measurement INTEGER STREAM burst, 0.1 FILE 'data.dat' ONESHOT
```

Use case: one-off loading of historical data into the system.

## DISPOSABLE

Once data transfer from the source finishes, the system deletes the data file, the descriptor file (`.desc`), and the metadata file (`.meta`). The directive acts on destruction of the `storage` object.

```
DECLARE temp INTEGER STREAM one_time, 0.1 FILE 'temp.dat' ONESHOT DISPOSABLE
```

`DISPOSABLE` is used together with `ONESHOT` — data is read once, then deleted after reading. This combination is useful for temporary input data files.

## HOLD

The declared source does not start reading immediately after the system starts. Physical data reading begins only when the first query requiring data from this stream arrives (e.g. an Ad Hoc query). Until the stream is queried, the system shows zero or empty values for it.

```
DECLARE sparse INTEGER STREAM optional_stream, 1.0 FILE 'sparse.dat' HOLD
```

Use case: data sources activated conditionally, e.g. on user request via `xqry`.

## Comparison table

| Directive     | Read loop | Deletes files after reading | Delayed read start |
| ------------- | :-------: | :--------------------------: | :-----------------: |
| _(default)_   | yes       | no                            | no                   |
| `ONESHOT`     | no        | no                            | no                   |
| `DISPOSABLE`  | yes       | yes                           | no                   |
| `HOLD`        | yes       | no                            | yes                  |
