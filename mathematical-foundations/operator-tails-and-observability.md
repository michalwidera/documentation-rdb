# Operator Tails and Observability

Causal execution extends a stream \\(S=(s_n,\Delta_S)\\) with a startup tail
\\(W_S\\): the number of initial slots of interval \\(\Delta_S\\) in which
the stream emits no record. A tail is not a prefix of zeros or all-null
records.

## Operator audit

“Own tail” below is the delay required by an operator beyond producer
availability. Producer tails are first converted to output slots.

| Operator | Source index or bound | Own tail | Test |
|---|---|---:|---|
| projection / `PUSH_STREAM` | current tuple | 0 | `ut_compiler` |
| time shift `>N` | history slot `N` | N | `ut_compiler` |
| sum `+` | current co-indexed tuples | 0 | `ut_compiler` |
| interleave `#` | phase maximum \\(H_{a,b}\\) | \\(H_{a,b}\\) | `deinterleave_roundtrip` |
| left de-interleave `&` (`DIV`) | \\(n+\lceil(n+1)\Delta_a/\Delta_b\rceil\\) | 1 | `deinterleave_roundtrip` |
| right de-interleave `%` (`MOD`) | \\(n+\lfloor n\Delta_b/\Delta_a\rfloor\\) | 0 | `deinterleave_roundtrip` |
| difference `C-Delta` | \\(\lceil n\Delta/\Delta_C\rceil\\) | phase bound, at most 1 for \\(\Delta\ge\Delta_C\\) | `it_k19_boundaries` |
| AGSE `@(k,L)` | fields \\(nk\\) through \\(nk+\lvert L\rvert-1\\) | phase bound below | `agse1`, `agse2`, `agse3`, `it_k19_boundaries` |
| `sumc`, `avgc`, `minc`, `maxc` | current complete tuple | 0 | `ut_dataModel`, `it_k19_boundaries` |

Difference takes a target interval \\(\Delta\\), which cannot be smaller than
the source interval \\(\Delta_C\\). For
\\(r=\Delta/\Delta_C=p/q\\), the maximum phase lead of
\\(\lceil nr\rceil\\) is \\((q-1)/q\\). A declared producer also needs one
slot in an integral phase because it publishes its next record after
consumers read in that tick.

## Complete AGSE windows

Let the source have \\(F\\) fields, window step \\(k\\), width \\(L\ne0\\),
and \\(g=\gcd(F,k)\\). The residues \\(nk\bmod F\\) visit multiples of
\\(g\\). The maximum lead of the last window field is:

\\[
P_{F,k,L}
=\left\lfloor\frac{|L|-1}{g}\right\rfloor g
\\]

For producer tail \\(W_S\\), the total AGSE tail is:

\\[
W_{\operatorname{AGSE}}
=\left\lfloor\frac{F W_S+P_{F,k,L}}{k}\right\rfloor+1
\\]

The bound is strict: a history read cannot assume that an active producer
has completed its record in the same tick. Every emitted record therefore
contains a complete window. Positive width follows RetractorDB's historical
convention, newest field first; negative width mirrors it into arrival order.

Source history must additionally cover the worst phase \\((F-g)/F\\). For a
computed producer, the minimum retained record count is:

\\[
\left\lceil
W_{\operatorname{AGSE}}\frac{k}{F}-W_S+\frac{F-g}{F}
\right\rceil
\\]

A declared source has one record armed when storage opens and a zero-step
prefetch, so its capacity bound includes two additional records. Capacity is
an execution property, not part of the output.

## Observability relation

For K19, a stream observation is:

\\[
\operatorname{Obs}(S)
=\left(\Delta_S,W_S,D_S,(s_n,N_n)_{n\ge0},G_S,M_S\right)
\\]

Here \\(D_S\\) is the public descriptor and field-name order; \\(N_n\\) is
the record's null map; \\(G_S\\) is the gap trace; and \\(M_S\\) is the
materialization policy. Gap detection currently applies to declarations,
while computed streams use \\(G_S=\varnothing\\). Enabling computed-stream
gap propagation would change the observable artifact and requires a
versioned semantic change.

An out-of-range history read internally returns an all-null guard record. A
valid compiled plan never materializes it: `startupLatency` skips undefined
slots and the history capacity retains every required index. The
`it_k19_boundaries` test distinguishes this case from a genuine `NULL`
inside a complete window.

The independent oracle and full phase campaign are in
`rdb-experiment/results_20260728_K19`.
