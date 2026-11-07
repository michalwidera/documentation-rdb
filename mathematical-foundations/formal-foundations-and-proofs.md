# Formal Foundations and Proofs

The chapter on the [algebra of regular time series](algebra-of-regular-time-series.md) defines the operators and their equations. This page presents their justification: the connection to covering-system theory and proofs of properties used to interpret and optimize query plans. The final [section on the connection to the implementation](#connecting-proofs-to-the-implementation) explains which properties have been formalized in Lean and how tests compare the model with C++ functions.

> **ℹ️ Info**
>
> The rational variant matters for the implementation. Beatty's theorem describes a partition for irrational parameters, while Fraenkel's generalization also admits rational parameters. The proofs below show that sample-position selection by interleaving and de-interleaving can be computed exactly in this domain, without floating-point approximations.


## Covering systems as the foundation

The literature on covering systems [\[4\]](../references.md#4) belongs to combinatorics and cryptanalysis within number theory. The problem under consideration is how to determine a partition of the set of positive natural numbers. We say that two sequences partition the set of positive natural numbers if the sets formed from the elements of these sequences have an empty intersection, and their union forms the set of positive natural numbers.

The basis for these considerations is the parameterized Beatty sequence. In its general form it is written using the floor function:

\\[
\mathcal{B}(\alpha ,\alpha ^{\prime }) := \left( \left\lfloor \frac{n-\alpha ^{\prime }}{\alpha }\right\rfloor \right) _{n=1}^{\infty }
\\]

This single definition generates an entire family of sequences. Partition results always concern a **pair** of its instances with different parameters: we write the pair as B(α, α′) and B(β, β′), where the second notation denotes the complementary term.

The parameters of this sequence have a clear geometric interpretation:

* α denotes the density of the sequence,
* 1/α denotes the slope,
* α′ denotes the offset,
* −α′/α denotes the y-intercept (the point where it crosses the y-axis).

The [Beatty](../references.md#1) theorem guarantees a partition of the set for irrational numbers. The [Fraenkel](../references.md#2) theorem is a generalization that - crucially for us - also allows rational numbers, provided five postulates are satisfied (quoted in the [introductory chapter](./)). An accessible proof of Fraenkel's theorem can be found in K. O'Bryant's paper _"Fraenkel's partition and Brown's decomposition"_ [\[23\]](../references.md#23).

The remainder of this page boils down to a single idea: showing that the stream operators are, in essence, machines generating Beatty sequences that partition (cover) the set of natural numbers.

## Tools: floor and ceiling properties

The proofs rely almost exclusively on the floor function (⌊x⌋ - the integer part) and the ceiling function (⌈x⌉ - the smallest integer not less than x). I therefore first present a set of identities that will be used repeatedly. Let x ∈ ℝ, and let C denote an integer:

\\[
\left\lfloor x\right\rfloor = \left\lceil x\right\rceil \iff x \in \mathbb{Z}
\\]

\\[
\left\lfloor x\right\rfloor + 1 = \left\lceil x\right\rceil \iff x \in \mathbb{R} \setminus \mathbb{Z}
\\]

The second of these identities carries over directly to Beatty sequences themselves. The ceiling variant of the sequence, B′<sub>α</sub>(n) = ⌈nα⌉, is - for irrational α - merely a shifted version of the floor variant:

\\[
B_{\alpha}^{\prime}(n) = \left\lceil n\alpha \right\rceil = \left\lfloor n\alpha \right\rfloor + 1
\\]

In the classical Beatty theorem, α is irrational, so nα is not an integer for any n > 0. The second identity therefore applies to every term: the ceiling variant raises each term of the floor variant by exactly 1. For rational α, nα can be an integer, in which case ⌈nα⌉ = ⌊nα⌋. The relationship must then be checked term by term. Part three of the proof of Theorem 2 (de-interleaving satisfies Fraenkel's postulates) performs this case analysis using gcd(a, b).

\\[
\left\lfloor x + C\right\rfloor = \left\lfloor x\right\rfloor + C
\\]

(the last identity holds for every C ∈ ℤ). Additionally, in analyzing the residue of the de-interleaving sequence we will use relationships tying the greatest common divisor (gcd) to the domain of the quotient a/b. For a, b ∈ ℕ<sub>>0</sub>:

\\[
\operatorname{gcd}(a,b) = b \iff \frac{a}{b} \in \mathbb{N}
\\]

and otherwise:

\\[
1 \leq \operatorname{gcd}(a,b) \leq \min(a,b)
\\]

These two cases disjointly cover the entire domain of interest to us - which will let us carry out a proof "by cases."

## Operators in formal notation

The operators introduced in the query language have their formal counterparts. The table below ties the formal notation (used in the proofs) to the symbols found in the [query language](../query-language-construction/):

| Operation | Formal symbol | Symbol in the query language |
| --- | --- | --- |
| Projection | π | field list after `SELECT` |
| Selection | σ | logical condition |
| Sum | Σ | `+` |
| Difference | δ | `-` |
| Interleaving | φ | `#` |
| De-interleaving and its complement | Θ, ∼Θ | `&` , `%` |
| Aggregation and serialization (AGSE) | Ψ | `@` |
| Shift | τ | `>` |

For the proofs to be self-contained, I restate two definitions I will refer to directly.

**Interleaving** φ(A, B) produces an output stream whose successive tuples are determined by the rule:

\\[
c_{n}= \left\\{ \begin{array}{cc} b_{n-\left\lfloor n z \right\rfloor } & \left\lfloor n z \right\rfloor = \left\lfloor \left( n+1\right) z \right\rfloor \\\\ a_{\left\lfloor n z \right\rfloor } & \left\lfloor n z \right\rfloor \neq \left\lfloor \left( n+1\right) z \right\rfloor \end{array} \right. , \ z = \frac{\Delta _{b}}{\Delta _{a}+\Delta _{b}}, \ \Delta _{c}=\frac{\Delta _{a}\Delta _{b}}{\Delta _{a}+\Delta _{b}}
\\]

**De-interleaving** is defined by two complementary formulas - operator Θ, which recovers the original stream, and operator ∼Θ, which determines the "remainder" of the de-interleaving:

\\[
a_{n} = c_{n+ \left\lceil \frac{(n+1)\Delta _{a}}{\Delta _{b}} \right\rceil },\ \Delta _{a}=\frac{\Delta _{c}\Delta _{b}}{\left\vert \Delta _{c}-\Delta _{b}\right\vert }
\\]

\\[
b_{n} = c_{n+\left\lfloor \frac{n\Delta_{b}}{\Delta_{a}}\right\rfloor},\ \Delta_{b}=\frac{\Delta_{c}\Delta_{a}}{\left\vert \Delta_{c}-\Delta_{a}\right\vert }
\\]

## Theorem 1: interleaving guarantees set coverage

> **✅ Note**
>
> **Theorem.** The interleaving operation guarantees sequential coverage of both index sets of the data streams that are its arguments: every element of stream A and every element of stream B is selected exactly once, in order, without gaps and without repetition.


**Proof.** Since 0 < z < 1, the increment

\\[
d_{n} := \left\lfloor \left( n+1\right) z \right\rfloor - \left\lfloor n z \right\rfloor
\\]

equals 0 or 1 for every n ≥ 0. The interleaving equation selects an element of stream B exactly at those steps where d<sub>n</sub> = 0 (the equality branch), and an element of stream A exactly at steps where d<sub>n</sub> = 1.

Consider the selection index for sequence B: x<sub>n</sub> = n − ⌊nz⌋. In a single step, x<sub>n+1</sub> − x<sub>n</sub> = 1 − d<sub>n</sub>: the index increases by exactly 1 at every step selecting from B, and otherwise remains unchanged. So if n < n′ are two consecutive steps selecting from B, then x<sub>n′</sub> = x<sub>n</sub> + 1. The first step selecting from B is n = 0, since 0 < z < 1 implies ⌊0⌋ = ⌊z⌋ = 0, i.e. d<sub>0</sub> = 0, and x<sub>0</sub> = 0. Selections from sequence B therefore use indices 0, 1, 2, … in order, without gaps or repetitions.

Symmetrically: the selection index for sequence A, i.e. ⌊nz⌋, increases by exactly 1 at every step selecting from A (d<sub>n</sub> = 1), and otherwise remains unchanged; at the first such step its value is 0 (all earlier steps have d = 0). The elements of sequence A are therefore also selected exactly once each, in order. ∎

## Theorem 2: de-interleaving satisfies Fraenkel's postulates

The theorem connects both sample-selection sequences in de-interleaving to Beatty sequences satisfying Fraenkel's postulates for rational parameters. It thereby establishes the exact inversion of interleaving.

> **✅ Note**
>
> **Theorem.** Let a, b ∈ ℕ<sub>>0</sub> represent the rational ratio of the rates of the component streams, ∆<sub>a</sub>/∆<sub>b</sub> = a/b. Both tuple-selection sequences describing the de-interleaving operation are - up to the index alignment shown in the proof - a special case of Beatty sequences satisfying the postulates of Fraenkel's theorem for rational parameters. Consequently they partition the set ℕ₀ := ℕ ∪ {0}, i.e. the index set of the interleaved stream, and de-interleaving exactly inverts interleaving using rational-number arithmetic alone.


**Proof - part one (reduction to Beatty form).** The tuple-selection sequence for the de-interleaving residue (operator ∼Θ) has the form:

\\[
\left( n + \left\lfloor \frac{nb}{a} \right\rfloor \right) _{n=0}^{\infty }
\\]

Its initial term (n = 0) equals 0; the terms for n ≥ 1 form the Beatty part. For n ∈ ℕ, by the property ⌊x + C⌋ = ⌊x⌋ + C, we have n + ⌊nb/a⌋ = ⌊n + nb/a⌋, so we seek α, α′ such that:

\\[
\left( \left\lfloor \frac{n-\alpha ^{\prime }}{\alpha }\right\rfloor \right) _{n=1}^{\infty } = \left( \left\lfloor n\frac{a + b}{a} \right\rfloor \right) _{n=1}^{\infty }
\\]

Reading off the slope and the offset: with a shift of α′ = 0 we obtain α = a/(a+b), and the selection sequence restricted to n ≥ 1 is exactly:

\\[
\mathcal{B}\\!\left( \frac{a}{a + b}, 0 \right) = \left( \left\lfloor n\frac{a + b}{a} \right\rfloor \right) _{n=1}^{\infty }
\\]

**Proof - part two (verifying the five postulates and determining the residue).** We check the postulates of Fraenkel's theorem in turn for α = a/(a+b), α′ = 0:

1. The value α = a/(a+b) for a, b > 0 is greater than zero and less than one.
2. The condition α + β = 1 is satisfied for β = b/(a+b).
3. For α′ = 0 the postulate is equivalent to postulate 1.
4. The postulate is vacuous, since α is a rational number.
5. The smallest number q for which qα ∈ ℕ is q = (a+b)/gcd(a,b); then the condition 1/q ≤ α + α′ = α is satisfied, and the condition ⌈qα′⌉ + ⌈qβ′⌉ = 1 with α′ = 0 forces ⌈qβ′⌉ = 1, i.e. 0 < β′ ≤ gcd(a,b)/(a+b). Every admissible value generates the same sequence (the complement of the sequence B(a/(a+b), 0) in ℕ is unique); we take β′ = gcd(a,b)/(a+b).

The sequence complementing B(a/(a+b), 0) in the sense of Fraenkel's postulates is therefore:

\\[
\mathcal{B}\\!\left( \frac{b}{a + b}, \frac{\operatorname{gcd}(a, b)}{a + b} \right)
\\]

After reindexing n ↦ n + 1, so that it runs from n = 0 - matching the selection sequences in the definition of de-interleaving - it takes the form:

\\[
\left( \left\lfloor \frac{(n + 1) - \frac{\operatorname{gcd}(a,b)}{a+b}}{\frac{b}{a+b}} \right\rfloor \right) _{n=0}^{\infty }
\\]

Expanding the above expression:

\\[
\left\lfloor \frac{(n + 1) - \frac{\operatorname{gcd}(a,b)}{a+b}}{\frac{b}{a+b}} \right\rfloor = \left\lfloor n\frac{a}{b} + n + \frac{a}{b} + 1 - \frac{\operatorname{gcd}(a, b)}{b} \right\rfloor
\\]

Comparing this - term by term for n ≥ 0 - with the tuple-selection sequence of the recovered stream (operator Θ):

\\[
\left( n + \left\lceil \frac{(n + 1)a}{b} \right\rceil \right) _{n=0}^{\infty }
\\]

and factoring out the integer part n + 1 via the property ⌊x + C⌋ = ⌊x⌋ + C, the claim reduces (after substituting n for n + 1, so that n ranges over ℕ<sub>>0</sub>) to the identity:

\\[
\left\lfloor n\frac{a}{b} - \frac{\operatorname{gcd}(a, b)}{b} \right\rfloor + 1 = \left\lceil n\frac{a}{b} \right\rceil ,\quad n \in \mathbb{N}_{>0}
\\]

**Proof - part three (case analysis).** Using the properties of the coefficient gcd(a, b), we consider two disjoint cases covering the entire domain.

_Case 1: gcd(a, b) = b, i.e. a/b ∈ ℕ._ Then n·a/b ∈ ℕ, so by the identity ⌊x⌋ = ⌈x⌉ ⟺ x ∈ ℤ we have ⌈n·a/b⌉ = ⌊n·a/b⌋, and by ⌊x + C⌋ = ⌊x⌋ + C:

\\[
\left\lfloor n\frac{a}{b} - 1 \right\rfloor + 1 = \left\lfloor n\frac{a}{b} \right\rfloor
\\]

Both sides of the identity being proved coincide.

_Case 2: b ∤ a, i.e. 1 ≤ gcd(a, b) < b and 0 < gcd(a,b)/b < 1._

If n·a/b ∉ ℤ, then by ⌊x⌋ + 1 = ⌈x⌉ ⟺ x ∈ ℝ ∖ ℤ we have ⌈n·a/b⌉ = ⌊n·a/b⌋ + 1. The fractional part of n·a/b is a nonzero multiple of gcd(a,b)/b, and hence at least gcd(a,b)/b; subtracting gcd(a,b)/b from n·a/b therefore cannot drop below the integer ⌊n·a/b⌋, whence:

\\[
\left\lfloor n\frac{a}{b} - \frac{\operatorname{gcd}(a, b)}{b} \right\rfloor = \left\lfloor n\frac{a}{b} \right\rfloor
\\]

and the identity being proved holds.

If n·a/b ∈ ℤ, then ⌈n·a/b⌉ = n·a/b, and since 0 < gcd(a,b)/b < 1:

\\[
\left\lfloor n\frac{a}{b} - \frac{\operatorname{gcd}(a, b)}{b} \right\rfloor = n\frac{a}{b} - 1
\\]

which again gives the identity being proved.

Both selection sequences describing the de-interleaving operation are therefore - up to the unit reindexing from part two - Beatty sequences satisfying Fraenkel's postulates for rational parameters: the pair B(a/(a+b), 0) and B(b/(a+b), gcd(a,b)/(a+b)) partitions the set ℕ, and together with the initial residue term 0 from part one - the set ℕ₀, the full index set of the interleaved stream. The recovered stream and the residue are therefore exact. ∎

> **✅ Note**
>
> **Corollary (exact invertibility over the rationals).** For streams with rational rates, the operators Θ and ∼Θ recover the component streams of φ(A, B) exactly (bit for bit): no tuple is lost, duplicated, or reordered relative to its component stream. The pair (φ; Θ, ∼Θ) therefore behaves like multiplication and division, and the pair (Σ; δ) like addition and subtraction, on the set of regular time series.

> **⚠️ Warning**
>
> The practical takeaway from this proof: the implementation must never leave the domain of rational numbers, not even momentarily. An implicit cast of an intermediate result to a floating-point number breaks the assumptions of the theorem above. Materialization into floating-point form must be deferred until an explicit application of the floor or ceiling operation.


## Operator properties used in optimization

Based on the algebra presented, a number of properties of data streams can be shown. They have direct application in the data-management system - during query-plan optimization and result interpretation.

### Disruption of event ordering

> **✅ Note**
>
> **Theorem.** The order of elements in a stream does not reflect the actual order in which the elements occurred in the real world.


**Proof (by counterexample).** Consider two streams:

```
Alpha(char),2:   {1,2,3,4,5,6,...}
Epsilon(char),3: {a,b,c,d,e,f,...}
```

The expression φ(Epsilon, Alpha) produces the output stream:

```
Tau(char),6/5:   {1,2,a,3,b,4,5,c,6,d,...}
```

In stream Tau, the tuple labeled `c` occurs after the tuple labeled `5`. Yet tuple `c` appears in stream Epsilon at second 9, while tuple `5` appears in stream Alpha at second 10. The natural order of events has been violated in the resulting stream. Conclusion: when analyzing time embedded in streams, applying the de-interleaving operation is necessary to recover the original form of the data streams. ∎

### Commutativity of summation

> **✅ Note**
>
> **Theorem.** The stream-summation operation, disregarding attribute order, is commutative.


**Proof.** Assume ∆<sub>a</sub> ≤ ∆<sub>b</sub>; the opposite case is symmetric. The first case of the sum definition gives, as the n-th element of stream Σ(A, B), the tuple:

\\[
c_{n} = \left( a_{n},\ b_{\left\lfloor n\Delta_{a}/\Delta_{b} \right\rfloor} \right)
\\]

whereas for Σ(B, A) the roles of the arguments are swapped, and its second case applies (or, at ∆<sub>a</sub> = ∆<sub>b</sub>, its first), giving as the n-th element:

\\[
c_{n} = \left( b_{\left\lfloor n\Delta_{a}/\Delta_{b} \right\rfloor},\ a_{n} \right)
\\]

Both streams carry ∆<sub>c</sub> = ∆<sub>a</sub>. They therefore coincide up to the order of the joined attributes. ∎

### Interleaving alignment method

The interleaving operation is not commutative in general: since 0 < z < 1, at n = 0 the equality branch of the interleaving definition always applies, so the stream φ(A, B) begins with element b₀, while the stream φ(B, A) begins with element a₀. Interleaving is, however, equivariant with respect to time shifts matched to the streams' rates - which is valuable for query-plan optimization.

In the causal realization a stream has the form \\(\widehat{S}=((s_n,\Delta),W_S)\\), where \\(W_S\\) is its startup tail. We define conversion of a producer's tail into output slots as:

\\[
\operatorname{conv}(w,\Delta_s,\Delta_o):=
\left\lceil\frac{w\Delta_s}{\Delta_o}\right\rceil
\\]

The tail of an interleave with interval \\(\Delta_c=\Delta_a\Delta_b/(\Delta_a+\Delta_b)\\) follows directly from the operator definition, without going through a single phase term.

Record \\(i\\) of \\(\varphi(A,B)\\) carries the content of record \\(j(i)\\) of exactly one component - the one the interleave definition selects in slot \\(i\\). Write \\(\Delta_{s(i)}\\) and \\(W_{s(i)}\\) for the interval and tail of the selected component. Record \\(j(i)\\) is determined at time \\(\bigl(j(i)+1+W_{s(i)}\bigr)\Delta_{s(i)}\\), while consumer slot \\(i\\) ends at \\((i+1+W)\Delta_c\\). The causality condition for every \\(i\\) is:

\\[
W\ge
\left\lceil\frac{\bigl(j(i)+1+W_{s(i)}\bigr)\Delta_{s(i)}}{\Delta_c}\right\rceil
-1-i
\\]

Let \\(\Delta_a/\Delta_b=p/q\\), where \\(p,q\in\mathbb{N}_{>0}\\) and \\(\gcd(p,q)=1\\). Both the component selection and the residue determining \\(j(i)\\) repeat with period \\(p+q\\), so the maximum of the right-hand side over **one** period is the maximum over all records:

\\[
W_{\varphi(A,B)}
=\max_{0\le i<p+q}\left(
\left\lceil\frac{\bigl(j(i)+1+W_{s(i)}\bigr)\Delta_{s(i)}}{\Delta_c}\right\rceil
-1-i
\right)
\\]

The formula is **exact**: it neither overshoots nor undershoots the event-model bound for any node. The period scan starts at zero - the logical origin shifts the consumer index and the component index by the same amount, so the window \\([0,\,p+q)\\) yields the same value as any shifted window.

The earlier closed form

\\[
W_{\varphi(A,B)}
=\max\left(
\operatorname{conv}(W_A,\Delta_a,\Delta_c),
\operatorname{conv}(W_B,\Delta_b,\Delta_c)
+H_{a,b}
\right)
\\]

\\[
H_{a,b}=\left\lceil\frac{p+q-1}{p}\right\rceil
\\]

protected the worst read phase of the second argument, but did not check whether that phase actually falls on the record that waits longest - hence it overshot the tail by one slot for some nodes. It survives in the implementation as the fallback for \\(p+q\\) above the scan threshold (`kHashPhaseScanLimit` in `SOperations.hpp`): overshooting costs one slot of latency, whereas undershooting would mean emitting a record before its dependency is determined. Tail slots are not records.

The shift \\(\tau_m\\) does not change the emitted record sequence, but it does change the **index** at which that sequence appears: record \\(n\\) carries the content of record \\(n-m\\). Records with an index below \\(O_S+m\\) have no definition, hence

\\[
O_{\tau_m(S)}=O_S+m,
\qquad
W_{\tau_m(S)}=\max\left(0,\;W_S-m\right)
\\]

The tail **decreases**: record \\(n-m\\) is older than the current one and therefore all the more available - the slot deficit is \\(W_S-m\\) and is constant. Details and measurement: [Tails, logical origins and operator observability](operator-tails-and-observability.md).

> **✅ Note**
>
> **Theorem (R1, commuting a shift with an interleave).** If numbers i, k ∈ ℕ are chosen such that i·∆<sub>a</sub> = k·∆<sub>b</sub> (both arguments shifted by the same amount of time), then interleaving the shifted streams and the interleaving of the original streams shifted by the sum of these numbers have **the same record sequence, the same interval and the same logical origin**. Their tails satisfy an inequality - the factored side is never the later one.

Formally, with \\(L:=i+k\\):

\\[
\operatorname{Obs}\Bigl(\varphi\bigl(\tau_{i}(A),\tau_{k}(B)\bigr)\Bigr)
=\operatorname{Obs}\Bigl(\tau_{i+k}\bigl(\varphi(A,B)\bigr)\Bigr),
\qquad i\Delta_{a}=k\Delta_{b},\quad i,k\in\mathbb{N}
\\]

\\[
W_{\mathrm{RHS}}=\max\left(0,\;W_{\varphi(A,B)}-L\right)\le W_{\mathrm{LHS}}
\\]

where \\(\operatorname{Obs}\\) is the value part of the observation (interval, logical origin, record sequence with its `NULL` map, descriptor, gap trace, materialization policy) - see [Tails, logical origins and operator observability](operator-tails-and-observability.md).

**Proof.**

*Interval.* Both sides arise from the same interleave, so both have \\(\Delta_c=\Delta_a\Delta_b/(\Delta_a+\Delta_b)\\).

*Auxiliary step.* From i·∆<sub>a</sub> = k·∆<sub>b</sub> it follows that

\\[
\frac{i\Delta_a}{\Delta_c}
=\frac{i\Delta_a(\Delta_a+\Delta_b)}{\Delta_a\Delta_b}
=\frac{i\Delta_a}{\Delta_b}+i
=k+i
=L\in\mathbb{N},
\\]

and symmetrically \\(k\Delta_b/\Delta_c=L\\). Shifting each argument by its own number of slots therefore corresponds to **the same** number \\(L\\) of result slots.

*Record sequence and logical origin.* Within one period the interleave takes \\(i\\) records from A and \\(k\\) records from B, filling exactly \\(L=i+k\\) slots of C. Shifting A by \\(i\\) and B by \\(k\\) therefore moves the mapping threshold of both components by exactly \\(L\\) result slots without changing their relative phase: \\(O_{\mathrm{LHS}}=O_{\varphi(A,B)}+L=O_{\mathrm{RHS}}\\). The content of a record at a given logical index is the same on both sides, because the choice of component depends only on phase, which is unchanged.

*Tails.* Let \\(s(n)\in\\{A,B\\}\\) denote the component selected in phase \\(n\\), and \\(j(n)\\) its index. Write the shifts as \\(t_A=i\\) and \\(t_B=k\\). After shifting, the component tail is \\(W_s^{\prime}=\max(0,W_s-t_s)\ge W_s-t_s\\). The intervals and the choice of component and its index in each interleave phase remain unchanged. Let \\(R_n\\) be the availability requirement from the phase formula above for tails \\(W_A,W_B\\), and \\(R_n^{\prime}\\) the requirement for \\(W_A^{\prime},W_B^{\prime}\\). The auxiliary step gives \\(t_s\Delta_s/\Delta_c=L\in\mathbb{N}\\) for both components. Monotonicity of the ceiling and its compatibility with shifts by the integer \\(L\\) give, in every phase:

\\[
\begin{aligned}
R_n^{\prime}
&=\left\lceil
\frac{(j(n)+1+W_{s(n)}^{\prime})\Delta_{s(n)}}{\Delta_c}
\right\rceil-1-n\\\\
&\ge\left\lceil
\frac{(j(n)+1+W_{s(n)}-t_{s(n)})\Delta_{s(n)}}{\Delta_c}
\right\rceil-1-n
=R_n-L.
\end{aligned}
\\]

We take the maximum over the same full period \\(p+q\\), since the shifts do not change the interval ratio. Using nonnegativity of tails as well, we obtain:

\\[
W_{\mathrm{LHS}}
\ge\max\left(0,\max_{0\le n<p+q}R_n-L\right)
=\max\left(0,W_{\varphi(A,B)}-L\right)
=W_{\mathrm{RHS}}.
\\]

Above the scan limit, the engine uses the \\(O(1)\\) fallback bound described earlier. For that bound, the same inequality follows from monotonicity of both \\(\operatorname{conv}\\) terms: a matched shift reduces each by at most \\(L\\), while the \\(H_{a,b}\\) term remains unchanged. Both sides use the same calculation variant because their intervals do not change. The fallback bound need not equal the exact phase maximum. ∎

> **⚠️ Scope of the theorem**
>
> Equality of tails **does not hold**. Counterexample: \\(\Delta_a=1/10\\), \\(\Delta_b=1/5\\), \\(W_A=W_B=0\\), \\(H_{a,b}=2\\), \\(i=2\\), \\(k=1\\), \\(L=3\\). Then \\(W_{\mathrm{LHS}}=2\\) while \\(W_{\mathrm{RHS}}=\max(0,2-3)=0\\). The unfactored side reads its components **after** their own shift, so it waits longer for the same content; the factored side reads it directly from the interleave.
>
> Practical consequence: the rewrite rule \\(\varphi(\tau_i(A),\tau_k(B))\to\tau_{i+k}(\varphi(A,B))\\) is a **latency optimization**, not a neutral rewrite. It preserves the entire value part of the observation and never emits a record before its dependencies are determined, but the result is ready sooner.
>
> Previously both sides had the same tail solely because the realization of \\(\tau_m\\) overestimated its own tail by \\(\min(W_S,m)\\). The overestimate was removed by addressing the producer with a logical index instead of a relative offset. Regressions guarding this scope: `it_r1_identity_nulls`, `it_optimizer_ablation-factor-name-collision-semantic`.

In the compiler, additional invariants preserve public stream field names, null value maps, and the materialization policy.

## Why this matters

These properties establish the boundaries of correct stream transformations:

* **Theorems 1 and 2** establish coverage of sample positions by interleaving and recovery of both components by de-interleaving, preserving the order within each component.
* **The rational variant** allows exact index mappings. The implementation must also check the limits of its numeric representation.
* **Operator properties** determine permitted rewrites and limits on interpretation. In particular, R1 preserves the value part of the observation but may reduce the startup tail, while interleaving does not preserve the general event order across its components.

The branch of mathematics in which these equations are situated is the theory of covering systems [\[4\]](../references.md#4) within number theory. The paper [A Deterministic Method for Processing Data Sequences](https://www.academia.edu/1840563/Deterministyczna_metoda_przetwarzania_ciagow_danych) [\[3\]](../references.md#3) presents the historical derivation of the method.

> **ℹ️ Info**
>
> A numerical verification of the equations above - Python prototypes operating on rational numbers (the `Fraction` library) - can be found on the [Model Implementation](model-implementation.md) page and in the repository [github.com/michalwidera/equations](https://github.com/michalwidera/equations).

## Connecting proofs to the implementation

The mathematical proofs concern the operator model. Their Lean formalization and the engine tests provide further levels of verification with distinct scopes. The sources are in the code repository's [`math_proofs`](https://github.com/michalwidera/retractordb/tree/master/math_proofs) directory; the [Lean project guide](https://github.com/michalwidera/retractordb/blob/master/math_proofs/README.md) describes tool setup, proof checking, and Verso document generation.

| Property | Formalization in `math_proofs/Profs/` |
| --- | --- |
| Sequential coverage by interleaving | [InterleaveCovering.lean](https://github.com/michalwidera/retractordb/blob/master/math_proofs/Profs/InterleaveCovering.lean) |
| Position partition and de-interleaving mappings | [BeattyPartition.lean](https://github.com/michalwidera/retractordb/blob/master/math_proofs/Profs/BeattyPartition.lean), [Deinterleave.lean](https://github.com/michalwidera/retractordb/blob/master/math_proofs/Profs/Deinterleave.lean) |
| Exact invertibility | [ExactInvertibility.lean](https://github.com/michalwidera/retractordb/blob/master/math_proofs/Profs/ExactInvertibility.lean) |
| Event-order counterexample and sum commutativity | [EventOrder.lean](https://github.com/michalwidera/retractordb/blob/master/math_proofs/Profs/EventOrder.lean), [SumCommutativity.lean](https://github.com/michalwidera/retractordb/blob/master/math_proofs/Profs/SumCommutativity.lean) |
| Matched shifts R1 and causal execution | [ShiftMatching.lean](https://github.com/michalwidera/retractordb/blob/master/math_proofs/Profs/ShiftMatching.lean), [CausalShift.lean](https://github.com/michalwidera/retractordb/blob/master/math_proofs/Profs/CausalShift.lean) |
| Phase-requirement periodicity and exact interleave tail | [InterleaveTailExact.lean](https://github.com/michalwidera/retractordb/blob/master/math_proofs/Profs/InterleaveTailExact.lean) |

The connection to the C++ code has four steps:

1. **Check the model in Lean.** The `Profs/` files contain definitions and proofs checked by the Lean kernel. The formalization of the positive-position partition uses Mathlib's generalized Rayleigh theorem. It does not formalize the full Fraenkel theorem. Once the environment is prepared, `lake build Profs`, run in `math_proofs`, checks the proof project.
2. **Generate the oracle.** [`OracleMain.lean`](https://github.com/michalwidera/retractordb/blob/master/math_proofs/OracleMain.lean) computes tables from the model definitions. The `gen-oracle.sh` script writes them to `test/UnitTest/proofOracle.hpp`, together with SHA-256 hashes of proof sources and files specifying tool versions.
3. **Compare with the implementation.** The `ut_proofOracle` test compares functions from `SOperations.hpp` with the generated tables and checks theorem consequences, for example `ProofOracle.deinterleave_inverts_interleave` and `ProofOracle.causal_shift_matching`. The C++ assertions check selected cases and parameter ranges; they do not constitute a universal proof that the entire implementation agrees with Lean.
4. **Check that the connections are current.** The `proof_drift` test checks oracle-input hashes and [`test/proof_manifest.tsv`](https://github.com/michalwidera/retractordb/blob/master/test/proof_manifest.tsv). The manifest assigns theorems to tests or explicitly records missing coverage or a scope without an engine counterpart. Changes to proof sources or tool versions require regenerating the oracle; hash checks alone do not replace checking the proofs in Lean.

The formalization covers indices, values, intervals, matched shifts, logical origins, and the phase formula for the exact interleave tail. The fallback tail estimate above `kHashPhaseScanLimit` remains outside its scope. Agreement of descriptors, `NULL` maps, gaps, materialization, and other C++ execution paths requires separate unit and integration checks. [Integration Tests](../appendices/integration-tests.md) explains their role and distinguishes a coverage description from an execution result.
