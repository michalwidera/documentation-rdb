# Underscore Symbol Processing

The `[_]` index is syntactic sugar that replicates a field expression. One expression written in `SELECT` expands during compilation into multiple output fields, one for each compatible slot of the referenced streams.

The number of copies is not determined solely by a stream's own schema. `x[_]` denotes all slots that `x` contributes to the record produced by the query's complete `FROM` clause. This distinction matters when a stream operator changes the schema width, for example by creating a window.

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

## Width computed from the `FROM` clause

The one-field stream `src` contributes five slots when its window `src@(1,5)` appears in `FROM`. An FIR convolution can therefore be written without a separate named window stream:

```rql
DECLARE value INTEGER STREAM src, 1/500 FILE 'data.txt'
DECLARE coef INTEGER[5] STREAM filter, 1 FILE 'coef.txt'

SELECT src[_] * filter[_] STREAM products FROM src@(1,5)+filter
SELECT products[0] STREAM output FROM SUMC(products)
```

The first query expands into five products. It is equivalent to the longer form:

```rql
SELECT * STREAM window FROM src@(1,5)
SELECT window[_] * filter[_] STREAM products FROM window+filter
SELECT products[0] STREAM output FROM SUMC(products)
```

In the shorter form, the compiler extracts the window from `FROM` as a substrate. Such a compiler-generated substrate is transparent when determining the width contributed by `src`. A user-named stream such as `window`, however, is a schema boundary, so the longer form refers to `window[_]`, not `src[_]`.

An operator in `FROM` can also reduce the width. A reducer collapses a window to one slot, so the following `src[_]` expands only once:

```rql
SELECT src[_] STREAM total FROM SUMC(src@(1,5))
```

If one expression contains several `[_]` indices, the compiler creates as many copies as the smallest determined width of their contributions. In a typical convolution, the window and the coefficient stream have the same width.

The compiler rejects a reference when the named stream does not occur in `FROM`, or when its fields do not form a contiguous block there. The latter occurs, for example, for `src[_]` under a window built over the concatenation `(src+other)@(1,5)`: fields from both sources are repeated together, so no single width can be assigned to `src` without guessing. Name the subexpression in a separate query and apply `[_]` to that named result instead.

## The `_` symbol and interleave

Component aliases such as `A[_]` are valid for sum `+`, because sum preserves separate schema segments for both arguments. Do not use this form for a component reached through interleave `#`:

```
SELECT A[_] - B[_] STREAM difference FROM A#B
```

After interleaving, positions `A[k]` and `B[k]` are the same position in the shared schema, so this expression does not identify two different values. The compiler rejects the plan instead of silently calculating `result[k]-result[k]`.

To process an interleaved record with `_`, name the interleave first and then refer to that result:

```
SELECT * STREAM interleaved FROM A#B
SELECT interleaved[_] * 2 STREAM scaled FROM interleaved
```

Recovering a particular component requires the de-interleave operator `&` or `%`.

This functionality is mainly used in signal-filter algorithms that apply the same operations to corresponding elements of a window and a coefficient vector. It is not required to access RetractorDB's complete functionality, but it makes such queries significantly shorter. See [Signal Filter Implementation](../usage-examples/signal-filter-implementation.md) for a complete example.
