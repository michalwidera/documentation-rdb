# Python and Jupyter

The embedded library executes RQL inside Python without a daemon. Its [API contract](../appendices/python-jupyter-api.md) covers logical time, not real-time execution. Use the separate [monitoring client](../appendices/stream-monitoring-api.md) for service streams.

## Installing a wheel

Use an explicitly supplied `.whl` file or its direct HTTPS URL. PyPI publication is a separate task; this guide assumes neither availability through `pip install retractordb` nor a macOS wheel. Linux x86_64 includes WSL2. The filename must match architecture and Python ABI: `cp312-abi3` supports CPython 3.12 and later, while cp310/cp311 target their respective versions. The build also provides for aarch64; availability and execution of each artifact require evidence on that architecture.

Keep the complete filename, SHA-256 and source SHA supplied with the wheel. Verify the checksum before installation. Run these commands in your project directory; `RDB_WHEEL` names the downloaded file:

```bash
python3.12 -m venv .venv-rdb
.venv-rdb/bin/python -m pip install 'numpy>=1.23' ipykernel
RDB_WHEEL="/path/to/retractordb-0.1.11-cp312-abi3-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl"
sha256sum "$RDB_WHEEL"
.venv-rdb/bin/python -m pip install --no-deps "$RDB_WHEEL"
.venv-rdb/bin/python -c 'import retractordb._core; print(retractordb._core.__file__)'
.venv-rdb/bin/python -m pip check
```

Alternatively, set `RDB_WHEEL` to the supplied direct HTTPS URL. Its path must preserve the original filename; signed query parameters are allowed. `--no-deps` requires NumPy to be prepared in advance and does not install or replace PyTorch. Omit signed URL secrets from reports. Importing `_core` establishes extension availability, rather than just the pure client.

Install PyTorch for your CPU/CUDA environment yourself. It is unnecessary for plan execution, NumPy or DLPack. Run the [complete API example](../appendices/python-jupyter-api.md#complete-example) in this interpreter or its kernel.

## Jupyter kernel

The kernel and extension must use compatible Python versions. You can explicitly register your environment's kernel:

```bash
.venv-rdb/bin/python -m ipykernel install --user --name retractordb-wheel --display-name 'RetractorDB wheel'
```

Select "RetractorDB wheel" in Jupyter. This registration intentionally changes user configuration; the local profile script below keeps its kernel inside the venv rather than registering it globally. The code repository's notebooks are `api/python/notebooks/j0_storage.ipynb`, `j1_engine.ipynb`, and `colab_quickstart.ipynb`.

## Google Colab

In a fresh runtime, upload `colab_quickstart.ipynb`, upload the wheel through the Files panel into `/content/`, and set the first cell's `WHEEL` to its path or direct URL. Set `SOURCE_COMMIT` to the complete SHA from the build log. The notebook installs only the wheel with `--no-deps`, compares NumPy/torch versions before and after, measures download, installation and import separately, and saves `rdb-acceptance.json`.

NumPy assertions verify the signal before and after training. Without torch, ML cells explicitly skip training; with torch they use CUDA when available or CPU. T4 uses fp16 with GradScaler; native bf16 is selected when the runtime reports support. Do not assume arbitrary GPUs have been accepted. Observe versions and restart requirements in each runtime; a local container does not establish Colab behavior. The [acceptance protocol](../appendices/notebook-acceptance.md) separates both kinds of evidence.

## Local Jupyter and PyTorch profiles

In the code repository, `scripts/jupyter-env.sh` creates persistent isolated environments for an installed Python 3.12. It needs an already-built compatible `_core` or a wheel; it does not compile the engine, install to system Python, or change `~/.local/bin` or the caller's PATH. Prepare a [separate Python build](python-build.md) for a local module.

```bash
scripts/jupyter-env.sh system
.venv-jupyter-system-cpu/bin/rdb-python -m pytest api/python/tests -ra
PYTHON="$PWD/.venv-jupyter-system-cpu/bin/rdb-python" \
  docker/wheel/notebook-smoke.sh --module-dir build/Debug-Python/python

scripts/jupyter-env.sh user
.venv-jupyter-user-cpu/bin/rdb-jupyter api/python/notebooks

scripts/jupyter-env.sh user --wheel \
  build/wheelhouse/retractordb-0.1.11-cp312-abi3-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl \
  --venv .venv-jupyter-wheel
.venv-jupyter-wheel/bin/rdb-jupyter api/python/notebooks
```

Select "RetractorDB (user, cpu)" in the user profile. `rdb-python` and the kernel use an explicit module root and verify the actual `_core` path. The module profile imports from the build without copying to site-packages; the wheel profile installs into its own venv and supplies its path to the notebook's installation cell.

`--module-dir`, `--python`, and `--venv` override module root, interpreter and environment. An existing venv must also use Python 3.12. Re-running refreshes dependencies and the kernel; use separate venvs for different modules and torch backends. Shell activation is unnecessary.

`scripts/notebook-versions.sh` defines the repeatable local profile: Python 3.12, NumPy 2.0.2, nanobind, pytest, nbclient, nbformat and ipykernel. Linux uses torch 2.11.0+cpu from the CPU index; the user profile also includes JupyterLab. These do not declare Colab's current versions. Setup checks `pip check`, `_core` provenance and DLPack sharing, measures time and venv size, and saves `requirements-resolved.txt`.

| Platform | Profile and scope |
| --- | --- |
| Linux x86_64 / WSL2 | Default CPU profile; primary verification platform |
| Linux aarch64 | Installer supports CPU; execution requires evidence on that host |
| macOS arm64, macOS 14+ | Default MPS profile, torch 2.14.1 from PyPI; local build required until a macOS wheel exists |
| Linux CUDA | Explicit `--torch cuda`, torch 2.11.0+cu128; a packaging check without a GPU does not establish GPU computation |

On macOS, launchers live in `.venv-jupyter-user-mps` and `.venv-jupyter-system-mps`. Setup checks that torch includes MPS, but requires no available MPS device. The float64 guard alone is not hardware acceptance.

The optional CUDA packaging profile downloads several GB and stays outside the default CPU profile. It needs neither a GPU nor driver and does not verify CUDA computation:

```bash
CUDA_VISIBLE_DEVICES='' scripts/jupyter-env.sh system --torch cuda
CUDA_VISIBLE_DEVICES='' .venv-jupyter-system-cuda/bin/rdb-python -m pytest api/python/tests -ra
CUDA_VISIBLE_DEVICES='' PYTHON="$PWD/.venv-jupyter-system-cuda/bin/rdb-python" \
  docker/wheel/notebook-smoke.sh --module-dir build/Debug-Python/python
```
