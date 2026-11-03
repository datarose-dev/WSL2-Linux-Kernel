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

Install **mise on Windows**, not inside the WSL distribution: `.wslconfig` needs Windows paths. Requires a published release containing `wsl2-kernel-windows-x64.zip`.

1. Install [mise](https://mise.jdx.dev/installing-mise.html) in PowerShell:

   ```powershell
   winget install jdx.mise
   ```

  Open a new PowerShell session so `mise` is available.

2. Install latest Datarose release into the **mise installs directory**, under the GitHub backend tool name, without a version subfolder. `version_prefix` removes `linux-datarose-wsl-` from the published tag; `asset_pattern` chooses the Windows bundle:

   ```powershell
   $installsRoot = if ($env:MISE_INSTALLS_DIR) {
     $env:MISE_INSTALLS_DIR
   } else {
     $miseDirs = mise doctor --json | ConvertFrom-Json
     Join-Path $miseDirs.dirs.data 'installs'
   }
   $installDir = Join-Path $installsRoot 'github-datarose-dev-wsl2-linux-kernel'
   mise install-into 'github:datarose-dev/WSL2-Linux-Kernel[asset_pattern=wsl2-kernel-windows-x64.zip,version_prefix=linux-datarose-wsl-]@latest' $installDir
   ```

   Unlike `mise use`, `mise install-into` writes directly to the chosen directory without a version-numbered subfolder. This installation is **not tracked** by mise, even though it lives under `installs/`; use `install-into` again to update it. **Do not combine this directory with regular `mise install` / `mise use` for the same tool:** `install-into` replaces the entire destination and may delete versioned installations. The path is resolved from mise's active configuration: `mise doctor --json` provides the data directory, and `MISE_INSTALLS_DIR` takes precedence when configured.

3. Verify installed files and print `.wslconfig` values:

   ```powershell
   $installsRoot = if ($env:MISE_INSTALLS_DIR) {
     $env:MISE_INSTALLS_DIR
   } else {
     $miseDirs = mise doctor --json | ConvertFrom-Json
     Join-Path $miseDirs.dirs.data 'installs'
   }
   $installDir = Join-Path $installsRoot 'github-datarose-dev-wsl2-linux-kernel'
   $kernel = Join-Path $installDir 'bzImage'
   $modules = Join-Path $installDir 'modules.vhdx'
   if (!(Test-Path $kernel) -or !(Test-Path $modules)) {
     throw 'Missing bzImage or modules.vhdx in mise installation'
   }
   "kernel=$($kernel.Replace('\', '\\'))"
   "kernelModules=$($modules.Replace('\', '\\'))"
   ```

4. In `%USERPROFILE%\.wslconfig`, add the two printed lines under the existing `[wsl2]` section. Create that section if missing; **keep other settings**. Example (replace with the actual path printed in step 3):

   ```ini
   [wsl2]
   kernel=C:\\path\\to\\mise\\installs\\github-datarose-dev-wsl2-linux-kernel\\bzImage
   kernelModules=C:\\path\\to\\mise\\installs\\github-datarose-dev-wsl2-linux-kernel\\modules.vhdx
   ```

   Example paths are placeholders. **Copy actual printed lines** from step 3. These paths remain unchanged across kernel updates.

5. Restart WSL from PowerShell, then verify inside test distribution:

   ```powershell
   wsl --shutdown
   wsl -d mydistro
   ```

   ```bash
   uname -r
   test -c /dev/udmabuf && echo 'UDMABUF OK'
   test -c /dev/kvm && echo 'KVM OK'
   test -c /dev/dxg && echo 'WSL GPU OK'
   ```

### Keep current

`@latest` does **not** update files automatically. Reinstall the latest release explicitly in PowerShell:

```powershell
wsl --shutdown
$installsRoot = if ($env:MISE_INSTALLS_DIR) {
  $env:MISE_INSTALLS_DIR
} else {
  $miseDirs = mise doctor --json | ConvertFrom-Json
  Join-Path $miseDirs.dirs.data 'installs'
}
$installDir = Join-Path $installsRoot 'github-datarose-dev-wsl2-linux-kernel'
mise install-into 'github:datarose-dev/WSL2-Linux-Kernel[asset_pattern=wsl2-kernel-windows-x64.zip,version_prefix=linux-datarose-wsl-]@latest' $installDir
```

Confirm replacement only if the directory contains this standalone kernel installation; `install-into` deletes all previous contents before reinstalling. Then start WSL. `.wslconfig` paths stay unchanged. `mise outdated` and `mise upgrade` do not manage an `install-into` installation. `wsl --update` does not update this custom kernel.

### Pin a version

Instead of `@latest`, choose a published Datarose version (without the `linux-datarose-wsl-` prefix):

```powershell
mise ls-remote 'github:datarose-dev/WSL2-Linux-Kernel[version_prefix=linux-datarose-wsl-]'
wsl --shutdown
$installsRoot = if ($env:MISE_INSTALLS_DIR) {
  $env:MISE_INSTALLS_DIR
} else {
  $miseDirs = mise doctor --json | ConvertFrom-Json
  Join-Path $miseDirs.dirs.data 'installs'
}
$installDir = Join-Path $installsRoot 'github-datarose-dev-wsl2-linux-kernel'
mise install-into 'github:datarose-dev/WSL2-Linux-Kernel[asset_pattern=wsl2-kernel-windows-x64.zip,version_prefix=linux-datarose-wsl-]@6.18.60.1' $installDir
```

Confirm replacement only if the directory contains this standalone kernel installation. The selected version remains installed until `install-into` runs again. For rebuilds use the corresponding `-r2`, `-r3`, etc. version suffix. `.wslconfig` paths remain unchanged.

### Revert

Remove `kernel` and `kernelModules` entries from `%USERPROFILE%\.wslconfig` (preserve other settings), then run `wsl --shutdown`. All WSL2 distributions share the selected kernel.

## Licence and copyright

- **Linux kernel and Microsoft WSL modifications:** GPL version 2 only, with Linux syscall exception (`GPL-2.0 WITH Linux-syscall-note`), plus any other per-file licences present in upstream source. See [`COPYING`](COPYING), [`LICENSES`](LICENSES), upstream kernel source referenced in release notes, and [`patches/`](patches/). Existing copyright notices remain with original authors, including Linux contributors and Microsoft.
- **Datarose-authored workflow, patch and documentation:** GPL-2.0-only. Copyright © 2026 **Rózsa Zoltán** ([@rozsazoltan](https://github.com/rozsazoltan)). See [`NOTICE.md`](NOTICE.md).
- This project is **unofficial**, not affiliated with or endorsed by Microsoft or Linux Foundation.

Each release publishes one binary asset, `wsl2-kernel-windows-x64.zip`, containing `bzImage` and matching `modules.vhdx`. GitHub-generated source archives contain only this patch repository, not the complete modified kernel source. Release notes identify the exact upstream commit and this repository's patches. GPLv2 requires access to complete corresponding source when distributing binaries; upstream source and patches alone should not be assumed to satisfy that obligation.
