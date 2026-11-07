# Running

Installed tools can run standalone or as a service. [Linux releases](linux-releases.md) cover installation and systemd; [xretractor options](../appendices/command-line-options/xretractor.md) cover real-time configuration, flags and plan replacement. Python `Engine` runs a [logical-time plan](../appendices/python-jupyter-api.md) without a service or bus.

## Standalone: a file until EOF

This example reads eight integers, multiplies each by two, and stores the `dst` stream. After [installing the tools](linux-releases.md), run the following commands in the same Linux shell:

```bash
rdb_demo_dir=$(mktemp -d)
mkdir "$rdb_demo_dir/results"
printf '10\n20\n30\n40\n50\n60\n70\n80\n' > "$rdb_demo_dir/input.txt"
cat > "$rdb_demo_dir/plan.rql" <<EOF
STORAGE '$rdb_demo_dir/results'
DECLARE a INTEGER STREAM src, 1/2 TEXTFILE '$rdb_demo_dir/input.txt'
SELECT a*2 STREAM dst FROM src
EOF
xretractor "$rdb_demo_dir/plan.rql" --name installation-demo -u -k
```

`-u` stops at EOF; `-k` skips the final keypress wait. Without `-u`, a source can wrap and the process needs stopping. The interval `1/2` means one sample every half second. Repeating the whole example creates a new directory with `mktemp`, keeping the results of previous runs separate.

After `xretractor` exits, read the artifact in the same shell where you set `rdb_demo_dir`:

```bash
xtrdb --noprompt <<EOF
storage $rdb_demo_dir/results
open dst
size
list 8
quit
EOF
```

Expected output:

```text
8 Record(s)
4 Byte(s) per record.
{ dst_0:20 }
{ dst_0:40 }
{ dst_0:60 }
{ dst_0:80 }
{ dst_0:100 }
{ dst_0:120 }
{ dst_0:140 }
{ dst_0:160 }
```

`size` confirms the record count and record size; `list 8` shows the values in storage order. The compiler assigned the field name `dst_0` to the expression `a*2`. The file `results/dst` contains binary data; `results/dst.desc` describes its `INTEGER` field. Use `xtrdb` or [offline Storage](../appendices/python-jupyter-api.md) to interpret the data with its descriptor and metadata.

The name `installation-demo` identifies the instance on the bus; concurrent instances need distinct names and disjoint plan resources. In batch or interactive mode, `xtrdb` requires the instances detected by its [lock and bus checks](../appendices/command-line-options/xtrdb.md) to have stopped. If it refuses to start, wait for those instances to finish. Observe a running engine with `xqry --server installation-demo`; after the process exits, its files remain available, but its IPC stream does not.

If the result differs from the output shown, keep the complete `xretractor` and `xtrdb` diagnostics and the example directory. Check [Runtime errors](../query-execution/runtime-errors.md); an `xtrdb` exit code of zero alone does not confirm that every command succeeded. The directory named by `rdb_demo_dir` remains available for further inspection.

## Running service

After installation with systemd support, check `systemctl status xretractor.service`. An empty startup plan means an idle instance. Deliver a plan through `xretractor new-plan.rql` or `xqry --server service --reset new-plan.rql` under the [service and replacement contract](../appendices/command-line-options/xretractor.md#service-and-plan-replacement). Environment/storage checks and refusals differ from embedding; a reset `OK` does not guarantee durable startup-plan storage.

Read service streams through `xqry` or the [monitoring client](../appendices/stream-monitoring-api.md). Do not use offline `Storage` to monitor a running service. WSL2 requires working systemd for the service variant; standalone and Engine do not require it.
