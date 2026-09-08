# Appendices

The appendices contain documents not directly related to the system's construction, but which describe the motivation behind design decisions, tool documentation, and supporting material for people deploying or extending the system.

**Production Builds and Diagnostic Variants**

A description of the production `release` safety contract and the isolated
`release-ablation` and `probe` modes. The chapter covers source-tree
cleanliness checks, explicit optimizer-switch values, separate CMake and Conan
directories, verification of the resulting binary configuration, and the
value-equivalence invariant across variants.

Full description: [Production Builds and Diagnostic Variants](production-builds-and-research-variants.md)

**Stream Monitoring API**

A versioned JSON Lines contract and optional Python and C++ libraries for observing
streams from an explicitly named instance. This chapter describes type mappings,
subscription lifecycle, timeouts, bounded buffers, error handling, and the separate
targets used to build, install, and test the API.

Full description: [Stream Monitoring API](stream-monitoring-api.md)

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

Scenarios live in the shared **`test/IntegrationTest`** tree. Tests that start a server
receive one of sixteen `RDB_NAMESPACE` namespaces and a CTest resource lock for their
directory, so most can run concurrently without stream-name, IPC, or working-file
collisions. Only scenarios that examine the production global identity remain
`RUN_SERIAL`.

Running them: `ninja test` or `ctest -R <name> -V` in the `build/Debug/` directory.

Full description: [Integration Tests](integration-tests.md)
