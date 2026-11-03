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

    if (-not (Test-Path -LiteralPath $installDir -PathType Container)) {
        throw "Kernel not installed: $installDir. Run install.ps1 first."
    }
    foreach ($filename in @('bzImage', 'modules.vhdx')) {
        if (-not (Test-Path -LiteralPath (Join-Path $installDir $filename) -PathType Leaf)) {
            throw "Missing $filename in $installDir. Refusing to overwrite unrelated mise files."
        }
    }
    $unexpected = @(Get-ChildItem -LiteralPath $installDir -Force | Where-Object {
        $_.Name -notin @('bzImage', 'modules.vhdx', '.mise.backend.toml')
    })
    if ($unexpected.Count -gt 0) {
        $unexpectedNames = ($unexpected | ForEach-Object {
            if ($_.PSIsContainer) { "$($_.Name)/" } else { $_.Name }
        }) -join ', '
        throw "Unexpected files in ${installDir}: $unexpectedNames. Refusing to replace non-Datarose files."
    }

    # Resolve a published release, not a cached mise version or a leftover Git tag.
    $apiBase = 'https://api.github.com/repos/datarose-dev/WSL2-Linux-Kernel/releases'
    $headers = @{
        'Accept' = 'application/vnd.github+json'
        'User-Agent' = 'datarose-wsl2-kernel-updater'
        'Cache-Control' = 'no-cache'
    }
    if ($Version -eq 'latest') {
        $releaseUri = "$apiBase/latest"
    } else {
        $releaseUri = "$apiBase/tags/linux-datarose-wsl-$Version"
    }
    try {
        $release = Invoke-RestMethod -Uri $releaseUri -Headers $headers -ErrorAction Stop
    } catch {
        throw "Cannot find published Datarose release ($Version): $($_.Exception.Message). Old installation kept."
    }
    $releaseVersionMatch = [regex]::Match(
        [string]$release.tag_name,
        '^linux-datarose-wsl-([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(?:-r[0-9]+)?)$'
    )
    if ($release.draft -or $release.prerelease -or -not $releaseVersionMatch.Success) {
        throw "Invalid or unpublished Datarose release: $($release.tag_name). Old installation kept."
    }
    $resolvedVersion = $releaseVersionMatch.Groups[1].Value
    $assets = @($release.assets | Where-Object { $_.name -eq 'wsl2-kernel-windows-x64.zip' -and $_.state -eq 'uploaded' })
    if ($assets.Count -ne 1) {
        throw "Release $($release.tag_name) has no uploaded Windows kernel ZIP. Old installation kept."
    }
    Write-Output "Selected release: $($release.tag_name)"

    # Keep mise's version cache and install state away from the active kernel.
    $stage = "$installDir.update-$PID"
    $backup = "$installDir.backup-$PID"
    $sandbox = "$installDir.mise-$PID"
    if ((Test-Path -LiteralPath $stage) -or
        (Test-Path -LiteralPath $backup) -or
        (Test-Path -LiteralPath $sandbox)) {
        throw 'Temporary update/backup path already exists. Refusing to overwrite it.'
    }

    $tool = "github:datarose-dev/WSL2-Linux-Kernel[asset_pattern=wsl2-kernel-windows-x64.zip,version_prefix=linux-datarose-wsl-]@$resolvedVersion"
    try {
        $miseEnvNames = @('MISE_DATA_DIR', 'MISE_INSTALLS_DIR', 'MISE_CACHE_DIR', 'MISE_STATE_DIR')
        $savedMiseEnv = @{}
        foreach ($name in $miseEnvNames) {
            $savedMiseEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        try {
            $env:MISE_DATA_DIR = $sandbox
            $env:MISE_INSTALLS_DIR = Join-Path $sandbox 'installs'
            $env:MISE_CACHE_DIR = Join-Path $sandbox 'cache'
            $env:MISE_STATE_DIR = Join-Path $sandbox 'state'
            & mise install-into $tool $stage
            if ($LASTEXITCODE -ne 0) {
                throw "mise install-into failed (exit code $LASTEXITCODE). Old installation kept."
            }
        } finally {
            foreach ($name in $miseEnvNames) {
                [Environment]::SetEnvironmentVariable($name, $savedMiseEnv[$name], 'Process')
            }
        }
        foreach ($filename in @('bzImage', 'modules.vhdx')) {
            if (-not (Test-Path -LiteralPath (Join-Path $stage $filename) -PathType Leaf)) {
                throw "New kernel bundle is missing $filename. Old installation kept."
            }
        }

        if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
            throw 'wsl.exe not found. Cannot safely replace loaded kernel modules.'
        }
        Write-Output 'Stopping all WSL distributions to release modules.vhdx...'
        & wsl.exe --shutdown
        if ($LASTEXITCODE -ne 0) { throw "wsl --shutdown failed (exit code $LASTEXITCODE)." }

        Move-Item -LiteralPath $installDir -Destination $backup -ErrorAction Stop
        try {
            Move-Item -LiteralPath $stage -Destination $installDir -ErrorAction Stop
        } catch {
            try {
                Move-Item -LiteralPath $backup -Destination $installDir -ErrorAction Stop
            } catch {
                throw "Cannot restore previous installation. Backup remains at: $backup. $($_.Exception.Message)"
            }
            throw
        }
        try {
            Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning "Kernel updated, but old backup could not be deleted: $backup"
        }
        Write-Output "Kernel updated: $installDir"
        Write-Output '.wslconfig path unchanged. Start WSL when ready.'
    } finally {
        if (Test-Path -LiteralPath $stage) {
            Remove-Item -LiteralPath $stage -Recurse -Force
        }
        if (Test-Path -LiteralPath $sandbox) {
            Remove-Item -LiteralPath $sandbox -Recurse -Force
        }
    }
}
