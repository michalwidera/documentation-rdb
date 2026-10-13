# Linux Releases

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

Ways to deliver a plan to a running service are described in the [xretractor options](../appendices/command-line-options/xretractor.md#service-and-plan-replacement).

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

## Checking the installation and configuration

```bash
xretractor --build-info
xqry -h
xtrdb -h
```

`--build-info` shows the binary's optimizer flags without starting the engine. It does not replace testing your own plan. After installation, also check `command -v xretractor` to confirm that `PATH` selects the intended installation.

The portable installer copies the default TOML only if the file is absent: to `/etc/retractor/retractor.toml` for a system installation or `$XDG_CONFIG_HOME/retractor/retractor.toml` (by default `~/.config/retractor/retractor.toml`) for the user. The shipped file leaves `storage.dir` commented out. Before setting it, create the directory and grant write access to the user running the engine. The complete configuration order and RQL directive precedence are described in the [xretractor options](../appendices/command-line-options/xretractor.md#configuration-file-toml).

Installation through `cmake --install` places the default TOML in `<prefix>/share/retractordb/retractor.toml`; it does not activate it as user configuration. You can copy it to your configuration location or select it with `--config`.

An operator can bound RAM history and growth of `DEFAULT`/`DIRECT` file streams without their own retention:

```toml
[limits]
history_memory_mib = 1024

[storage]
default_retention = [1000, 4]
```

`history_memory_mib` is a positive MiB budget for sources and `MEMORY` rings; a larger plan is rejected at compilation. `default_retention` requires two positive numbers `[capacity, segments]`, also applies to file-based substrates, and does not override explicit `RETENTION`. Without it, file streams without retention still grow; `xretractor` lists them at startup and in `-c`. The TOML file may also contain `server.autoname` (default `false`) and `service.unrestricted` (default `false`, allowing `DO SYSTEM` through `xqry --reset`); their effects and precedence are explained in the [xretractor options](../appendices/command-line-options/xretractor.md#configuration-file-toml).
