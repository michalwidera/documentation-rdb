# Interval Resolution

Every stream in RetractorDB has an assigned time interval — delta (Δ). The interval determines how often new values are produced. For declared streams (`DECLARE`), the interval is given by the user. For output streams (`SELECT`), the interval is determined by the compiler from the stream-algebra equations.

The examples in this chapter use the canonical declarations from the whole chapter: `core0` (Δ=1/10), `core1` (Δ=1/5), `core2` (Δ=3/10).

## Algorithm

The `resolveStreamIntervals` stage works iteratively:

```
prevUnresolved = ∞
loop:
    unresolvedCount = 0
    sort qTree topologically
    for every query:
        if the source streams' deltas are known:
            determine the output delta from the operator's equation
        otherwise:
            unresolvedCount++
    if unresolvedCount == 0: done (success)
    if unresolvedCount >= prevUnresolved: error (loop in the graph)
    prevUnresolved = unresolvedCount
```

Every round resolves at least one stream — because the graph is acyclic, and the topological sort guarantees sources are processed before outputs. If the number of unresolved streams stops decreasing, that indicates a cycle — see [Loop Detection](loop-detection.md).

## Operator equations

### Stream sum (`+`, STREAM\_ADD)

```
SELECT ... STREAM c FROM a + b
```

\\[\Delta_c = \min(\Delta_a, \Delta_b)\\]

The output stream produces values as often as the faster of the input streams.

Example: core0(Δ=1/10) + core1(Δ=1/5) → str1(Δ=1/10)

### Stream synchronization (`#`, STREAM\_HASH)

```
SELECT ... STREAM c FROM a # b
```

\\[\Delta_c = \frac{\Delta_a \cdot \Delta_b}{\Delta_a + \Delta_b}\\]

The result corresponds to the harmonic mean of the intervals — the stream only produces a value when both inputs are available at the same time.

Example: core0(Δ=1/10) # core1(Δ=1/5) → str1(Δ=1/15)

### Time shift (`>n`, STREAM\_TIMEMOVE)

```
SELECT ... STREAM c FROM a > n
```

\\[\Delta_c = \Delta_a\\]

A shift changes neither the stream's rate nor its emitted record sequence, but it
does change the index at which that sequence appears: record `m` carries the
content of record `m-n`. It is a causal delay, but its carrier is the **logical
origin**, not the tail — records with an index below `n` have no definition. The
operator's own tail is non-positive: it equals `max(0, W_src − n)`, because
record `m-n` is older than the current one and therefore all the more available.
The plan listing shows both quantities as `origin=` and `tail=`; the silent slots
are their sum and the runtime emits nothing in them.

Source history requires `n+1` records for the read range itself, plus two more
for a declared source's head lead (the record armed when the storage is opened
and the zero prefetch), which logical-index addressing does not shorten.

### Window aggregates (`.max`, `.min`, `.avg`, `.sum`)

\\[\Delta_c = \Delta_a\\]

Aggregates reduce values within a window, but the output stream's interval stays the same as the source's.

### The AGSE algorithm (`@(step, window)`, STREAM\_AGSE)

```
SELECT ... STREAM c FROM a @ (step, window)
```

\\[\Delta_c = \frac{\Delta_a \cdot \text{step}}{\text{windowSize}}\\]

AGSE (the Episode Series Generation Algorithm) generates sliding windows. The output interval depends on the step and the window size relative to the source.

### De-hash operators (STREAM\_DEHASH\_DIV, STREAM\_DEHASH\_MOD)

The inverse operations of `#` — they determine what interval one of the input streams had, given the result's interval and the other argument:

\\[\Delta_a = \frac{\Delta_c \cdot \Delta_b}{\left|\Delta_c - \Delta_b\right|}\\]

## Why iteration?

In a query with multiple output streams, one stream may depend on another:

```
DECLARE a INTEGER STREAM core0, 0.1 FILE 'data.dat'
SELECT str1[0] STREAM str1 FROM core0
SELECT str2[0] STREAM str2 FROM str1
```

In the first iteration round, the compiler determines Δ\_str1 = 1/10 (because Δ\_core0 is known). In the second round — Δ\_str2 = 1/10 (because Δ\_str1 is now known). Without iteration, str2 would have to be declared before str1, which would limit the language's expressiveness.
