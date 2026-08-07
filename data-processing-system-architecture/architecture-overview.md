# General Perspective

The system is built around 3 programs available as system commands. The first is the compiler and query-plan execution engine. The second is the client for accessing current data. The third is the program that provides access to binary dumps. Their names are, in order:

* xretractor
* xqry
* xtrdb

The xretractor program creates RetractorDB's main process. The xqry program creates processes that communicate with RetractorDB. Communication happens through a shared memory area. The xtrdb program is used to analyze data and metadata stored in the database's files.

Below, Fig. 12 schematically shows RetractorDB's architecture. All currently existing components are included. The areas enclosed in boxes with headers filled with system commands correspond to the existing components. The artifact-storage area is a symbolic representation of the filesystem.

<figure><img src="../assets/schemat_architektury_retractordb.svg" alt=""><figcaption><p>Fig. 12. Data-flow diagram between RetractorDB processes</p></figcaption></figure>

In Fig. 12 we see the processes carried out by the xretractor, xtrdb, and xqry programs. The figure schematically shows how the processes in RetractorDB communicate. It shows the shared parts of the developed tools.

The xretractor process communicates with xqry processes through a shared memory area. In this memory, xretractor creates a data queue for every xqry process. Data is received by xqry processes on an ongoing basis. The job of the xqry processes is to forward the data on to other systems or processes. If an xqry process dies or is terminated, xretractor, which manages the shared area, frees the area dedicated to it within the shared region.

Besides directing data for delivery through shared memory, RetractorDB also writes data to the so-called artifact-storage area. Currently this is a directory to which the results of the stream-processing carried out according to RetractorDB's query execution plans are continuously written.

> **⚠️ Warning**
>
> The "Database" shown in the figure is not a relational database. By "database" in the figure shown, we mean a set of binary or text files managed by RetractorDB. Data is pulled from devices and written to rotating or non-rotating binary or text files. Access to this data is carried out via the xtrdb tool, or, while the system is running, via the xqry process.


The file with RQL queries and directives is given as the first argument to the command that starts the system. That argument is **optional**: invoking `xretractor` without a query file starts it in **idle mode** — the process comes up, takes the service lock, opens the IPC channel and waits, building neither a plan nor a timeline. This lets a systemd unit come up together with the operating system, before the operator supplies a query set. The exception is `--onlycompile` mode, where a missing file remains an error — there is nothing to compile.

A query set is attached later by one of two routes: the `xqry -a` command (see [Ad Hoc Queries](../query-execution/ad-hoc-queries.md), restricted to `SELECT`), or by handing the service a query file and restarting it — the latter being the only route that brings in `RULE`, `STORAGE`, and `SUBSTRAT` directives.

> **_NOTE:_** Idle mode is covered by the `service_idle` test (variants using the `--service` flag and the `XRETRACTOR_SERVICE` environment variable).
