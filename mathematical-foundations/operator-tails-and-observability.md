# Tails, logical origins and operator observability

A causal realization extends a stream \\(S=(s_n,\Delta_S)\\) with **two**
integer quantities, not one. The distinction matters: they answer different
questions and behave differently under plan rewrites.

| Quantity | Question | Meaning |
|---|---|---|
| logical origin \\(O_S\\) | *which record is missing?* | index of the first record that **exists at all**; records with a lower index have no definition, because they would reach before the start of the source stream |
| startup tail \\(W_S\\) | *when is a record ready?* | record \\(n\\) is emitted at time \\((n+1+W_S)\Delta_S\\) |

Neither is a prefix of zeros or of all-null records. The boundary principle
holds unchanged: `NULL` is a data value, never a placeholder. The number of
initial slots in which the stream stays silent is \\(O_S+W_S\\) — and only that
sum was visible before the two quantities were separated.

The logical index is the currency of every mapping between streams. A stream
with a non-zero \\(O_S\\) has no earlier records, so its physical record 0
carries logical index \\(O_S\\); the conversion to a buffer offset is performed
solely by `dataModel::fetchForward()`.

## Operator audit

In the table, "own tail" is the delay required by the operator beyond producer
availability. Producer tails are converted to result slots beforehand.

| Operator | Source index or bound | Logical origin | Own tail | Test |
|---|---|---|---:|---|
| projection / `PUSH_STREAM` | current tuple | \\(O_S\\) | 0 | `ut_compiler` |
| shift `>N` | record \\(n-N\\) | \\(O_S+N\\) | \\(-N\\), see below | `ut_compiler`, `ut_h10aGate` |
| sum `+` | current co-indexed tuples | mapping threshold | 0 | `ut_compiler` |
| interleave `#` | phase maximum \\(H_{a,b}\\) | mapping threshold | \\(H_{a,b}\\) | `deinterleave_roundtrip` |
| left de-interleave `&` (`DIV`) | \\(n+\lceil(n+1)\Delta_a/\Delta_b\rceil\\) | mapping threshold | 1 | `deinterleave_roundtrip` |
| right de-interleave `%` (`MOD`) | \\(n+\lfloor n\Delta_b/\Delta_a\rfloor\\) | mapping threshold | 0 | `deinterleave_roundtrip` |
| difference `C-Delta` | \\(\lceil n\Delta/\Delta_C\rceil\\) | mapping threshold | phase-dependent, at most 1 when \\(\Delta\ge\Delta_C\\) | `it_k19_boundaries` |
| AGSE `@(k,L)` | fields from \\(nk-(\lvert L\rvert-1)\\) to \\(nk\\) | formula below | formula below | `agse1`, `agse2`, `agse3`, `it_k19_boundaries`, `ut_h10aGate` |
| `sumc`, `avgc`, `minc`, `maxc` | current full tuple | \\(O_S\\) | 0 | `ut_dataModel`, `it_k19_boundaries` |

"Mapping threshold" is the smallest index \\(n\\) **from which** every later
record maps onto existing component records. It is not "the first index with
complete dependencies": with an interleave of components having different
origins, record 0 may be complete while record 1 is not. A stream is a sequence
of records, not a set with holes — the boundary principle forbids filling a hole
with `NULL` — so the logical origin is the first index with no remaining gap.
All record-to-record mappings are non-decreasing, so such an index exists and is
unique.

The difference operator takes a target interval \\(\Delta\\) that may not be
smaller than the source interval \\(\Delta_C\\). For the ratio
\\(r=\Delta/\Delta_C=p/q\\) the maximum phase lead of the index
\\(\lceil nr\rceil\\) is \\((q-1)/q\\). A declared producer requires one slot
even in integral phase, because it publishes the next record after consumers
read within the same tick.

## The shift \\(\tau_N\\)

Record \\(n\\) carries the content of producer record \\(n-N\\). Hence both
quantities:

\\[
O_{\tau_N(S)}=O_S+N,
\qquad
W_{\tau_N(S)}=\max\left(0,\;W_S-N\right)
\\]

The tail **decreases**, it does not grow. Record \\(n-N\\) is older than the
current one, so it is available all the more readily: the deficit of slot
\\(n\\) is \\((n-N+1+W_S)-(n+1)=W_S-N\\) and is **constant**, independent of
\\(n\\). The shift therefore moves silence from the tail into the logical
origin, and additionally absorbs the producer tail whenever \\(N\ge W_S\\).

The sum \\(O+W\\) is not invariant here: for \\(N<W_S\\) it equals \\(W_S\\),
whereas the realization from before the separation gave \\(W_S+N\\). That
earlier realization overestimated the tail by \\(\min(W_S,N)\\); the
overestimate was measured on 6.6% of `>N` class nodes in the campaign
`rdb-experiment/results_20260807_K24p` and removed by addressing the producer
with a logical index instead of a relative offset.

## The full AGSE window

The window is stamped by the interval **end**: record \\(n\\) spans flattened
source positions from \\(nk-(\lvert L\rvert-1)\\) to \\(nk\\). Its newest field
therefore lies exactly at position \\(nk\\), and the window's logical index
denotes the same instant as the source's logical index — joining a window with
its own source (a FIR pipeline) does not lead the signal.

The price of the convention is that for small \\(n\\) the window would reach
before the start of the source. Those records are not produced. Let the source
have \\(F\\) fields and logical origin \\(O_S\\); requiring the whole window to
fit gives

\\[
O_{\operatorname{AGSE}}
=\left\lceil\frac{O_S F+\lvert L\rvert-1}{k}\right\rceil
\\]

Availability is governed by the newest field, which lies in record
\\(\lfloor nk/F\rfloor\\). Substituting \\(r_n=(nk)\bmod F\\), the availability
condition for every \\(n\\) becomes \\(W\ge\bigl(F(1+W_S)-r_n\bigr)/k-1\\). The
residues \\(r_n\\) run through multiples of \\(\gcd(F,k)\\) periodically, so the
minimum \\(r_n=0\\) is attained regardless of the index at which the stream
starts. Hence

\\[
W_{\operatorname{AGSE}}
=\left\lceil\frac{(1+W_S)F}{k}\right\rceil-1
\\]

The phase term \\(P_{F,k,L}=\lfloor(\lvert L\rvert-1)/g\rfloor\,g\\), present in
the form used before the re-stamping, **disappeared from the tail**: the window
span is not waiting but undefinedness, and moved wholly into the logical origin.
The sum \\(O+W\\) describes the same silence as before.

A positive width preserves the historical RetractorDB convention — the newest
field comes first; a negative width mirrors it, giving arrival order.

Source history capacity has no closed form here. The backward distance at the
moment record \\(n\\) is emitted,

\\[
\left\lfloor\frac{(n+1+W)k}{F}\right\rfloor-W_S-1
\;-\;
\left\lfloor\frac{nk-\lvert L\rvert+1}{F}\right\rfloor,
\\]

is periodic with period \\(F/\gcd(F,k)\\) output slots, so the maximum is
computed **exactly**, by scanning one full period from
\\(O_{\operatorname{AGSE}}\\). A closed form would be guesswork here, and
underestimating means reading outside history, not merely one slot of delay.
A declared source has one record armed when the storage is opened plus a zero
prefetch, so its capacity bound contains two extra records. Capacity is a
property of execution, not part of the result.

## The observability relation

Stream observation splits into two parts, because plan rewrites preserve them
to different degrees.

**Value part** — preserved by rewrites exactly:

\\[
\operatorname{Obs}(S)
=\left(\Delta_S,O_S,D_S,(s_n,N_n)_{n\ge O_S},G_S,M_S\right)
\\]

where:

* \\(O_S\\) is the logical origin, the index of the first record;
* \\(D_S\\) is the public descriptor and field-name order;
* \\(N_n\\) is the record's `NULL` map — a true `NULL` remains a data value and
  is carried through AGSE;
* \\(G_S\\) is the gap trace; detection currently works for declarations, while
  computed streams have \\(G_S=\varnothing\\);
* \\(M_S\\) describes the materialization policy (`DEFAULT`, `MEMORY`,
  `VOLATILE` and the remaining storage kinds).

**Latency part** — the tail \\(W_S\\) — carries a weaker guarantee:

> a plan rewrite never **increases** \\(W_S\\) and never emits a record before
> its dependencies are determined; it may, however, **decrease** \\(W_S\\).

The split is not a formality. The \\(R_1\\) factoring
(\\(\varphi(\tau_i(A),\tau_k(B))\to\tau_{i+k}(\varphi(A,B))\\)) preserves the
whole value part but **shortens** the tail: the factored form reads content
directly from the interleave, whereas the unfactored form reads components only
after their own shift. Proof and measurement: [Formal foundations and
proofs](formal-foundations-and-proofs.md), theorem on commuting a shift with an
interleave. Regressions: `it_r1_identity_nulls`,
`it_optimizer_ablation-factor-name-collision-semantic`.

Changing any component of the value part changes the observable artifact. In
particular, enabling gap propagation for computed streams in the future requires
a versioned semantic change.

A read outside available history internally returns an all-null record as a
failsafe. A correctly compiled plan never materializes it: `logicalOrigin` skips
slots without a definition, `startupLatency` skips slots not yet determined, and
the history capacity retains every required index. The `it_k19_boundaries` test
distinguishes this case from a genuine `NULL` located inside a full window.

The independent oracle and the full phase campaigns live in
`rdb-experiment/results_20260728_K19` (operator boundaries) and
`rdb-experiment/results_20260807_K24p` (separation of logical origin and tail,
nine operator classes, two seeds).
