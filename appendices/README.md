# Appendices

The appendices contain documents not directly related to the system's construction, but which describe the motivation behind design decisions, tool documentation, and supporting material for people deploying or extending the system.

**System Origin**

A description of the historical circumstances that led to RetractorDB's creation. The starting point is the author's experience building a neonatal monitoring system in the early 2000s — running into the limitations of relational databases when recording high-granularity signals, attempts based on the stream-processing systems of the time, and the evolution toward a dedicated time-series processing engine. The chapter also explains where the name "Retractor" comes from — a reference to a group of surgical instruments that separate and join tissue structures, treated here as an analogy for operations on data streams.

Full description: [System Origin](system-origin/README.md)

**Further Development Directions**

An outline of potential extensions to the algebra underlying RQL. The main thread is the search for a generalization to complex numbers — a direct application of Gaussian integers, assuming the computational basis would be rational numbers, did not produce the expected results, due to the nature of the modulus (the modulus of a complex number with rational components is real, not rational). An alternative is **Eisenstein integers** — a threefold-symmetric counterpart to Gaussian numbers, whose modulus preserves rational properties. The chapter includes a derivation of their definition and a preliminary analysis of their applicability to time-series algebra.

Full description: [Further Development Directions](further-development-directions/README.md)

**RQL Syntax Highlighting**

RetractorDB query files (extension `.rql`) have dedicated syntax-highlighting definitions for three environments:

- **Visual Studio Code** — the `rql-vscode` extension, installed from the GitHub repository,
- **Vim** — the files `syntax/rql.vim` and `ftdetect/rql.vim`, installed via `scripts/buildrdb.sh vimsyntax` or manually into `~/.vim/`,
- **bat / batcat** — a Sublime Text 3 format definition, installed via `scripts/buildrdb.sh batsyntax`.

Each environment recognizes RQL keywords (`SELECT`, `DECLARE`, `RULE`, `STREAM`, …), data types, comments, string literals, and numeric values.

Full description: [Syntax Highlighting](syntax-highlighting/README.md)

**Command-Line Options**

Complete command-line flag documentation for all three of the system's tools:

| Tool         | Role                                                                  |
| ------------ | ----------------------------------------------------------------------- |
| `xretractor` | The main processing process: compiles RQL queries and executes the plan |
| `xqry`       | Client: queries a running `xretractor` via shared memory         |
| `xtrdb`      | Inspection tool: analyzes binary artifacts and metadata           |

Each tool is described in its own subchapter, with example invocations and explanations of the individual switches.

Full description: [Command-Line Options](command-line-options/README.md)

**Integration Tests**

A catalog of all the system's integration tests, with a description of the functionality each one verifies. Integration tests run the actual binaries (`xretractor`, `xqry`, `xtrdb`) and compare their results against patterns — unlike GTest unit tests, which test isolated library classes.

The tests are split into two sets:

- **`IntegrationTest_serial`** — require a running IPC server; run sequentially (one after another) due to a shared lock file and Boost memory segments,
- **`IntegrationTest_parallel`** — query compilation and file inspection without an IPC server; can run in parallel.

Running them: `ninja test` or `ctest -R <name> -V` in the `build/Debug/` directory.

Full description: [Integration Tests](integration-tests.md)
