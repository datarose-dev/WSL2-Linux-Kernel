# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Rózsa Zoltán (@rozsazoltan)

& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($env:OS -ne 'Windows_NT') {
        throw 'Run this script in Windows PowerShell, not inside WSL.'
    }
    if (-not $env:USERPROFILE) { throw 'USERPROFILE not available.' }

    $configPath = Join-Path $env:USERPROFILE '.wslconfig'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Write-Output "No .wslconfig found at $configPath. Default WSL kernel already selected."
        return
    }

    $content = [System.IO.File]::ReadAllText($configPath)
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = @($content -split '\r?\n')
    $result = New-Object 'System.Collections.Generic.List[string]'
    $inWsl2 = $false
    $removed = 0

    foreach ($line in $lines) {
        if ($line -match '^[ \t]*\[([^\]\r\n]+)\][ \t]*(?:[;#].*)?$') {
            $inWsl2 = $Matches[1].Equals('wsl2', [StringComparison]::OrdinalIgnoreCase)
        }
        if ($inWsl2 -and $line -match '^[ \t]*(?:kernel|kernelModules)[ \t]*=') {
            $removed++
            continue
        }
        $result.Add($line)
    }

    if ($removed -eq 0) {
        Write-Output "No kernel overrides found in $configPath. Default WSL kernel already selected."
        return
    }

    $backupPath = "$configPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')"
    Copy-Item -LiteralPath $configPath -Destination $backupPath -ErrorAction Stop
    $updated = [string]::Join($newline, $result)
    [System.IO.File]::WriteAllText($configPath, $updated, (New-Object System.Text.UTF8Encoding($false)))

    Write-Output "Removed $removed kernel override(s): $configPath"
    Write-Output "Backup: $backupPath"
    Write-Output 'Run wsl --shutdown to restore the default Microsoft kernel.'
}
