# Type Promotion

What happens when we multiply data of type BYTE with data of type INTEGER? RetractorDB follows strict type-promotion rules. Multiplying a BYTE-type field by a value of a field that is of type INTEGER produces a schema field of type INTEGER. This happens at compile time.

At present, RetractorDB supports the following data types:

| Type     | Description                                   |
| -------- | --------------------------------------------- |
| BYTE     | values 0–255                                  |
| INTEGER  | 4-byte values for signed numbers              |
| UINT     | like INTEGER, for unsigned numbers            |
| RATIONAL | rational numbers                              |
| FLOAT    | floating-point numbers                        |
| DOUBLE   | double-precision floating-point numbers       |
| STRING   | character strings                             |

The STRING and RATIONAL types still need review, fixes, and test coverage. During development I focused my effort on number processing. In the future I want to add complex numbers and rational Eisenstein complex numbers to this set as well.

An example of type promotion in practice — the `scaled` query from the chapter [Underscore Symbol Processing](underscore-symbol-processing.md):

```
SELECT core0[_] * core1[_] \
STREAM scaled \
FROM core0 + core1
```

`core0` has fields BYTE and INTEGER, `core1` has fields INTEGER and FLOAT. After expanding `_`, the compiler determines the output fields' types:

| Expression          | Left type | Right type | Result type |
| ------------------- | -------- | --------- | ------------ |
| `scaled[0] * scaled[2]` | BYTE     | INTEGER   | INTEGER      |
| `scaled[1] * scaled[3]` | INTEGER  | FLOAT     | FLOAT        |
