# Asterisk Expansion

Everyone who has written SQL knows the magic `*` character in that language. Invoking a SELECT command with this argument expands the argument list based on the schemas of the tables produced by relational joins. I wanted to achieve something similar in RQL.

The example uses the canonical declarations used throughout the chapter:

```
DECLARE a BYTE, b INTEGER \
STREAM core0, 0.1 \
FILE 'sensor_a.txt'

DECLARE c INTEGER, d FLOAT \
STREAM core1, 0.2 \
FILE 'sensor_b.txt'

SELECT * \
STREAM merged \
FROM core0 + core1

SELECT merged[2] \
STREAM result \
FROM merged
```

Let's compile it and see the effect:

```
$ xretractor -c query.rql
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
        result_0: INTEGER
                PUSH_ID(result[2])
core0(1/10)     sensor_a.txt
        a: BYTE
        b: INTEGER
core1(1/5)      sensor_b.txt
        c: INTEGER
        d: FLOAT
```

The `*` symbol turned into four fields: `core0_0`, `core0_1`, `core1_2`, `core1_3`. Naming convention: source stream name + absolute position in the output schema. Field types determine the order — `core0` contributes BYTE and INTEGER at positions 0 and 1, `core1` contributes INTEGER and FLOAT at positions 2 and 3. Referring to `merged[2]` in the `result` query gets us a field of type INTEGER — third in order, the first field from `core1`.

> **_NOTE:_** The functionality described here is covered by the test: `Pattern3`, described in the appendix [Integration Tests](../appendices/integration-tests.md).
