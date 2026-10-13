# System Installation

RetractorDB's primary deployment platform is Linux on x86-64 and ARM64 (AArch64). You can install a release package or build the programs from source. The installer downloaded with `curl` installs prebuilt binaries; compilation is a separate operation. Apple is a development environment, covered in a [separate section](source-build.md#apple-development-environment).

## Choosing an installation method

| Method | Use | Binary location |
| --- | --- | --- |
| Installer `install.sh --user` | Installation for the current user, without administrator privileges | `~/.local/bin` |
| Installer `install.sh --system` | System-wide installation, optionally with a systemd service | `/usr/local/bin` |
| DEB package | Debian or Ubuntu; managed through apt | `/usr/bin` |
| Building from source | Development, testing, or your own release | `~/.local/bin` by default |

The installer uses [GitHub Releases](https://github.com/michalwidera/retractordb/releases). A quick installation guide is also available on the [project website](https://retractordb.com/install/). The production-build contract and diagnostic variants are described in the [build appendix](../appendices/production-builds-and-research-variants.md).

`Engine` executes a plan inside Python on a logical timeline. It provides no real-time execution and publishes no streams on the bus. Use `xretractor` for real-time processing and the monitoring client to observe its streams.

## Reading paths

- [Linux releases](linux-releases.md): portable, DEB, systemd, upgrades and configuration.
- [Building from source](source-build.md): Linux and the macOS development port.
- [Running](running.md): standalone and a running service plan.
- [Python and Jupyter](python-jupyter.md): wheels, Colab and local environments.
- [Building the Python library](python-build.md): RDB_PYTHON, tests and packaging.
