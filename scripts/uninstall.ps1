# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Rózsa Zoltán (@rozsazoltan)

& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($env:OS -ne 'Windows_NT') {
        throw 'Run this script in Windows PowerShell, not inside WSL.'
    }
    if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
        throw 'mise not found. Cannot resolve the configured kernel install directory.'
    }
    if (-not $env:USERPROFILE) { throw 'USERPROFILE not available.' }

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

    # Refuse to delete anything beyond the expected bundle and mise metadata.
    $installed = Test-Path -LiteralPath $installDir
    if ($installed) {
        $directory = Get-Item -LiteralPath $installDir -Force
        if (-not $directory.PSIsContainer -or
            ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Unexpected kernel installation path: $installDir. Refusing to delete it."
        }
        $unexpected = @(Get-ChildItem -LiteralPath $installDir -Force | Where-Object {
            $_.Name -notin @('bzImage', 'modules.vhdx', '.mise.backend.toml') -or
            $_.PSIsContainer -or
            ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
        })
        if ($unexpected.Count -gt 0) {
            $names = ($unexpected | ForEach-Object {
                if ($_.PSIsContainer) { "$($_.Name)/" } else { $_.Name }
            }) -join ', '
            throw "Unexpected files in ${installDir}: $names. Refusing to delete non-Datarose files."
        }
    }

    # Remove only kernel overrides that point to this installation.
    $configPath = Join-Path $env:USERPROFILE '.wslconfig'
    $removed = 0
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $content = [System.IO.File]::ReadAllText($configPath)
        $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
        $lines = @($content -split '\r?\n')
        $result = New-Object 'System.Collections.Generic.List[string]'
        $inWsl2 = $false
        $expected = @{
            kernel = (Join-Path $installDir 'bzImage')
            kernelModules = (Join-Path $installDir 'modules.vhdx')
        }

        foreach ($line in $lines) {
            if ($line -match '^[ \t]*\[([^\]\r\n]+)\][ \t]*(?:[;#].*)?$') {
                $inWsl2 = $Matches[1].Equals('wsl2', [StringComparison]::OrdinalIgnoreCase)
            }
            if ($inWsl2 -and $line -match '^[ \t]*(kernel|kernelModules)[ \t]*=[ \t]*(.*)$') {
                $key = $Matches[1]
                $value = ($Matches[2] -replace '[ \t]+[;#].*$', '').Trim().Trim('"').Trim("'")
                $value = $value.Replace('\\', '\')
                if ([string]::Equals($value, $expected[$key], [StringComparison]::OrdinalIgnoreCase)) {
                    $removed++
                    continue
                }
            }
            $result.Add($line)
        }
    }

    if (-not $installed -and $removed -eq 0) {
        Write-Output "Kernel already uninstalled: $installDir"
        return
    }

    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'wsl.exe not found. Cannot safely unload the kernel.'
    }
    Write-Output 'Stopping all WSL distributions...'
    & wsl.exe --shutdown
    if ($LASTEXITCODE -ne 0) { throw "wsl --shutdown failed (exit code $LASTEXITCODE)." }

    if ($removed -gt 0) {
        $backupPath = "$configPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')"
        Copy-Item -LiteralPath $configPath -Destination $backupPath -ErrorAction Stop
        $updated = [string]::Join($newline, $result)
        [System.IO.File]::WriteAllText($configPath, $updated, (New-Object System.Text.UTF8Encoding($false)))
        Write-Output "Removed $removed Datarose kernel override(s): $configPath"
        Write-Output "Backup: $backupPath"
    } else {
        Write-Output 'No matching Datarose kernel overrides in .wslconfig.'
    }

    if ($installed) {
        Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction Stop
        Write-Output "Kernel files removed: $installDir"
    } else {
        Write-Output "Kernel files already absent: $installDir"
    }
    Write-Output 'Uninstall complete. Start WSL when ready.'
}
