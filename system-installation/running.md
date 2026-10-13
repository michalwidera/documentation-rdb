# Running

Installed tools can run standalone or as a service. [Linux releases](linux-releases.md) cover installation and systemd; [xretractor options](../appendices/command-line-options/xretractor.md) cover real-time configuration, flags and plan replacement. Python `Engine` runs a [logical-time plan](../appendices/python-jupyter-api.md) without a service or bus.

## Standalone: a file until EOF

Prepare separate input and output in a Linux shell:

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

`-u` stops at EOF; `-k` skips the final keypress wait. Without `-u`, a source can wrap and the process needs stopping. The name identifies the instance on the bus; concurrent instances need distinct names and disjoint plan resources. Use `xqry --server installation-demo` while it is running; IPC cannot observe a completed run. Inspect resulting artifacts with `xtrdb` or offline Storage. The example directory remains for inspection.

## Running service

After installation with systemd support, check `systemctl status xretractor.service`. An empty startup plan means an idle instance. Deliver a plan through `xretractor new-plan.rql` or `xqry --server service --reset new-plan.rql` under the [service and replacement contract](../appendices/command-line-options/xretractor.md#service-and-plan-replacement). Environment/storage checks and refusals differ from embedding; a reset `OK` does not guarantee durable startup-plan storage.

Read service streams through `xqry` or the [monitoring client](../appendices/stream-monitoring-api.md). Do not use offline `Storage` to monitor a running service. WSL2 requires working systemd for the service variant; standalone and Engine do not require it.
