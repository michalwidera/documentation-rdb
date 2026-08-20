# RetractorDB

This chapter is a map, not a catalog. Instead of listing everything ever written about streams and signals, I show five strands of peer-reviewed literature at whose intersection RetractorDB sits, and for each of them I answer three questions: what has this strand already solved, how does RetractorDB differ from it, and what does this strand **not** touch. Only by overlaying these five layers does the gap this project fills become visible.

<div class="no-print">

> **📥 Download the documentation**
>
> This documentation is compiled entirely from Markdown files. Three targets are copied. The first is the HTML page you see now, the second is the PDF file, and the third is the EPUB document for the reader. Each time the content of the GitHub repository where the Markdown files are stored changes, a process is triggered to create these three targets.
> * [retractordb.pdf](retractordb.pdf)
> * [retractordb.epub](retractordb.epub)

</div>

> **✅ Note**
>
> This system is an: Edge Signal Processing Engine. RetractorDB supports — rather than replaces — time-series databases (TSDB) and data stream management systems (DSMS): it works close to the signal source, pre-processes and filters high-frequency measurements using a declarative query language, keeps a partial, correctable record of past events and scheduled future ones in inspectable artifacts, and passes exact, deterministic results up the architecture — so that only reduced, already-processed streams reach the central architecture.


> **ℹ️ Info**
>
> Why did I place this chapter so early? Because an honest answer to the question "is this needed?" first requires showing what already exists. Most ideas in computer science have already been thought of once — reinventing the wheel wastes someone else's effort. This chapter is my attempt to prove that this particular wheel has not, in fact, been invented yet.


## Five neighboring fields

The problem RetractorDB solves does not belong entirely to any single discipline. It sits in the gap between five:

1. **Number theory** – Beatty sequences, Fraenkel's theorem, covering systems. This provides the formal foundation.
2. **Task scheduling via Beatty sequences** – the same mathematics, a different application. The closest application-level neighbor.
3. **Digital signal processing (DSP)** – nonuniform sampling and filter banks with rational coefficients. This is the DSP counterpart of the interleaving operation.
4. **Data stream management systems (DSMS)** – stream algebras and continuous-query semantics. This is the database reference point.
5. **Time-series systems (TSMS) and in-database DSP** – the narrowest, most sparsely populated niche, closest to the system's actual goal.

I discuss them in turn, from the foundation toward the application.

## Number theory: Beatty sequences and covering systems (1)

RetractorDB's entire algebra rests on the Beatty sequence and its generalization by Fraenkel to rational numbers. I cite these results in [Formal Foundations and Proofs](mathematical-foundations/formal-foundations-and-proofs.md). Here I'm interested in the broader backdrop: how this mathematics functions in the contemporary literature, and whether anyone has already applied it where I have.

Beatty sequences have a rich combinatorial literature and documented applications in aperiodic tilings (quasicrystals), periodic scheduling, computer vision (digital lines), and formal language theory [\[11\]](references.md#11). The strand is alive: Schaeffer, Shallit, and Zorcic (2024) showed that a non-homogeneous Beatty sequence is synchronizable by a finite automaton, which leads to decidability of the first-order theory of these sequences [\[12\]](references.md#12). For me, however, the most relevant work is that of Berger, Felzenbaum, and Fraenkel (1986) on disjoint covering systems based on **rational** Beatty sequences [\[13\]](references.md#13) — exactly the variant my de-interleaving is based on, and one I did not cite in the original paper.

**What this strand does not touch:** number theory studies these sequences as mathematical objects. It does not connect them to a database, to a stream-processing model, or to signal processing. It supplies bricks, not a building.

## Task scheduling via Beatty sequences (2)

This is the strand I must discuss most honestly, because it uses **the same proof machinery** as my theorems — just for a different purpose. In the periodic-scheduling problem (so-called _pinwheel scheduling_), tasks with different repeat periods are distributed so that tasks with one repeat time land in time slots belonging to the first complementary Beatty sequence, and those with the other, into the second [\[14\]](references.md#14). Recent work (2025) proves results on the Rayleigh/Beatty partition using identities on floor and ceiling functions of the type ⌈(m+l)a⌉ − ⌈ma⌉ [\[15\]](references.md#15) — almost identical, point for point, to the apparatus in my proof that [de-interleaving satisfies Fraenkel's postulates](mathematical-foundations/formal-foundations-and-proofs.md).

The conclusion, for me, is twofold. On one hand — this is independent confirmation that the approach is correct and natural; if someone else arrives, by the same road, at a working scheduling scheme, the foundation is solid. On the other — it narrows what I can call novel. "Beatty sequences for scheduling" already exists and is being actively published. Interestingly, my system uses this mathematics **internally**, precisely for task scheduling (see [Query Execution](query-execution/)) — but that's not where the original contribution lies.

**What this strand does not touch:** scheduling treats sequences as a tool for allocating time slots to processors. It doesn't build a data algebra on top of them, doesn't use them to express operations on signals, and doesn't create a query language.

## Digital signal processing: nonuniform sampling and filter banks (3)

The interleaving and de-interleaving operation is, in DSP terms, a sample-rate conversion between streams with different Δ. Here a broad, mature literature exists. The closest bridge is the work of Samadi, Ahmad, and Swamy (2004), which formulates the perfect-reconstruction condition for nonuniform filter banks based on the system's response to delayed unit-step signals [\[16\]](references.md#16) — thereby introducing step-function (and, indirectly, floor-function) machinery into the domain of multirate DSP. The broader strand is periodic-nonuniform sampling of band-limited signals [\[17\]](references.md#17), and — directly relevant — filter banks with **rational** decimation factors (Kovačević and Vetterli) [\[18\]](references.md#18).

Number-theoretic constructions even show up there: Ramanujan filter banks extract periodic components of a signal [\[19\]](references.md#19). But I have not found Beatty sequences or Fraenkel's theorem specifically in this literature — and that's part of the gap.

**What this strand does not touch:** DSP operates in the z-domain, the frequency domain, on frames and bases. It doesn't treat resampling as a declarative algebraic operator, nor does it embed it in a database system. Coefficients are sometimes rational, but the apparatus is analysis, not the number theory of set partitioning.

## Data stream management systems (DSMS) (4)

On the database side, the canon is CQL from Stanford's STREAM project (Arasu, Babu, Widom). In this model, a stream is a potentially infinite multiset of elements ⟨s, τ⟩, where s is a tuple and τ a timestamp [\[20\]](references.md#20); query semantics is built on windows and stream↔relation mappings. A second close neighbor is the temporal algebra of Krämer and Seeger (the PIPES system), providing deterministic results for continuous queries and a rich set of transformation rules underlying optimization [\[21\]](references.md#21).

This is the proper reference point for my algebra and my [expression rewrite rules](mathematical-foundations/formal-foundations-and-proofs.md). The difference, however, is fundamental and concerns the data model itself. CQL and PIPES build their semantics on the (s, τ) model — every tuple carries its own timestamp, and operators act through windows. I adopt a differential model (sₙ, Δ), with a rational, fixed value of Δ per stream, and I derive the operators that align streams with different Δ from number theory. This is not a cosmetic difference in syntax — it's a different data model, leading to a different class of operators (interleaving, de-interleaving) and a different optimization method.

In deployment terms, the relationship is complementary rather than competitive: RetractorDB acts as an edge-level pre-processing and buffering stage, whose exact, deterministic results can feed a windowed DSMS.

**What this strand does not touch:** DSMS encompass both deterministic semantics and mechanisms for scaling, windows, out-of-order handling, and state management. The cited systems do not, however, define this particular lossless partition of regular sample positions using Beatty sequences or use number theory as the semantics of resampling.

## Time-series systems (TSMS) and in-database DSP (5)

This is the narrowest niche — and the closest to RetractorDB's actual goal. The canonical survey is Jensen, Pedersen, and Thomsen's "Time Series Management Systems: A Survey" (IEEE TKDE, 2017) [\[22\]](references.md#22). The Plato system described there is the closest real "DSP inside a database": it combines an RDBMS with signal-processing methods, eliminating the need to export data to external tools like R or SPSS [\[22\]](references.md#22). The other approaches to "signals in a database" boil down to approximation and compression — wavelet, dictionary, and shape-based representations.

All of them, however, treat DSP as approximation or after-the-fact analytics. None makes signal-processing operations **exact, deterministic first-class operators** within a query algebra. This confirms that the niche is thin, and that my angle of attack — exactness over rational numbers — is distinct.

**What this strand does not touch:** TSMS optimize ingestion scale, compression, and retention. DSP is a second-class citizen in them — an analytical add-on, not the core of the semantics.

## The blank spot: where the contribution lies

The table below is a qualitative capability map, not evidence of priority or a claim that the review is complete. Within the broader stream-systems strand, it separates SDF/CSDF and synchronous languages because they are the closest systems models. “Partial” denotes a related capability, not semantic equivalence.

| Field | Beatty/Fraenkel | Lossless sample partition | Declarative dataflow | Artifacts / replay |
| --- | :---: | :---: | :---: | :---: |
| Number theory | ✔ | – | – | – |
| Scheduling (pinwheel) | ✔ | – | – | partial |
| SDF / CSDF | – | partial | ✔ | – |
| Synchronous languages / clock calculi | – | – | ✔ | – |
| Multirate DSP | – | partial | partial | – |
| DSMS (CQL, PIPES) | – | – | ✔ | partial |
| TSMS / in-database DSP | – | partial | partial | partial |
| **RetractorDB** | **✔** | **✔** | **✔** | **✔** |

The strongest neighbors are SDF/CSDF and synchronous languages and clock calculi: they already provide multirate declarative dataflow, deterministic semantics, static schedules, or buffer inference. RetractorDB's integration scope is narrower: the system combines a Beatty-defined, exactly invertible partition of sample positions with a query compiler, a sequential slot runtime, and persistent artifacts that can be inspected and replayed. This describes the system's architecture and semantics; it does not claim that the individual ingredients are new. RetractorDB does not claim hard real-time guarantees.

> **⚠️ Warning**
>
> Hence a real risk, which I point out directly: the scheduling community has been publishing this same Beatty/Fraenkel machinery in 2023–2025. The problem itself — together with the need for a declarative stream algebra and a continuous query language — was already formulated back in 2003–2005, in the context of computer-assisted fetal monitoring [\[25\]](references.md#25); I laid the "covering systems ↔ stream alignment and DSP" bridge in a 2006 publication [\[3\]](references.md#3), but in a venue with low discoverability. If this result doesn't reach well-cited circulation, the same bridge may be independently built and credited to someone else.


## Methodological caveat

This is a targeted review, not a systematic one — based on searching across five strands, not a full citation analysis. A "forward citation" review of Samadi's paper [\[16\]](references.md#16) confirms the point: according to Semantic Scholar (as of July 2026), its only recorded citations are a paper on Gabor window design, two systems-theoretic papers on multirate systems, and the 2006 bridge paper itself [\[3\]](references.md#3) — none of them uses Beatty sequences or Fraenkel's theorem. The closest use of this machinery outside number theory that I'm aware of is the construction of exponential Riesz bases from Beatty–Fraenkel sequences (Pfander, Revay, and Walnut) [\[24\]](references.md#24) — but that belongs to pure harmonic analysis and doesn't touch filter banks or sample-rate conversion. What remains for full closure is a systematic review of the scheduling strand [\[14\]](references.md#14) and of the filter-bank literature as a whole; if a use of Fraenkel's theorem in multirate DSP exists, it narrows the scope of the novelty claim and should be accounted for here.
