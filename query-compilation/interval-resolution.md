# Interval Resolution

Every stream in RetractorDB has an assigned time interval - delta (Δ). The interval determines how often new values are produced. For declared streams (`DECLARE`), the interval is given by the user. For output streams (`SELECT`), the interval is determined by the compiler from the stream-algebra equations.

The examples in this chapter use the canonical declarations from the whole chapter: `core0` (Δ=1/10), `core1` (Δ=1/5), `core2` (Δ=3/10).

## Algorithm

The `resolveStreamIntervals` stage works iteratively. Declared source intervals are already known and positive; an unresolved output stream interval has an internal value of zero. The existence of every source is checked before this stage.

```
loop:
    unresolvedCount = 0
    resolvedThisPass = 0
    sort qTree by increasing interval
    for every query except declarations and directives:
        if any source interval is unresolved:
            unresolvedCount++
            continue to the next query
        determine the output delta from the operator's equation
        if this query's interval was unresolved:
            resolvedThisPass++
        store the determined delta
    if unresolvedCount == 0: done (success)
    if resolvedThisPass == 0: error (cycle in the graph)
```

The `qTree::sort()` call orders nodes by interval, not topologically. A producer therefore need not precede its consumer. An interval determined earlier in the same round is immediately available to subsequent queries.

In a valid acyclic graph, every round that starts with unresolved nodes resolves at least one of them: those nodes include one whose sources are all already resolved. Known intervals remain known, so the number of unresolved nodes decreases. If unresolved nodes remain after a round but `resolvedThisPass == 0`, there is a cycle - see [Loop Detection](loop-detection.md). An invalid operator argument or an out-of-range result causes a separate compilation refusal.

## Operator equations

### Stream sum (`+`, STREAM\_ADD)

```rql
SELECT ... STREAM c FROM a + b
```

\\[\Delta_c = \min(\Delta_a, \Delta_b)\\]

The output stream produces values as often as the faster of the input streams.

Example: core0(Δ=1/10) + core1(Δ=1/5) → str1(Δ=1/10)

### Stream synchronization (`#`, STREAM\_HASH)

```rql
SELECT ... STREAM c FROM a # b
```

\\[\Delta_c = \frac{\Delta_a \cdot \Delta_b}{\Delta_a + \Delta_b}\\]

The `#` operator interleaves input records. The output rate is the sum of the input rates, giving the interval above. The plan determines which input is selected; the sources need not emit simultaneously.

Example: core0(Δ=1/10) # core1(Δ=1/5) → str1(Δ=1/15)

### Stream difference (`- r`, STREAM\_SUBTRACT)

```rql
SELECT ... STREAM c FROM a - r
```

\\[\Delta_c = r,\qquad r \geq \Delta_a > 0\\]

The argument `r` is the target interval, not an amount subtracted from the source interval. The operator selects source records at this rate. An equal interval preserves the source rate, a larger interval produces a slower result, and a smaller interval is refused during plan constraint validation.

### Time shift (`>n`, STREAM\_TIMEMOVE)

```rql
SELECT ... STREAM c FROM a > n
```

\\[\Delta_c = \Delta_a\\]

A shift changes neither the stream's rate nor its emitted record sequence, but it does change the index at which that sequence appears: record `m` carries the content of record `m-n`. It is a causal delay, but its carrier is the **logical origin**, not the tail - records with an index below `n` have no definition. The operator's own tail is non-negative: it equals `max(0, W_src - n)`, because record `m-n` is older than the current one and therefore all the more available. The plan listing shows both quantities as `origin=` and `tail=`; the silent slots are their sum and the runtime emits nothing in them.

Source history requires `n+1` records for the read range itself, plus two more for a declared source's head lead (the record armed when the storage is opened and the zero prefetch), which logical-index addressing does not shorten.

### Stream reducers (`MAX`, `MIN`, `AVG`, `SUMC`)

\\[\Delta_c = \Delta_a\\]

Reducers operate on a complete stream expression, e.g. `AVG(a@(1,10))`. They reduce values within a record or a window, but the output stream's interval stays the same as the source's. The postfix forms `.max`, `.min`, `.avg`, and `.sumc` remain backward compatible but are deprecated.

### The AGSE algorithm (`@(step, window)`, STREAM\_AGSE)

```rql
SELECT ... STREAM c FROM a @ (step, window)
```

\\[\Delta_c = \frac{\Delta_a \cdot \text{step}}{F_{a}}\\]

AGSE (the Episode Series Generation Algorithm) generates sliding windows. `F_a` is the number of flat values in a source record, determined by `descriptorStorage().flatElementCount()`. The step counts these values, so the output interval depends on the step and the input record width. The output window size determines the number of values in the window.

### De-hash operators (STREAM\_DEHASH\_DIV, STREAM\_DEHASH\_MOD)

If `c = a # b`, the `&` operator determines the interval of component `a` from the interval of interleave `c` and an argument denoting the interval of the other component `b`. Inverting the interleave equation gives:

\\[\Delta_a = \frac{\Delta_c \cdot \Delta_b}{\Delta_b - \Delta_c},\qquad 0 < \Delta_c < \Delta_b\\]

The domain follows from positive intervals: the interleave has a higher rate than either component. For the `%` operator, the roles of `a` and `b` are exchanged.

The implementation generally uses the absolute-value formula:

\\[\Delta_a = \frac{\Delta_c \cdot \Delta_b}{\left|\Delta_c - \Delta_b\right|}\\]

The compiler refuses equal intervals and a result faster than the source, that is, `Delta_a < Delta_c`. It can also accept an argument outside the domain of interleave inversion. For example, for `Delta_c = 3/2` and `Delta_b = 1` it computes `Delta_a = 3`, but interleaving intervals `3` and `1` gives an interval of `3/4`, not `3/2`. The absolute value therefore does not make this formula an inverse of `#` outside the stated domain.

## Interval validation

A `DECLARE` source interval must be positive. The compiler also checks this for a plan constructed without the parser. Interval arguments to `&`, `%` and `-` are checked during compilation; for deinterleave `&` and `%`, an argument equal to the source interval is also refused before division by zero in the formula above. This includes a source interval computed from another expression. In Python, this refusal gives `CompileError`, after which the plan can be corrected and compilation retried.

Operator arithmetic uses wider integers and checks whether the result fits the interval representation. An out-of-range result is a plan refusal. An internal zero denoting an unresolved node, and a directive's zero interval, do not authorize a source with a zero step. After compilation completes, stream intervals are positive; runtime relies on this invariant instead of repeating the same checks for every record. `ut_compiler` regressions cover nonpositive intervals, equal-interval deinterleave and recompilation of a valid plan containing directives.

## Why iteration?

In a query with multiple output streams, one stream may depend on another:

```rql
DECLARE a INTEGER STREAM core0, 0.1 BINFILE 'data.dat'
SELECT str1[0] STREAM str1 FROM core0
SELECT str2[0] STREAM str2 FROM str1
```

Both output streams have an interval of `1/10`. If `str1` is visited before `str2` in a round, both intervals can be determined in that same round. If the order is reversed, `str2` waits until the next round because `str1`'s interval was not yet known when `str2` was visited.

Iteration makes the result independent of the visit order after sorting by interval. The order of queries in the file does not dictate their resolution order. If this stage processed the graph in a true topological order, the entire valid dependency chain could be resolved in one traversal.
