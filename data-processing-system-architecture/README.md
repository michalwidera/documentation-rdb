# System Architecture

The construction of the data-processing system is a strictly technical chapter. Here I present how the system was designed and built, and where and how its functionality is currently laid out.

RetractorDB was implemented in C++ under Linux. The source code goes through continuous integration and testing on GitHub, backed by CircleCI. The code is run and developed locally on the Linux WSL2 platform. I abandoned development and implementation of the system under Windows. In the early phase I kept that option open, and I may return to it in the future. However, maintaining too many development platforms significantly slows down rapid prototyping and system development. I still keep and maintain the system's functionality on the Linux ARM platform. The code is compiled and tested on ARM and x86-64 architecture machines running in CircleCI's resources. Raspberry Pi is one of the intended production platforms for RetractorDB, aimed at Edge IoT needs.

The build uses Conan 2, CMake, and Ninja. Tool preparation, source builds, and release-package installation are described in [Installation Process](../appendices/installation-process.md). Linux remains the general deployment contract of this manual; the Apple port is solely for development and testing, with its limitations covered in a separate section of that appendix.

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

- **[Data Storage Format](data-storage-format/readme.md)**

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
