# Algebra of Regular Time Series

Algebra — understood as a construct consisting of a defined set and defined operations on it — forms the basis for the declarative query language developed here. Throughout the rest of this work, when referring to "the Algebra" (without a further qualifier) I mean the Algebra of regular time series. When I want to refer to Relational Algebra, I will state the qualifier explicitly.

I proposed \[[3](../references.md#3)] the following definition of a regular time series (the so-called data model), along with the following operations and definitions.

> **✅ Note**
>
> By a data stream we understand an ordered pair S := (s<sub>n</sub>,∆) — where the first element is an ordered series of data and the second, denoted by the symbol delta, is the regular time interval between consecutive elements of the series.


We adopt a fixed indexing convention: stream indices run from zero, and element s<sub>n</sub> carries an implicit, default timestamp of (n+1)·∆. In other words — the first element of the stream appears after a full interval ∆ has elapsed since the stream's creation. The timestamp is not carried within the tuple; it is derived from the position n and the rate ∆. It is precisely this differential data model that distinguishes the system from classical DSMS, where a stream is a multiset of pairs ⟨s,τ⟩ with a timestamp attached to every tuple.

A data series defined this way is referred to in the system as a data stream. Such a regularly flowing set of data passing through the system, usually described by a data schema, contains fields of various types. Each reading occurs at an equal time interval between consecutive measurements. This construction resembles a digital signal more than an irregular data stream — however, referring to it as a "stream" throughout the rest of the research will prove justified.

> **ℹ️ Info**
>
> Note:\
> The terms "stream" and "time series" are used interchangeably in this work and mean the same thing.\
> Formally, in the scientific literature a stream is denoted as a set of pairs (a,t) — where a denotes a tuple, and t denotes its moment of registration or occurrence.\
> A stream allows tuples whose time t coincides for different tuples. In the case of a time series, we distinguish two types of series — regular and irregular.\
> \- For irregular series — a series is a sequence of tuples ordered in time — {a<sub>t</sub>,t<sub>n</sub>}, where the time t<sub>n</sub> is unique in the set for each tuple.\
> \- A regular time series, on the other hand, can be described by a sequence of tuples and a regular time interval between their occurrences — ({a<sub>t</sub>},D) — and it is this latter definition that forms the basis for further operations in the system developed here.


The operations that can be performed on such a data set are defined as follows:

* interleaving and de-interleaving
* sum and difference
* sequence shift
* aggregation and serialization

The interleaving operation involves two different data streams.

We define it as follows:

\\[
c_{n}=\left\\{ 
\begin{array}{cc}
b_{n-\left\lfloor n z \right\rfloor } & \left\lfloor n z
\right\rfloor =\left\lfloor \left( n+1\right) z \right\rfloor \\\\ 
a_{\left\lfloor n z \right\rfloor } & \left\lfloor n z \right\rfloor
\neq \left\lfloor \left( n+1\right) z \right\rfloor%
\end{array}%
\right. , z =\frac{\Delta _{b}}{\Delta _{a}+\Delta _{b}},\Delta _{c}=%
\frac{\Delta _{a}\Delta _{b}}{\Delta _{a}+\Delta _{b}}
\\]

The arguments of the interleaving operation are two data streams A and B, each with its own data arrival rate. The result is an output stream C — with a new rate, different from the two source rates, determined by the formula above.

We denote the operation with the symbol #.

We define the de-interleaving operation by means of two operations.

1\. Left-hand de-interleaving, producing stream A in the form:

\\[
a_{n} = c_{n+ \left\lceil  \frac{(n+1)\Delta _{a}}{\Delta _{b}} \right\rceil },\ \Delta _{a}=\frac{\Delta _{c}\Delta _{b}}{\left\vert \Delta _{c}-\Delta _{b}\right\vert }
\\]

2. Right-hand de-interleaving, producing stream B in the form:

\\[
b_{n} = c_{n+\left\lfloor \frac{n\Delta_{b}}{\Delta_{a}}\right\rfloor},\ \Delta_{b}=\frac{\Delta_{c}\Delta_{a}}{\left\vert \Delta_{c}-\Delta_{a}\right\vert }
\\]

We denote de-interleaving operations 1 and 2 with the symbols & and %.

The argument of the de-interleaving operation is an interleaved data stream together with a rational number specifying the arrival rate of the stream being extracted. The result of the operation is a data stream with the rate determined by the formula above.

The interleaving and de-interleaving operations are complementary. This means they resemble multiplication and division on the set of natural numbers. Multiplication yields a single result, whereas division sometimes leaves a remainder; what matters is also what we divide by, and in what order.

I defined the sum operation as follows:

\\[
c_{n}=\left\\{ 
\begin{array}{cc}
a_{n}|b_{ \left\lfloor  \frac{n\Delta_{a}}{\Delta_{b}} \right\rfloor }  & \Delta_{a}\leq \Delta_{b} \\\\ 
a_{ \left\lfloor  \frac {n\Delta_{b}}{\Delta_{a}} \right\rfloor }|b_{n} & \Delta_{a}>\Delta_{b}
\end{array}
\right. ,\Delta_{c}=\min \left( \Delta_{a},\Delta_{b}\right)
\\]

The faster stream dictates the rate of the result: each of its elements is joined (the symbol | denotes tuple concatenation) with the element occupying the co-indexed slot of the slower stream.

The difference, on the other hand, is described by the formula:

\\[
a_{n}=\left\\{ 
\begin{array}{cc}
c_{n} & \Delta_{b}\geqslant \Delta_{a} \\\\ 
c_{\left\lceil \frac{n\Delta_{a}}{\Delta_{b}}\right\rceil } & \Delta_{b}<\Delta_{a}
\end{array}
\right.
\\]

We denote these operations with the symbols + and -.

Causal execution augments the mathematical stream S = (s<sub>n</sub>, ∆)
with a **logical origin** O<sub>S</sub> ∈ ℕ and a **startup tail**
W<sub>S</sub> ∈ ℕ. The logical origin is the index of the first record that
exists at all; the tail is the number of subsequent slots for which an existing
record is not yet ready. Neither kind of slot is a record: the engine inserts
neither zeros nor all-null placeholders.

\\[
\widehat{S} := \left((s_n,\Delta),O_S,W_S\right)
\\]

We define the shift as a read of an older index: output record \(n\) carries
the contents of producer record \(n-m\). In the causal realization:

\\[
O_{\tau_m(S)}=O_S+m,
\qquad
W_{\tau_m(S)}=\max(0,W_S-m),
\qquad m\in\mathbb{N}
\\]

A shift neither discards source elements nor creates a prefix. It moves delay
into the logical origin, while reading an older record can absorb part of the
producer's tail. The compiler reports both quantities as `origin=` and `tail=`.
The runtime emits no records in any silent slot, of which there are
`origin + tail`. Details:
[Tails, logical origins and operator
observability](operator-tails-and-observability.md).


I denote the shift operation with the symbol >.

The last operation within the defined algebra is the aggregation and serialization operation — abbreviated as Agse. Although it may look like two separate operations, I have defined a two-argument operator implementing the logic of a sliding data window. The first argument is the window's hop, the second is its width. The hop is a natural number specifying by how much the sliding data window must be shifted over the stream. We assume that the source data stream is split with respect to the data schema, which modifies its arrival rate. The window width is an integer, non-zero. Negative width values reverse the order in which the resulting elements are created, mirror-image fashion. Positive values preserve the sequential character of the sliding data windows created.

I denote the Agse operation with the symbol @.

To summarize, the algebra underlying the declarative query language is as follows:

\\[
A_{rql}::=((s_n,\Delta_s), (\\#,\\&,\\%,+,-,>,@))
\\]

where the first element of the pair defining the algebra is the data model (s\_n — the data series, ∆\_s — its regular time interval), and the second is the set of operations formally defined on this data model.
