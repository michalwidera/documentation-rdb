# System Architecture

This chapter describes RetractorDB's components, their responsibilities, and the flow of data and control. It starts with the cooperation between `xretractor`, `xqry`, and `xtrdb`, then covers artifact formats and query-plan execution.

The system is implemented in C++. Its deployment platform is Linux on x86-64 and ARM64, including edge devices such as Raspberry Pi. Development and testing also cover Linux in WSL2 and the macOS development port. A native Windows version is not currently maintained. The source code is hosted on GitHub, and the continuous integration configuration uses CircleCI.

The build uses Conan 2, CMake, and Ninja. Tool preparation, source builds, and release-package installation are described in [System Installation](../system-installation/). The limitations of the Apple port are covered in [building from source](../system-installation/source-build.md#apple-development-environment).

## Overview of topics covered in this chapter

The chapter is built in layers - from the general view down to implementation detail.

<div class="timeline">

- **[General Perspective](architecture-overview.md)**

  The system as a trio of cooperating programs: `xretractor` as the process executing a query plan, `xqry` as the multi-instance client for current data, and `xtrdb` as the binary-file inspection tool. Several named `xretractor` processes can run on one host, each with its own Boost IPC area. The diagram in Fig. 12 shows component boundaries for one such instance.

- **[Multiple Instances and the Bus](multiple-instances-and-bus.md)**

  Instance names, separation of IPC objects, the `xrdbbus` registry, global protection of stream and storage-file names, and automatic routing rules for `xqry` commands. This section also describes the stable `service` identity, complete plan replacement with `xqry --reset`, and the modes shown by `xqry --bus`.

- **[Data and Control Flow](data-and-control-flow.md)**

  Which data paths are always active (data arrival → xretractor → artifacts), and which are optional or diagnostic. The graceful-shutdown mechanism is also described - xretractor reacts to `SIGINT`, `SIGTERM`, and `SIGHUP` signals by finishing the current cycle without risking file corruption.

- **[Artifacts, Substrates, and Ephemerides](artifacts-substrates-ephemerides.md)**

  The system's key taxonomic split. Each stream type has a different purpose and a different storage strategy: artifacts are materialized on disk as a durable result, substrates are intermediate streams necessary during computation, and ephemerides are ephemeral data sources that cannot, or need not, be stored.

- **[Data Storage Format](data-storage-format/)**

  The four-file structure of an artifact: a binary data file (fixed-length records, no header), a `.desc` descriptor describing the record schema in ANTLR4 grammar, a `.meta` metadata file with an index of null values and transmission gaps (RLE encoding), and an optional `.shadow` file for non-destructive modification of historical records. The descriptor determines the storage strategy via the `TYPE` field.

- **[Compilation and Plan Construction](compilation-and-plan-construction.md)**

  The process of turning an `.rql` file into a ready-to-run query execution plan. The `-c` flag runs compile-only mode without execution; combined with `-d -f -s` it generates DOT output, which `graphviz` turns into a data-flow graph. The graph shows two domains: the arithmetic-expression stack (PUSH, ADD, etc.) and the stream algebra. The full set of compile-mode and execution-mode flags is described.

- **[Data Processing and Distribution](data-processing-and-distribution.md)**

  A complete walkthrough: from preparing a data file, through running `xretractor`, through viewing streaming statistics (`xqry -d`), to live visualization in gnuplot (`xqry -s str1 -p 50,50 | gnuplot`) and network transmission via `nc`. The example combines two sources - a text file and `/dev/urandom` - illustrating how the `+` operator in the FROM clause performs algebraic stream joining.

- **[Artifact Analysis](artifact-analysis.md)**

  The `xtrdb` tool - an interactive binary-file inspector modeled after the dbase style. The `.open`, `.desc`, `.list`, `.rlist`, and `.meta` commands let you browse the contents of artifacts without knowing the binary format. The tool is also used to verify determinism: the same input data should always produce identical results.

</div>

***

Three commands are enough to run a complete pipeline:

```bash
xretractor -c query.rql          # verify the query file's correctness
xretractor query.rql             # start processing
xqry -s <stream>                 # read current data
```

A fourth element - `xtrdb` - comes into play for diagnostics and testing, not in a typical production workflow.
