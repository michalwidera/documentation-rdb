# Summary

The regular time-series model assigns each stream an ordered sequence of records and a fixed rational interval. Operators describe transformations of values, schemas, and sample positions. Beatty sequences and Fraenkel's theorem provide the basis for showing that interleaving and de-interleaving partition and recover sample positions without loss.

The Python prototypes described in [Model Implementation](model-implementation.md) support checking examples and searching for counterexamples. A finite numerical experiment does not prove a theorem about infinite streams. Mathematical arguments are presented in [Formal Foundations and Proofs](formal-foundations-and-proofs.md); the [connection between proofs and the implementation](formal-foundations-and-proofs.md#connecting-proofs-to-the-implementation) describes the Lean formalization and its links to C++ tests.

Exact index mappings require rational arithmetic until an integer index is determined by floor or ceiling. A floating-point approximation can select a different sample at an interval boundary. The code must also check the range of its numeric types.

Causal execution distinguishes logical origin, startup tail, and history capacity. An optimization rule may preserve records and their indices while reducing the wait for the result. [Tails, Logical Origins and Operator Observability](operator-tails-and-observability.md) explains these boundaries.

These foundations support the interpretation of [RQL operators](../query-language-construction/) and [compilation passes](../query-compilation/compilation-passes.md). The [short example](../system-installation/running.md#standalone-a-file-until-eof) is sufficient for a first run; the proofs are primarily useful when analyzing semantics or changing the optimizer. Publication [\[3\]](../references.md#3) presents the historical derivation of the method, whose background is covering-system theory [\[4\]](../references.md#4).

