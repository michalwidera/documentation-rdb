# Compilation Debugging

The compiler transforms an `.rql` file into an execution plan through several stages. The effect of each stage is visible through `xretractor`'s diagnostic flags. The tools described here let you answer questions like: why does the schema look different from what I wrote? where does this delta come from? why did a substrate appear?

## The basic tool: the `-c` flag

The `-c` (`--onlycompile`) flag stops `xretractor` after compilation and prints the compiled plan to standard output — without starting processing:

```bash
xretractor -c query.rql
```

An exit code of `0` means success. Code `1` means a compilation error. Error messages go to stderr:

```bash
xretractor -c query.rql 2>errors.txt
echo $?
```

Compilation can be invoked even while another `xretractor` process is already running — the `-c` flag does not attempt to acquire the execution lock.

## How to read the compilation plan

For the canonical `query.rql` from this chapter, the plan looks as follows:

```
merged(1/10)
        :- PUSH_STREAM(core0)
        :- PUSH_STREAM(core1)
        :- STREAM_ADD
        core0_0: BYTE
                PUSH_ID(merged[0])
        core0_1: INTEGER
                PUSH_ID(merged[1])
        core1_2: INTEGER
                PUSH_ID(merged[2])
        core1_3: FLOAT
                PUSH_ID(merged[3])
result(1/10)
        :- PUSH_STREAM(merged)
        result_0: BYTE
                PUSH_ID(merged[0])
        result_1: INTEGER
                PUSH_ID(merged[2])
        result_2: BYTE
                PUSH_ID(merged[0])
        result_3: INTEGER
                PUSH_ID(merged[2])
core0(1/10)     sensor_a.txt
        a: BYTE
        b: INTEGER
core1(1/5)      sensor_b.txt
        c: INTEGER
        d: FLOAT
core2(3/10)     sensor_c.txt
        e: INTEGER
```

Every block has a fixed format:

```
streamName(delta)
        :- streamOperation(arg)
        outputFieldName: TYPE
                instruction
                ...
```

| Element | Meaning |
|---------|-----------|
| `streamName(delta)` | The stream's name and its interval as a fraction: `1/10` = 0.1 s = 10 Hz |
| `:- PUSH_STREAM(x)` | Pushes stream `x` onto the stream stack; appears once per FROM argument |
| `:- STREAM_ADD` | The stream-sum operator (`+` in FROM) |
| `:- STREAM_HASH` | The stream-synchronization operator (`#` in FROM) |
| `:- STREAM_TIMEMOVE(n)` | Time shift (`>n` in FROM) |
| `field: TYPE` | An output-schema field, after type promotion |
| `PUSH_ID(s[n])` | Pushes the value of field `n` from stream `s` onto the stack — the effect of aliasing is visible here |
| `PUSH_VAL(x)` | Pushes the constant `x` onto the stack |
| `ADD`, `MULTIPLY`, ... | An arithmetic operation: pops two arguments off the stack, pushes the result |

Ephemeris blocks (`DECLARE`) appear at the end of the plan — they contain the field list and the path to the data file.

**Aliasing in the plan**: if two output fields point to the same `PUSH_ID`, they are aliases. In the example, `result_0` and `result_2` are both `PUSH_ID(merged[0])` — confirmation that `merged[0]` and `core0[0]` are the same position. See [Aliasing](aliasing.md).

**Substrates in the plan**: an automatically generated substrate appears as a block with a name like `STREAM_HASH_core0_core1` — with no corresponding `SELECT` in the source file. See [Substrates](substrates.md).

## Visualizing the dependency graph

Instead of text, you can generate a graph in DOT format and process it with `graphviz`:

```bash
xretractor -c -d -f -s query.rql > out.dot && dot -Tsvg out.dot -o out.svg
```

Available flags that modify the DOT output:

| Flag | Full name       | Meaning |
|-------|-----------------|-----------|
| `-d`  | `--dot`         | generate DOT output instead of a text plan |
| `-f`  | `--fields`      | show stream fields in the graph nodes |
| `-s`  | `--streamprogs` | show stack-instruction sequences in the nodes |
| `-u`  | `--rules`       | show RULE rules |
| `-p`  | `--transparent` | transparent background — for embedding in documents |

The graph shows dependencies between streams as edges directed from sources to results. Substrates have a different color than streams explicitly defined by the user. See [Dependency Tree Construction](dependency-tree-construction.md).

> **_NOTE:_** The functionality described here is covered by the test: `issue31_doc`, described in the appendix [Integration Tests](../appendices/integration-tests.md).

## Verifying intervals

If an output stream's delta is unexpected:

1. Check the source streams' deltas — visible in the DECLARE blocks at the end of the plan.
2. Check the operator in the FROM clause — every operator has a different delta equation.

Example: `core0(1/10) # core1(1/5)` gives a delta of `1/15` (the harmonic mean), not `1/10`. If you expected `1/10`, use `+` instead of `#`. Full equations — see [Interval Resolution](interval-resolution.md).

## Common compilation errors

### A cycle in the dependency graph

```
[error] Circular dependency: stream interval resolution stalled with N
>> unresolved streams
```

A stream refers, directly or indirectly, to itself. Generate the graph via `-d` — the cycle will be visible as a loop. See [Loop Detection](loop-detection.md).

### Unknown stream

A reference to a stream that hasn't been declared yet. `.rql` files are processed sequentially — a `SELECT` cannot refer to a stream defined further down in the file. Move the `DECLARE` or `SELECT` earlier.

### Schema cardinality mismatch with `_`

Both streams in the expression `core0[_] * core1[_]` must have schemas of the same cardinality. Check how many fields each argument has in the plan's DECLARE blocks. See [Underscore Symbol Processing](underscore-symbol-processing.md).

### Data file unavailable

This error **does not appear with `-c`** — the flag verifies the query's correctness, it does not check whether the data files exist. The file-access error only appears when processing is started without `-c`.
