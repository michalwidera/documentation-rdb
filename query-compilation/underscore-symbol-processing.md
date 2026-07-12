# Underscore Symbol Processing

In some queries you can use the underscore symbol. This technique is syntactic sugar. Similarly to expanding the `*` symbol, a single reference results, after compilation, in many fields appearing. How many of these fields are produced depends on what was joined with what, and in what order, in the FROM clause.

The example uses the canonical declarations used throughout the chapter — `core0` has two fields (BYTE, INTEGER), `core1` has two fields (INTEGER, FLOAT), the schemas have equal cardinality:

```
DECLARE a BYTE, b INTEGER   STREAM core0, 0.1 FILE 'sensor_a.txt'
DECLARE c INTEGER, d FLOAT  STREAM core1, 0.2 FILE 'sensor_b.txt'

SELECT core0[_] * core1[_] \
STREAM scaled \
FROM core0 + core1
```

After compiling:

```
$ xretractor -c query.rql
scaled(1/10)
        :- PUSH_STREAM(core0)
        :- PUSH_STREAM(core1)
        :- STREAM_ADD
        scaled_0: INTEGER
                PUSH_ID(scaled[0])
                PUSH_ID(scaled[2])
                MULTIPLY
        scaled_1: FLOAT
                PUSH_ID(scaled[1])
                PUSH_ID(scaled[3])
                MULTIPLY
core0(1/10)     sensor_a.txt
        a: BYTE
        b: INTEGER
core1(1/5)      sensor_b.txt
        c: INTEGER
        d: FLOAT
```

The `_` symbol expanded into two fields: `scaled[0] * scaled[2]` (i.e. `a * c`) and `scaled[1] * scaled[3]` (i.e. `b * d`). References to `core0` and `core1` were translated, via aliasing, into absolute positions in the combined schema. The resulting types are INTEGER (`BYTE * INTEGER`) and FLOAT (`INTEGER * FLOAT`) — the result of type promotion, described in a separate subchapter.

Once the `_` operator appears in a formula's array index, the compiler repeats the formula for every field of the arguments. The schemas of both arguments must have equal cardinality — that is, core0 and core1 must have schemas of the same size, and the types will be promoted to the highest one. I'll cover type promotion shortly.

This functionality is mainly used when building queries that implement signal-filter algorithms. There, a series of mathematical operations comes into play. The functionality behind underscore-symbol processing is not required to achieve RetractorDB's full functionality. However, it significantly simplifies building specific queries where operations on two schemas need to be combined. An example use case will be presented when signal-processing algorithms are introduced.
