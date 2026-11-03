<!-- SPDX-License-Identifier: GPL-2.0-only -->
<!-- Copyright (C) 2026 Rózsa Zoltán (@rozsazoltan) -->

# Datarose WSL2 Linux Kernel

Unofficial, open-source builds of [Microsoft's WSL2 Linux kernel](https://github.com/microsoft/WSL2-Linux-Kernel), maintained by **Rózsa Zoltán** ([@rozsazoltan](https://github.com/rozsazoltan)) under [datarose-dev](https://github.com/datarose-dev).

Only intended upstream kernel change:

```diff
-# CONFIG_UDMABUF is not set
+CONFIG_UDMABUF=y
```

This enables `/dev/udmabuf` for DMA-BUF consumers.

## Automated releases

Workflow checks Microsoft's latest WSL2 kernel release daily. For the configured upstream series (`config/upstream-series`), it clones **official upstream source**, applies all `patches/*.patch` files in filename order using `git apply` (currently only [`enable-udmabuf.patch`](patches/enable-udmabuf.patch)), builds x86_64 kernel and publishes a GitHub release. Patch checks stop at the first failed patch, report previously applied patches and the failed filename, and show the exact `git apply` error in the workflow log and job summary.

When Microsoft publishes a newer kernel series (for example, `6.18` → `7.0`), `github-actions[bot]` opens a pull request to update [`config/upstream-series`](config/upstream-series). Review and merge the pull request to switch series. Previously configured series continues receiving builds until merge.

Version mapping:

```text
Microsoft: linux-msft-wsl-6.18.58.1
Datarose:  linux-datarose-wsl-6.18.58.1
```

Release revisions are automatic: first build of each upstream version has **no revision suffix**. If an already released upstream version is rebuilt by a manual workflow run, the next available suffix is used (`-r2`, `-r3`, …). Scheduled checks do not rebuild already published versions. Existing releases are not overwritten. Upstream tag and commit are recorded in release notes. **This repository contains no vendored kernel source.**

```text
Microsoft: linux-msft-wsl-6.18.60.1
Datarose:  linux-datarose-wsl-6.18.60.1
Rebuild:   linux-datarose-wsl-6.18.60.1-r2
Rebuild:   linux-datarose-wsl-6.18.60.1-r3
```

Release tag is renamed, **not kernel internal version**: `uname -r` retains Microsoft's original `-microsoft-standard-WSL2` suffix. No extra kernel changes beyond UDMABUF.

## Install with mise (Windows)

Install [mise](https://mise.jdx.dev/installing-mise.html) **on Windows**, not inside WSL. Run scripts in **PowerShell**. Scripts use mise's configured installs directory (`MISE_INSTALLS_DIR`, or `mise doctor --json` data directory) and store `bzImage` and `modules.vhdx` directly under `github-datarose-dev-wsl2-linux-kernel/`, with **no version subfolder**. `.wslconfig` paths therefore stay stable between updates.

Scripts run directly from the [`master` branch](https://github.com/datarose-dev/WSL2-Linux-Kernel/tree/master/scripts). Review their source before executing remote PowerShell code.

### Install

Install mise if needed, then open a new PowerShell session:

```powershell
winget install jdx.mise
```

Install latest published kernel:

```powershell
irm 'https://raw.githubusercontent.com/datarose-dev/WSL2-Linux-Kernel/master/scripts/install.ps1' | iex
```

Configure Windows WSL settings **once** (creates `%USERPROFILE%\.wslconfig` if missing; preserves other settings and backs up existing file):

```powershell
irm 'https://raw.githubusercontent.com/datarose-dev/WSL2-Linux-Kernel/master/scripts/configure.ps1' | iex
wsl --shutdown
```

Then verify in your WSL distribution:

```powershell
wsl -d mydistro
```

```bash
uname -r
test -c /dev/udmabuf && echo 'UDMABUF OK'
test -c /dev/kvm && echo 'KVM OK'
test -c /dev/dxg && echo 'WSL GPU OK'
```

### Update

```powershell
irm 'https://raw.githubusercontent.com/datarose-dev/WSL2-Linux-Kernel/master/scripts/update.ps1' | iex
```

`update.ps1` downloads the latest bundle into a temporary directory, verifies required files, stops all WSL distributions with `wsl --shutdown`, and replaces the installed files while keeping a rollback copy during replacement. **No `.wslconfig` change needed.** Run the script when you want an update; updates are not automatic. `mise upgrade` does not manage `install-into` installations.

### Pin a version

Both `install.ps1` and `update.ps1` accept optional `-Version`, including rebuild suffixes (`6.18.60.1-r2`). Download the desired script from [`scripts/`](scripts/) and run it locally with `-Version '6.18.60.1'`. Default: `latest`.

### Restore Microsoft kernel

```powershell
irm 'https://raw.githubusercontent.com/datarose-dev/WSL2-Linux-Kernel/master/scripts/restore.ps1' | iex
wsl --shutdown
```

`restore.ps1` removes only `kernel` and `kernelModules` from `[wsl2]` in `%USERPROFILE%\.wslconfig`, preserving other settings and saving a backup. It does not delete downloaded kernel files. All WSL2 distributions share the selected kernel.

**Note:** `mise install-into` is a standalone installation, even inside mise's `installs/` directory. Do not manage the same directory through `mise use` / `mise install`; those commands may create versioned installations and conflict with these scripts.

## Licence and copyright

- **Linux kernel and Microsoft WSL modifications:** GPL version 2 only, with Linux syscall exception (`GPL-2.0 WITH Linux-syscall-note`), plus any other per-file licences present in upstream source. See [`COPYING`](COPYING), [`LICENSES`](LICENSES), upstream kernel source referenced in release notes, and [`patches/`](patches/). Existing copyright notices remain with original authors, including Linux contributors and Microsoft.
- **Datarose-authored workflow, patch and documentation:** GPL-2.0-only. Copyright © 2026 **Rózsa Zoltán** ([@rozsazoltan](https://github.com/rozsazoltan)). See [`NOTICE.md`](NOTICE.md).
- This project is **unofficial**, not affiliated with or endorsed by Microsoft or Linux Foundation.

Each release publishes one binary asset, `wsl2-kernel-windows-x64.zip`, containing `bzImage` and matching `modules.vhdx`. GitHub-generated source archives contain only this patch repository, not the complete modified kernel source. Release notes identify the exact upstream commit and this repository's patches. GPLv2 requires access to complete corresponding source when distributing binaries; upstream source and patches alone should not be assumed to satisfy that obligation.
