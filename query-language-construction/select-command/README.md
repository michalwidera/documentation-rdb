# SELECT Command

Every SELECT command in RetractorDB creates a continuous query. These queries run from the moment they appear in the system until the system shuts down.

The syntax of the SELECT command is as follows:

```
SELECT algebraic_expression [, algebraic_expression] 
STREAM output_stream_name
FROM stream_algebraic_expression 
[FILE 'artifact_file_name'] 
[RETENTION capacity [segments]]
[VOLATILE]
[STORAGE profile]
```

![SELECT command syntax diagram](../../assets/railroad-select.svg)

_Fig. 4. SELECT command syntax diagram_

The railroad diagram in Fig. 4 was generated from the `select_statement` rule in the system's ANTLR4 grammar (`RQL.g4`). The diagram is read by following the lines from left to right: rounded green boxes are keywords and symbols entered literally, rectangles are values supplied by the user. The branch after the word SELECT shows that the field list is either an asterisk (the full record) or one or more expressions separated by commas (a loop looping back through a comma). Tracks bypassing the FILE, RETENTION (with an optional second parameter — the number of segments), VOLATILE, and STORAGE clauses mean each of them is optional.

Readers familiar with SQL will immediately notice that the command shown above differs significantly from what they know from relational databases.

The first difference, beyond syntax, is that once entered into the system, these commands run until the system shuts down. Every SELECT command is a continuous query. The STREAM clause requires the author to give every query a unique name. While the algebraic expressions in the SELECT clause's field list don't differ from the form familiar from relational systems, the stream algebraic expression must satisfy the conditions presented in the previous chapter on algebraic expressions. The optional FILE and RETENTION clauses provide processes for directing results and managing their retention. Old, segmented output files can be deleted on an ongoing basis, keeping room in the system for new data in continuous motion.

An example of a query creating a new data stream might be the following RQL command.

```
SELECT str1[0]*10 + str1[1]*10, str1[2] \
STREAM str1 \
FROM A+B
```

A query built this way assumes that someone has declared streams A and B. This could have been done with the DECLARE keyword or with another SELECT command. Based solely on the line containing the query, we cannot tell how fast the data of stream str1 arrives. This information is computed at compile time, based on streams A and B and the algebraic expression in the FROM clause.

> **_NOTE:_** The functionality described here is covered by the tests: `simple`, `Pattern2`, described in the appendix [Integration Tests](../../appendices/integration-tests.md).

The VOLATILE clause creates an ephemeral form of the query. A query with this clause holds only a single record in memory — only the descriptor describing the data structure appears on disk.

The STORAGE clause allows choosing how the artifacts created are managed and stored. The full table of types, with a description of each, is in the chapter [Storage Types](storage-types.md).

## FROM clause operators

The stream algebraic expression in the `FROM` clause can include:

| Operator      | Syntax                                  | Description                                                                                                       |
| ------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Sum           | `A + B`                                  | Joins two streams — see [Summation Sequencing](summation-sequencing.md)     |
| Interleaving  | `A # B`                                  | Interleaving of two streams — see [Interleaving Sequencing](interleaving-sequencing.md)  |
| Shift         | `A > N`                                  | Shifts the read window by N samples                                                                                |
| AGSE window   | `A @ (k, w)`                             | Sliding data window — see [AGSE Sliding Data Window](../../query-execution/agse-sliding-window/) |
| Aggregate     | `A.min` / `A.max` / `A.avg` / `A.sumc`   | Reduces a multi-field record to a single value — see [Aggregate Operators](aggregate-operators.md)     |

> **⚠️ Warning** After an interleave `A#B`, do not refer to its components as `A[0]`, `A.field`, `A[_]`, or `A.*`. An interleave has one shared schema; use the output stream name or recover a component with `&`/`%`. See [Aliasing](../../query-compilation/aliasing.md) for details.

> **_NOTE:_** The shift operator `A > N` is covered by the test: `issue56_timeshift`, described in the appendix [Integration Tests](../../appendices/integration-tests.md).

> **_NOTE:_** Null-value propagation through SELECT expressions is covered by the test: `issue121_null_propagation`, described in the appendix [Integration Tests](../../appendices/integration-tests.md).
