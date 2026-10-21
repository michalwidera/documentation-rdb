# Python and Jupyter

The embedded library executes RQL inside Python without a daemon. Its [API contract](../appendices/python-jupyter-api.md) covers logical time, not real-time execution. Use the separate [monitoring client](../appendices/stream-monitoring-api.md) for service streams.

## Installing from PyPI

The [`retractordb` package is published on PyPI](https://pypi.org/project/retractordb/). Release [v0.1.12](https://github.com/michalwidera/retractordb/releases/tag/v0.1.12) provides prebuilt Python wheels on both PyPI and GitHub Releases. `pip install retractordb` installs the package with the embedded `retractordb._core` library; no local engine compilation or running service is required. The [project website](https://retractordb.com/) introduces RetractorDB, while the [system installer](https://retractordb.com/install/) installs the separate CLI programs and service.

The following example pins version `0.1.12` and creates an environment in your project directory. `--only-binary=retractordb` requires a prebuilt wheel instead of attempting to build the engine from source:

```bash
python3.12 -m venv .venv-rdb
.venv-rdb/bin/python -m pip install --upgrade pip
.venv-rdb/bin/python -m pip install --only-binary=retractordb 'retractordb==0.1.12' jupyterlab ipykernel
.venv-rdb/bin/python -c 'import retractordb._core; print(retractordb._core.__file__)'
.venv-rdb/bin/python -m pip check
```

`pip` selects a wheel matching your interpreter and platform and installs NumPy (`numpy>=1.23`). PyTorch is optional and is not installed by default. Importing `_core` establishes extension availability, rather than just the pure monitoring client.

Release `0.1.12` publishes six wheels:

| Platform | Minimum glibc | CPython variants |
| --- | --- | --- |
| Linux x86_64, including WSL2 | 2.27 | 3.10 (`cp310-cp310`), 3.11 (`cp311-cp311`), 3.12+ (`cp312-abi3`) |
| Linux aarch64 / ARM64 | 2.26 | 3.10 (`cp310-cp310`), 3.11 (`cp311-cp311`), 3.12+ (`cp312-abi3`) |

The `abi3` wheels target CPython 3.12 and later with the standard GIL. For CPython 3.10 or 3.11, replace `python3.12` with the appropriate interpreter; the local profiles below still require 3.12. This release has no macOS, native Windows or musllinux wheels. Prepare a [local build](python-build.md) on macOS, or use Linux under WSL2 on Windows. ARM64 wheel availability does not establish execution on a particular device.

Install PyTorch for your CPU/CUDA environment yourself. It is unnecessary for plan execution, NumPy or DLPack. Run the [complete API example](../appendices/python-jupyter-api.md#complete-example) in this interpreter or its kernel.

## Installing a wheel from GitHub Releases

Alternatively, download a `.whl` file from [release v0.1.12](https://github.com/michalwidera/retractordb/releases/tag/v0.1.12) or the PyPI files section. Keep the complete filename, SHA-256 and source revision information from the build process. This release's wheels on GitHub and PyPI have identical filenames and SHA-256 checksums.

This Linux x86_64 and CPython 3.12+ example downloads a specific wheel and verifies its published checksum. Run it in your project directory; if you do not have an environment yet, create one with the commands below:

```bash
python3.12 -m venv .venv-rdb
.venv-rdb/bin/python -m pip install 'numpy>=1.23' jupyterlab ipykernel
RDB_WHEEL="retractordb-0.1.12-cp312-abi3-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl"
curl -fLO "https://github.com/michalwidera/retractordb/releases/download/v0.1.12/$RDB_WHEEL"
printf '%s  %s\n' \
  '511ca1401d9d0e268dd99f8ecfadbeb1e6f8c96ffce141c1a69891e87cffd287' "$RDB_WHEEL" \
  | sha256sum --check
.venv-rdb/bin/python -m pip install --no-deps "$RDB_WHEEL"
.venv-rdb/bin/python -c 'import retractordb._core; print(retractordb._core.__file__)'
.venv-rdb/bin/python -m pip check
```

Use the corresponding checksum from GitHub Releases or PyPI for any other `.whl` file. `--no-deps` requires NumPy to be prepared in advance and does not install or replace PyTorch. You can also install directly from an HTTPS URL containing the original wheel filename, but verify the checksum separately after downloading.

Running `pip install ./api/python` in the code repository installs only the monitoring client and can replace a package containing `_core`. Use a separate environment for that installation.

## Jupyter kernel

The kernel and extension must use compatible Python versions. You can explicitly register your environment's kernel:

```bash
.venv-rdb/bin/python -m ipykernel install --user --name retractordb-wheel --display-name 'RetractorDB wheel'
.venv-rdb/bin/jupyter lab
```

Select "RetractorDB wheel" in Jupyter. This registration intentionally changes user configuration; the local profile script below keeps its kernel inside the venv rather than registering it globally. The code repository's notebooks are [`j0_storage.ipynb`](https://github.com/michalwidera/retractordb/blob/v0.1.12/api/python/notebooks/j0_storage.ipynb), [`j1_engine.ipynb`](https://github.com/michalwidera/retractordb/blob/v0.1.12/api/python/notebooks/j1_engine.ipynb), and [`colab_quickstart.ipynb`](https://github.com/michalwidera/retractordb/blob/v0.1.12/api/python/notebooks/colab_quickstart.ipynb).

## Google Colab

For a basic package installation in a fresh runtime, run this cell:

```python
%pip install --only-binary=retractordb retractordb==0.1.12
import retractordb._core
print(retractordb._core.__file__)
```

Open the full [`colab_quickstart.ipynb` in Colab](https://colab.research.google.com/github/michalwidera/retractordb/blob/v0.1.12/api/python/notebooks/colab_quickstart.ipynb). Its installation cell still requires a `.whl` file or direct URL, rather than a PyPI package name. Download a compatible wheel from release `v0.1.12`, upload it through the Files panel into `/content/`, and set `WHEEL` in the first code cell to its path; alternatively, use the wheel's GitHub Releases URL. Set `SOURCE_COMMIT` to the complete SHA from the build log. The notebook installs only the wheel with `--no-deps`, compares NumPy/torch versions before and after, measures download, installation and import separately, and saves `rdb-acceptance.json`.

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
  build/wheelhouse/retractordb-0.1.12-cp312-abi3-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl \
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
