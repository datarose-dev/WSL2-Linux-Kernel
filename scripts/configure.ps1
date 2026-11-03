# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Rózsa Zoltán (@rozsazoltan)

& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($env:OS -ne 'Windows_NT') {
        throw 'Run this script in Windows PowerShell, not inside WSL.'
    }
    if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
        throw 'mise not found. Install it with: winget install jdx.mise'
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
    $kernel = Join-Path $installDir 'bzImage'
    $modules = Join-Path $installDir 'modules.vhdx'
    foreach ($file in @($kernel, $modules)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Missing kernel asset: $file. Run install.ps1 first."
        }
    }

    $kernelEntry = 'kernel=' + $kernel.Replace('\', '\\')
    $modulesEntry = 'kernelModules=' + $modules.Replace('\', '\\')
    $configPath = Join-Path $env:USERPROFILE '.wslconfig'
    $content = if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        [System.IO.File]::ReadAllText($configPath)
    } else {
        ''
    }
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = if ($content.Length -eq 0) { @() } else { @($content -split '\r?\n') }
    $result = New-Object 'System.Collections.Generic.List[string]'
    $inWsl2 = $false
    $sectionCount = 0

    foreach ($line in $lines) {
        if ($line -match '^[ \t]*\[([^\]\r\n]+)\][ \t]*(?:[;#].*)?$') {
            $inWsl2 = $Matches[1].Equals('wsl2', [StringComparison]::OrdinalIgnoreCase)
            if ($inWsl2) {
                $sectionCount++
                if ($sectionCount -gt 1) {
                    throw "Multiple [wsl2] sections found in $configPath. Refusing to edit."
                }
                $result.Add($line)
                $result.Add($kernelEntry)
                $result.Add($modulesEntry)
                continue
            }
        }
        if ($inWsl2 -and $line -match '^[ \t]*(?:kernel|kernelModules)[ \t]*=') {
            continue
        }
        $result.Add($line)
    }

    if ($sectionCount -eq 0) {
        if ($result.Count -gt 0 -and $result[$result.Count - 1] -ne '') {
            $result.Add('')
        }
        $result.Add('[wsl2]')
        $result.Add($kernelEntry)
        $result.Add($modulesEntry)
    }

    $updated = [string]::Join($newline, $result)
    if ($updated -eq $content) {
        Write-Output "Already configured: $configPath"
        return
    }

    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $backupPath = "$configPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')"
        Copy-Item -LiteralPath $configPath -Destination $backupPath -ErrorAction Stop
        Write-Output "Backup: $backupPath"
    }
    [System.IO.File]::WriteAllText($configPath, $updated + $(if ($updated.EndsWith($newline)) { '' } else { $newline }), (New-Object System.Text.UTF8Encoding($false)))
    Write-Output "Updated: $configPath"
    Write-Output $kernelEntry
    Write-Output $modulesEntry
    Write-Output 'Run wsl --shutdown to apply the new kernel.'
}
