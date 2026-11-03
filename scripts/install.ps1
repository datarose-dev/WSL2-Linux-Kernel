# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Rózsa Zoltán (@rozsazoltan)

param(
    [ValidatePattern('^(latest|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(?:-r[0-9]+)?)$')]
    [string]$Version = 'latest'
)

& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($env:OS -ne 'Windows_NT') {
        throw 'Run this script in Windows PowerShell, not inside WSL.'
    }
    if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
        throw 'mise not found. Install it with: winget install jdx.mise'
    }

    $doctor = & mise doctor --json
    if ($LASTEXITCODE -ne 0) { throw 'mise doctor --json failed.' }
    $miseDirs = ($doctor -join "`n") | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($miseDirs.dirs.data)) {
        throw 'mise did not return a data directory.'
    }

    $installsRoot = if ($env:MISE_INSTALLS_DIR) {
        $env:MISE_INSTALLS_DIR
    } else {
        Join-Path $miseDirs.dirs.data 'installs'
    }
    $installDir = Join-Path $installsRoot 'github-datarose-dev-wsl2-linux-kernel'

    if (Test-Path -LiteralPath $installDir) {
        if (@(Get-ChildItem -LiteralPath $installDir -Force).Count -gt 0) {
            throw "Destination already contains files: $installDir. Use update.ps1 to replace an existing Datarose kernel."
        }
    }

    $tool = "github:datarose-dev/WSL2-Linux-Kernel[asset_pattern=wsl2-kernel-windows-x64.zip,version_prefix=linux-datarose-wsl-]@$Version"
    & mise install-into $tool $installDir
    if ($LASTEXITCODE -ne 0) { throw "mise install-into failed (exit code $LASTEXITCODE)." }

    foreach ($filename in @('bzImage', 'modules.vhdx')) {
        if (-not (Test-Path -LiteralPath (Join-Path $installDir $filename) -PathType Leaf)) {
            throw "Missing $filename in $installDir"
        }
    }

    Write-Output "Kernel installed: $installDir"
    Write-Output 'Run configure.ps1 once to update .wslconfig.'
}
