# Notebook and Colab Acceptance

## Notebooks and their smoke test

C5 (#493) adapts three notebooks from `feature/jupyter-integration` to the current RQL syntax and exception hierarchy ([errors](python-jupyter-api.md#errors)). All committed cell outputs are empty.

| Notebook in `api/python/notebooks/` | Flow |
|---|---|
| `j0_storage.ipynb` | descriptor, copied storage, NULL values, negative indexing and `CorruptDescriptor` with a usable kernel afterwards |
| `j1_engine.ipynb` | `TEXTFILE`, compile/step/run, records, NumPy/DLPack windows, plan refusals and recompilation |
| `colab_quickstart.ipynb` | wheel install, noisy signal from `TEXTFILE`, `AVG(v:100)`, windows and a PyTorch training loop |

The Colab notebook asserts the moving average against NumPy before importing PyTorch, and again after training. Without torch it still checks the signal and windows, then records that ML was skipped. With torch it trains on CUDA when available, otherwise CPU. T4 uses fp16 and GradScaler; GPUs with native bf16 support, such as L4/A100, use bf16. CUDA epoch losses are checked against a CPU model with the same initialization and batches (`rtol=0.05`, `atol=0.002`). The notebook uses the existing `StreamDataset` API with `num_workers=0`.

The first cell accepts `WHEEL` as a local path/glob or a direct HTTPS wheel URL, and `SOURCE_COMMIT` as the full source SHA from the wheel build log. Upload a wheel through Colab's Files panel, or edit those two values. The smoke script supplies `RDB_WHEEL` and `RDB_SOURCE_COMMIT`. Installation uses the kernel's interpreter and `--no-deps`; before/after NumPy and PyTorch versions must match. Installation, download (if any) and import have separate timers. No elapsed-time threshold is a pass/fail condition. The final cell writes `rdb-acceptance.json`.

For local work, `RDB_PYTHON_MODULE_DIR` selects the built package root ([Python build](../system-installation/python-build.md)) in all three notebooks; the interpreter must match the extension. Without it, `j0` and `j1` take the first `build/*/python` with an extension in sorted order. Open them from `api/python/notebooks`, or set `RDB_REPO_DIR` to the checkout root. The smoke script sets this variable even in a container with a read-only checkout. `j0` copies only data, descriptor and metadata fixtures, omitting the shadow update that would replace the first record.

`docker/wheel/notebook-smoke.sh` executes all three notebooks with `nbclient`, each in a separate kernel registered for the selected interpreter. It validates their JSON, rejects deprecated RQL forms, fails on cell errors and checks the selected `_core` path in every notebook. `pip freeze --all` must change only by adding `retractordb`. Results include Python/NumPy/PyTorch versions, wheel filename, source SHA (supplied from the build log), wheel SHA-256, installation/import times, cell times, NumPy checks and epoch measurements. Windows/s and mean step time include the DataLoader, device transfer and optimizer; engine advancement and CPU-reference training are timed separately. The first epoch includes warm-up. These measurements describe this demonstration, not general engine performance.

The wheel profile creates a clean Python 3.12 venv using the versions in `scripts/notebook-versions.sh`. The default torch is the CPU build. These fixed local dependencies do not declare Colab's current runtime versions. An explicit `--without-torch` profile omits torch and checks that ML was skipped successfully. Use separate output directories; executed notebooks and `acceptance.json` remain there after the temporary venv is removed. Without `--output-dir`, the script prints a retained temporary results directory.

### Manual release check for J5

Run this step after building the current wheel ([wheel build](../system-installation/python-build.md)), before handing it to a Colab user or distributing it. Both installed-wheel profiles must pass; build-module smoke alone does not satisfy the release check. Keep the wheel build log with the report so its source SHA is traceable. The build must be from the named commit; any uncommitted changes affecting the wheel must be recorded and rebuilt after review/commit before release.

```bash
# Use the full SHA recorded in the wheel build log, not a guess from an old wheel.
SOURCE_COMMIT="paste-full-source-SHA-from-build-log"
mkdir -p build/notebook-results/with-torch build/notebook-results/without-torch

docker run --rm -v "$PWD:/src:ro" -v "$PWD/build/notebook-results/with-torch:/results" \
  python:3.12-slim bash /src/docker/wheel/notebook-smoke.sh \
  --source-commit "$SOURCE_COMMIT" --output-dir /results

docker run --rm -v "$PWD:/src:ro" -v "$PWD/build/notebook-results/without-torch:/results" \
  python:3.12-slim bash /src/docker/wheel/notebook-smoke.sh \
  --source-commit "$SOURCE_COMMIT" --without-torch --output-dir /results
```

With no wheel argument, exactly one host-architecture cp312-abi3 wheel is required in `build/wheelhouse/`. Pass a file or HTTPS URL explicitly to select another. `PYTHON` selects another Python 3.12 executable. `RDB_TORCH_INDEX` overrides the CPU index; `RDB_TORCH_INDEX=` uses PyPI to resolve the CPU wheel version.

For a build-module check, use an existing matching interpreter with NumPy, `nbclient`, `nbformat` and `ipykernel`, plus torch unless `--without-torch` is set:

```bash
PYTHON="$PWD/.venv-jupyter-system-cpu/bin/rdb-python" \
  docker/wheel/notebook-smoke.sh --module-dir build/Debug-Python/python \
  --output-dir build/notebook-results/local-module
```

This profile installs nothing and has no wheel installation timing. Real Colab CPU/GPU acceptance is a separate human run under [the protocol below](#real-colab-cpu-then-gpu). Report its date, runtime and restart outcome separately from the container results. PyPI publication (#447), DeviceWindowLoader (#468) and MPS acceptance are not prerequisites of #448. Automated release CI remains a separate task.

## Container and Google Colab acceptance

Issue #448 accepts a ready C4 wheel (#492) from a file or direct HTTPS URL. PyPI publication, DeviceWindowLoader and MPS acceptance are separate work. A container run is evidence for the installed wheel; acceptance in real Colab requires its own CPU and GPU runs by a human. No Colab result is claimed by this protocol.

## Prepare the artifact

1. Build the Linux x86_64 wheel from the intended source revision using `docker/wheel/build-wheels.sh x86_64`. Keep its full source SHA and build log. Record any uncommitted changes that affect the wheel; rebuild from the reviewed commit before distribution. Use the repaired cp312-abi3 wheel for Python 3.12+.
2. Record its filename and `sha256sum build/wheelhouse/<wheel-name>.whl`. Use that same wheel for the container and Colab acceptance, not an older file with the same version and filename.
3. Run both installed-wheel container profiles from [the manual release check](#manual-release-check-for-j5). Preserve each `acceptance.json` and the three executed notebooks. Require `notebook-smoke: OK - 3/3 notebooks`; the profile without torch must record `training.status = skipped` and successful NumPy assertions. The default profile must record successful CPU training. Compare wheel SHA-256 with step 2.

## Real Colab: CPU, then GPU

Perform each run in a fresh runtime. A local notebook execution or a container named after Colab does not complete this step.

1. Upload `api/python/notebooks/colab_quickstart.ipynb` through Colab's notebook upload dialog. Use the notebook from the reviewed change; the GitHub copy can differ before the pull request is merged.
2. Select a CPU runtime for the first run. Upload the wheel through the Files panel to `/content/`, or set `WHEEL` in the first code cell to a direct HTTPS URL. The URL must contain the original wheel filename in its path; signed query strings are allowed. Set `SOURCE_COMMIT` to the full SHA recorded by the build.
3. Run all cells without installing/replacing NumPy or torch manually. The notebook installs only `retractordb` with `--no-deps`. Save the first cell's before/after versions, separate download/install/import times and `_core` path. Compare the reported wheel SHA-256 with the prepared artifact.
4. Require both NumPy assertions and the training cell to complete. A real Colab runtime with torch must train; an unexpected ML skip is not CPU/GPU acceptance. The notebook's optional no-torch path is covered separately by the container.
5. Download `rdb-acceptance.json` and the executed notebook. Record the Colab runtime version/date, CPU or GPU selection and whether Colab actually required a restart. `restart_performed=false` describes the uninterrupted notebook execution; `restart_required=null` intentionally needs human observation. Do not convert that unknown field to a proven no-restart result without observing the run. If a restart is required, preserve the pre-restart output and its reason, then record the completed run after restarting separately.
6. Repeat in a fresh GPU runtime (for example T4). Require `training.device = cuda`, the actual GPU name, epoch throughput/step times and CPU-reference loss agreement. A CPU fallback is not GPU acceptance. T4 should report `torch.float16` with GradScaler enabled; L4/A100 should report native `torch.bfloat16` without fp16 scaling. Record what the assigned runtime actually provides, including torch and CUDA versions.

The model receives copied CPU windows from `StreamDataset`, with `num_workers=0`. CUDA is a separate device transfer. The implementation follows [PyTorch's AMP API](https://docs.pytorch.org/docs/stable/amp.html), with fp16 gradient scaling and bf16 when native support is reported. Epoch timing uses [CUDA synchronization](https://docs.pytorch.org/docs/stable/generated/torch.cuda.synchronize.html).

Windows/s = processed windows / training-loop seconds. Mean step time = that elapsed time / batch count. Both include loading, transfers and optimization; engine advancement and CPU-reference training are reported separately. The first epoch includes warm-up. Record all epochs; do not report the fastest alone as the result. This small model is a demonstration, not a general engine benchmark. CUDA and CPU loss comparison uses the same initialization, data order and SGD parameters, with `rtol=0.05, atol=0.002`. An assertion failure remains a failed run.

Approximately 20 seconds is a roadmap reference, not a closure threshold. Record conditions: upload versus URL, download time, cold/warm runtime, Python version, CPU/GPU type and whether package caches were already populated. Compare times only under comparable conditions; container installation does not measure Colab.

## Result to record in #448

Keep container and Colab results separate. Attach the build log and local result artifacts, then fill this template with observed values. Posting the comment, commit, push and opening a pull request require separate human authorization.

| Field | Container with torch | Container without torch | Colab CPU | Colab GPU |
|---|---|---|---|---|
| Status (not run / passed / failed) | not run | not run | not run | not run |
| Date and runtime version | | | | |
| Wheel filename / source commit / SHA-256 | | | | |
| Python / NumPy / torch / CUDA | | | | |
| Wheel source (file or URL; omit signed URL secrets) | | | | |
| Download / install / import seconds | | | | |
| NumPy/torch before = after | | | | |
| NumPy assertions | | | | |
| Training device / precision / GradScaler | | skipped | | |
| Epoch windows/s and mean step ms | | skipped | | |
| CPU-reference loss agreement (GPU only) | n/a | n/a | n/a | |
| Restart required / performed (human observation) | n/a | n/a | | |
| Report and executed notebook location | | | | |

Do not close #448 until the required container and real Colab results are recorded, and the reviewed change reaches `dev/445-jupyter-epic` through a pull request. The protocol itself and a green local build-module smoke do not meet those criteria.
