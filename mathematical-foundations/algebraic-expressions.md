# Algebraic Expressions

The defined algebra entails the possibility of defining algebraic expressions. Typical algebraic expressions over the set of rational numbers are material covered in elementary school. Algebraic expressions in RetractorDB occur in two forms. In the field list of the SELECT command, we have the typical expressions familiar from school. In the argument list of the SELECT command's FROM clause, we have an algebraic expression built on the newly defined algebra.

This means that in the field list after the SELECT clause, the plus operator means one thing, while in the FROM clause it means something else entirely. An innocent-looking query from the definition combines two entirely different worlds and concepts: one, an algebra based on numbers; the other, based on regular time series.

Example. As an example, we present an algebraic expression built over the set of regular time series (hereafter called streams). Assume the existence of two streams: A(a<sub>1</sub> int, a<sub>2</sub> int),1 and B(b<sub>1</sub> int),½ — where,

* A denotes a stream containing, in each record, two fields of type int — a<sub>1</sub> and a<sub>2</sub> — arriving once per second, and
* B contains, in each record, a field of type int named b<sub>1</sub> arriving twice per second.

The algebraic expression C=A+B creates a data stream with fields C(a<sub>1</sub> int, a<sub>2</sub> int, b<sub>1</sub> int),½.

To interleave a data stream, sets A and B should have the same data schema. Let's assume, then, that there is a stream D(d<sub>1</sub> int),1 — arriving, like stream A, once per second.

The algebraic expression E=B#D creates the stream: E(e<sub>1</sub> int),⅓. The rate ⅓ comes from the formula (1\*½)/(1+½). You will find this formula in the definition of the interleaving operation.

For streams defined this way, the following expression is still valid:

```
F=((B#D)+A)>2
```

And such expressions may appear as valid, with respect to the developed time-series algebra, in the body of a query.

## Further examples

Continuing with the streams defined above, A(a<sub>1</sub> int, a<sub>2</sub> int),1, B(b<sub>1</sub> int),½ and D(d<sub>1</sub> int),1, and the output streams C=A+B and E=B#D — below is a further set of valid algebraic expressions. Equivalents of all these expressions appear in FROM clauses of queries in the system's integration tests, and are verified on every build of the project.

Interleaving the result of an interleave:

```
G=E#D
```

Stream E has rate ⅓, stream D has rate 1, both share the same schema with a single int field. The interleaving formula gives a rate of (⅓·1)/(⅓+1)=¼, so G(g<sub>1</sub> int),¼. The result of one operation is a fully valid stream and can be the argument of the next one.

Sum of three streams:

```
H=A+B+D
```

Summation joins tuples, so the result schema is the concatenation of the schemas, and the rate is dictated by the fastest component: H(a<sub>1</sub> int, a<sub>2</sub> int, b<sub>1</sub> int, d<sub>1</sub> int),½.

Sum with a shifted component, and a shift of an interleaving argument:

```
I=D+((A+B)>1)
J=(B>1)#D
```

Shifting a sequence does not change the stream's rate — it only changes data access by a given number of samples. Therefore I has rate min(1,½)=½, and J — just like E — has rate ⅓.

De-interleaving:

```
K=E&1
L=E%½
```

The right-hand argument of the de-interleaving operators is a rational number, not a stream. Substituting into the de-interleaving formulas: K has rate (⅓·1)/|⅓−1|=½ — left-hand de-interleaving recovers stream B from the interleave E. Similarly L has rate (⅓·½)/|⅓−½|=1 — right-hand de-interleaving recovers stream D. De-interleaving is the inverse of interleaving, just as division is the inverse of multiplication.

Difference:

```
M=C-1
```

Difference is the inverse operation to sum — it extracts, from the joined stream C, the component indicated by the rational number on the right-hand side of the operator.

Aggregation and serialization:

```
N=A@(1,4)
P=A@(1,-4)
R=A@(2,2)
S=(A@(2,2))@(1,1)
```

N creates a sliding window of width 4 shifted by one element, P — thanks to its negative width — builds the same windows mirror-imaged, R creates disjoint windows (hop equal to the width). Expression S shows that the result of an Agse operation can be the argument of another Agse operation.

All of the above forms can be combined into arbitrarily complex expressions — like F=((B#D)+A)>2 from the example above — as long as the data schemas of the arguments satisfy the requirements of the respective operations.

## Coverage of examples in integration tests

Each of the expression forms cited has a counterpart in the RetractorDB repository's integration tests (directories `test/IntegrationTest_serial` and `test/IntegrationTest_parallel`), executed on every project build:

| Expression from this chapter | Form in the test | Integration test |
|---|---|---|
| C=A+B (sum) | `s1+s2`, `core0+core1` | `IntegrationTest_serial/issue167_dedup_positive`, `IntegrationTest_serial/Data` (all-operators) |
| E=B#D (interleaving) | `core0#core1` | `IntegrationTest_serial/operations`, `IntegrationTest_serial/Data` (all-operators) |
| G=E#D (cascaded interleaving) | `(s1#s2)#s3`, `s1#s2#s3` | `IntegrationTest_serial/issue167_triarg` |
| H=A+B+D (multi-argument sum) | `s1+s2+s3`, `s1+s2+s3+s4` | `IntegrationTest_serial/issue167_triarg` |
| I=D+((A+B)>1) | `s3+((s1+s2)>1)` | `IntegrationTest_serial/issue167_dedup_cascaded` |
| J=(B>1)#D and (B#D)>1 | `(core1>1)#core2`, `(core1#core2)>1` | `IntegrationTest_parallel/subquery` |
| K=E&1, L=E%½ (de-interleaving) | `core0&1.5`, `core0%4` | `IntegrationTest_serial/Data` (all-operators) |
| M=C−1 (difference) | `core0-1/2` | `IntegrationTest_serial/Data` (all-operators) |
| shift of a sum, as in F | `(s1+s2)>1`, `(core0+core1)>5` | `IntegrationTest_serial/issue167_dedup_field_names`, `IntegrationTest_serial/issue56_timeshift` |
| N=A@(1,4), P=A@(1,−4), R=A@(2,2) | `core1@(1,4)`, `core1@(1,-4)`, `core1@(2,2)` | `IntegrationTest_serial/agse1` (further hop/width variants: `agse2`, `agse3`) |
| S=(A@(2,2))@(1,1) (cascaded Agse) | `signalText3@(1,1)` | `IntegrationTest_serial/agse1` |

The tests compare query execution results against pattern files, so the expressions above are verified not only syntactically, but also in terms of the values and rates of the resulting streams.
