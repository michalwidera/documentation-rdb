# Installation Process

RetractorDB's primary deployment platform is Linux on x86-64 and ARM64 (AArch64). You can install a release package or build the programs from source. The installer downloaded with `curl` installs prebuilt binaries; compilation is a separate operation. Apple is a development environment, covered in a [separate section](#apple-development-environment).

## Choosing an installation method

| Method | Use | Binary location |
| --- | --- | --- |
| Installer `install.sh --user` | Installation for the current user, without administrator privileges | `~/.local/bin` |
| Installer `install.sh --system` | System-wide installation, optionally with a systemd service | `/usr/local/bin` |
| DEB package | Debian or Ubuntu; managed through apt | `/usr/bin` |
| Building from source | Development, testing, or your own release | `~/.local/bin` by default |

The installer uses [GitHub Releases](https://github.com/michalwidera/retractordb/releases). A quick installation guide is also available on the [project website](https://retractordb.com/install/). The production-build contract and diagnostic variants are described in the [build appendix](production-builds-and-research-variants.md).

## Installing a release on Linux

The installer requires Bash, `curl`, `python3`, and `sha256sum`. It detects x86-64 and AArch64, selects a `retractordb-<version>-linux-<architecture>-portable.tar.gz` archive, and verifies its SHA-256 against the GitHub release asset's `digest` field. Before installation it checks the archive contents, ELF architecture, and whether all three programs can run. A system with an incompatible `glibc` or `libstdc++`, a musl-based distribution, or 32-bit ARM may require a separate source build.

To check the releases available for the host architecture:

```bash
curl -fsSL https://retractordb.com/install.sh | bash -s -- list
```

By default, the newest stable version with a matching archive is selected. Drafts and prereleases are skipped. To install for the current user:

```bash
curl -fsSL https://retractordb.com/install.sh | bash -s -- install --user
```

The `xretractor`, `xqry`, and `xtrdb` programs are available through links in `~/.local/bin`. If that directory is missing from `PATH`, add it to your shell configuration. The installer prints this advice but does not change the shell configuration itself.

You can also download and inspect the script first:

```bash
curl -fsSLO https://retractordb.com/install.sh
less install.sh
bash install.sh install --user
```

## System installation and the systemd service

System installation requires root privileges and uses the `/usr/local` prefix:

```bash
curl -fsSL https://retractordb.com/install.sh | sudo bash -s -- install --system
```

On a host running systemd, `--service` also installs, enables, and starts the service:

```bash
curl -fsSL https://retractordb.com/install.sh | sudo bash -s -- install --system --service
systemctl status xretractor.service
```

The installer creates the `retractor` account and an empty `/etc/retractor/startup.rql` if they do not already exist. An empty file starts an idle instance ready to accept a plan. Existing queries are preserved. The service prefix must be owned by root and must not be writable by other users. The portable archive itself contains no systemd unit; the installer creates it.

Ways to deliver a plan to a running service are described in the [xretractor options](command-line-options/xretractor.md#service-and-plan-replacement).

## Upgrades, versions, status and removal

```bash
curl -fsSL https://retractordb.com/install.sh | bash -s -- upgrade --user
curl -fsSL https://retractordb.com/install.sh | bash -s -- status --user
curl -fsSL https://retractordb.com/install.sh | bash -s -- uninstall --user
```

`install` and `upgrade` accept `--version <version>` with a release number available through `list`. Use `--prefix /absolute/path` for a custom directory; supply the same prefix when upgrading, checking, or removing it. For a system installation, use `--system` and run operations that modify the installation as root.

The installer stores programs in `<prefix>/lib/retractordb/versions/<version>` and maintains an `installer-state` file in `<prefix>/lib/retractordb`. The `status` command shows the managed installation and binary links; it does not check whether the engine is ready to handle queries. Use a command such as `xqry --server service --hello` to contact a running instance.

An upgrade restarts the managed systemd service with the new binary. `uninstall` removes the programs and its own unit while preserving configuration, query files, and the service account. The installer does not take over binaries installed by another method in the same prefix; choose a separate prefix or keep using the original installation method.

Stop running instances before updating their binaries. Versions using different bus layouts have separate registries and do not provide shared collision checks for stream names or storage paths. The current layout is described in [Multiple Instances and the Bus](../data-processing-system-architecture/multiple-instances-and-bus.md).

## DEB package

For Debian or Ubuntu, download a DEB package matching the architecture from GitHub Releases and install it through apt. In the example below, `package.deb` denotes the downloaded file:

```bash
sudo apt install ./package.deb
```

The package installs programs in `/usr/bin`, prepares configuration, and enables the service for the next system boot. To start it immediately:

```bash
sudo systemctl start xretractor.service
systemctl status xretractor.service
```

Upgrade with `apt install ./<new-file>.deb` and remove with `sudo apt remove retractordb`. The portable installer does not manage Debian packages. Do not install both the DEB variant and the portable variant with `--service` on one host: both use the `xretractor.service` name.

## Building and installing from source

Linux builds use Conan 2, CMake, and Ninja. A C++23 compiler with `<print>` and `std::println` is required (GCC 14 or newer). The project's toolchain requires CMake 4.4.2 or newer. The `scripts/buildrdb.sh` script prepares the tools and Conan profile; dependency installation on Linux uses apt.

From the downloaded `retractordb` repository:

```bash
scripts/buildrdb.sh toolchain
scripts/buildrdb.sh conan ninja
scripts/buildrdb.sh bashrc
```

After adding `~/.local/bin` to `PATH`, refresh the shell, for example by opening a new terminal. To build and install Debug:

```bash
scripts/buildrdb.sh debug
cmake --install build/Debug
ctest --test-dir build/Debug --output-on-failure
```

Installation is a separate step after building and does not require sudo by default. Integration tests also use installed programs, so installation precedes testing. The optional API libraries have [separate installation and test targets](stream-monitoring-api.md).

A production release from source requires a clean Git tree:

```bash
scripts/buildrdb.sh release
cmake --install build/Release
ctest --test-dir build/Release --output-on-failure
```

The `release-dirty` mode is for diagnosing local changes and does not produce a production release. See the [build contract](production-builds-and-research-variants.md). Packages for distribution are prepared separately; scripts and checks for Linux releases are described in the code repository's `scripts/release_package/README.md`.

## Checking the installation and configuration

```bash
xretractor --build-info
xqry -h
xtrdb -h
```

`--build-info` shows the binary's optimizer flags without starting the engine. It does not replace testing your own plan. After installation, also check `command -v xretractor` to confirm that `PATH` selects the intended installation.

The portable installer copies the default TOML only if the file is absent: to `/etc/retractor/retractor.toml` for a system installation or `$XDG_CONFIG_HOME/retractor/retractor.toml` (by default `~/.config/retractor/retractor.toml`) for the user. The shipped file leaves `storage.dir` commented out. Before setting it, create the directory and grant write access to the user running the engine. The complete configuration order and RQL directive precedence are described in the [xretractor options](command-line-options/xretractor.md#configuration-file-toml).

Installation through `cmake --install` places the default TOML in `<prefix>/share/retractordb/retractor.toml`; it does not activate it as user configuration. You can copy it to your configuration location or select it with `--config`.

## Apple development environment

The macOS port is for development and testing. The system's general contract, service description, and production procedures in this manual apply to Linux. The `curl` installer described above supports Linux; Apple requires a source build.

The tested port configuration is Apple silicon with macOS 27 and Apple clang 21. Intel Macs and older system releases remain unverified. Xcode 16.3+ Command Line Tools and a macOS 14.4+ deployment target are minimum requirements imposed by `std::print`, not a declaration that all such configurations have been tested.

Before building, prepare the Command Line Tools (`xcode-select --install`), Homebrew, and CMake, Python 3, and Git available on `PATH`. On macOS, `scripts/buildrdb.sh toolchain` uses Homebrew. The script below can install missing Conan and Ninja through Homebrew; it also uses the Conan environment to provide the required CMake version:

```bash
scripts/macos-build.sh
scripts/macos-build.sh --sanitize
```

The default run is Debug: configure, build, install, refresh the test copy, rebuild, run CTest, and run the separate `test-api` target. The log is written to `build/macos-build.log`. `--sanitize` enables AddressSanitizer and UndefinedBehaviorSanitizer. `--no-install` disables automatic tool installation, but still installs the built programs. `--skip-tests` skips tests while retaining installation. `scripts/macos-build.sh release` selects the Release configuration but does not perform the checks of the production `scripts/buildrdb.sh release` workflow.

### Differences relevant to development

| Area | macOS port behavior |
| --- | --- |
| Configuration | Without `--config`, layers are read in order from `/etc/retractor/retractor.toml`, `/usr/local/etc/retractor/retractor.toml`, `/opt/homebrew/etc/retractor/retractor.toml`, then the user location. Later layers override earlier keys. The Homebrew path does not imply that an installation formula is available. |
| IPC | Boost.Interprocess uses file-backed storage under `/tmp/boost_interprocess/...`; `--shmbudget` reports that volume rather than Linux's `/dev/shm` tmpfs. Overlong object names receive a deterministic shortened token; the public server name retains its 32-character limit. |
| Process liveness | `sysctl` provides the PID and start time; the absence of `/proc` does not remove the live-owner check. The bus lock has a fallback that recovers after its owner's death. |
| Real time | `SCHED_FIFO` is set on the processing thread through `pthread_setschedparam`. The TOML priority (1..99) is clamped to the kernel's range. CPU affinity and a PREEMPT_RT equivalent are unavailable; `mlockall` can return `ENOSYS`, after which execution continues without locked memory pages. Absolute sleep uses the Mach interface. This is not a measurement platform for Linux real-time guarantees. |
| Service | The code identifies a launchd job through `XPC_SERVICE_NAME` and parent PID 1, and builds a restart command using `launchctl kickstart -k`. Choosing the domain from the effective UID is a heuristic: a system daemon running as a non-root user may receive the wrong domain. The package provides neither a `.plist` nor a launchd service installer. |
| Memory tests | On Apple silicon, tests run without Valgrind. Run memory checks in a separate sanitizer configuration; passing ordinary CTest, including entries with `-vg` in their names, does not establish that such checks ran. |
| API | The script explicitly runs `test-api`, covering Python and C++ clients and process creation. The API remains optional; this development path does not extend the production API contract to macOS. |
| Packaging | CPack creates TGZ without the systemd service component. The ability to create a Darwin archive locally does not mean it is available through the web installer. |

Platform capability checks and fallback declarations are described in the [build appendix](production-builds-and-research-variants.md#platform-capabilities-and-sanitizers).
