# Extracts Set-IniKey from install.ps1 and tests merge behavior against a
# Docker-Desktop-style .wslconfig, then tests the uninstall revert logic.
$ErrorActionPreference = "Stop"
$src = Get-Content (Join-Path $PSScriptRoot "..\install.ps1") -Raw

# Pull the Set-IniKey function text out of the installer so the test always
# runs the real code.
if ($src -notmatch '(?s)(function Set-IniKey.*?\n    \})') { throw "Set-IniKey not found" }
Invoke-Expression $Matches[1]

$existing = @(
    "# my notes",
    "[wsl2]",
    "memory=12GB",
    "processors=4",
    "networkingMode=nat",
    "",
    "[interop]",
    "enabled=true"
)

$lines = $existing
$changes = @()
foreach ($kv in @(
    @{ s = "wsl2";         k = "kernel";            v = 'C:\\W\\bzImage' },
    @{ s = "wsl2";         k = "kernelModules";     v = 'C:\\W\\modules.vhdx' },
    @{ s = "wsl2";         k = "memory";            v = "8GB" },
    @{ s = "experimental"; k = "autoMemoryReclaim"; v = "gradual" },
    @{ s = "experimental"; k = "sparseVhd";         v = "true" })) {
    $script:prevValue = $null
    $lines = Set-IniKey $lines $kv.s $kv.k $kv.v
    $changes += [pscustomobject]@{ section = $kv.s; key = $kv.k; value = $kv.v; previous = $script:prevValue }
}

Write-Host "--- merged ---"
$lines | ForEach-Object { Write-Host $_ }

# Assertions on the merge
function Assert($cond, $msg) { if (-not $cond) { Write-Host "ASSERT FAIL: $msg" -ForegroundColor Red; exit 1 } }
Assert (($lines -join "`n") -match '(?m)^kernel=C:\\\\W\\\\bzImage$') "kernel key set in file"
Assert (($lines -join "`n") -match '(?m)^memory=8GB$') "memory replaced"
Assert (($lines -join "`n") -notmatch '(?m)^memory=12GB$') "old memory gone"
Assert (($lines -join "`n") -match '(?m)^processors=4$') "unrelated key preserved"
Assert (($lines -join "`n") -match '(?m)^networkingMode=nat$') "unrelated key preserved 2"
Assert (($lines -join "`n") -match '(?m)^enabled=true$') "other section preserved"
Assert (($lines -join "`n") -match '(?m)^\[experimental\]$') "experimental section created"
Assert (($lines -join "`n") -match '(?m)^# my notes$') "comment preserved"
# kernel must land inside [wsl2], not [interop]: find positions
$idxWsl2 = [array]::IndexOf($lines, '[wsl2]')
$idxInterop = [array]::IndexOf($lines, '[interop]')
$idxKernel = ($lines | Select-String -SimpleMatch 'kernel=C:' | Select-Object -First 1).LineNumber - 1
Assert ($idxKernel -gt $idxWsl2 -and $idxKernel -lt $idxInterop) "kernel inside [wsl2]"
$prevMem = ($changes | Where-Object key -eq 'memory').previous
Assert ($prevMem -eq '12GB') "previous memory recorded ($prevMem)"
Assert ($null -eq ($changes | Where-Object key -eq 'kernel').previous) "kernel had no previous"

# --- revert logic from uninstall.ps1 (same algorithm, inline) ---
foreach ($chg in $changes) {
    $inSection = $false
    $lines = @($lines | ForEach-Object {
        if ($_ -match '^\s*\[(.+)\]\s*$') { $inSection = ($Matches[1] -eq $chg.section); $_ }
        elseif ($inSection -and $_ -match "^\s*$([regex]::Escape($chg.key))\s*=") {
            if ($null -ne $chg.previous -and "$($chg.previous)" -ne "") { "$($chg.key)=$($chg.previous)" }
        }
        else { $_ }
    })
}
$cleaned = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*\[.+\]\s*$') {
        $j = $i + 1
        while ($j -lt $lines.Count -and $lines[$j] -notmatch '^\s*\[.+\]\s*$') { $j++ }
        $body = if ($j -gt $i + 1) { $lines[($i + 1)..($j - 1)] | Where-Object { $_ -and $_.Trim() } } else { @() }
        if ($body) { $cleaned.AddRange([string[]]$lines[$i..($j - 1)]) }
        $i = $j - 1
    } else { $cleaned.Add($lines[$i]) }
}
Write-Host "--- reverted ---"
$cleaned | ForEach-Object { Write-Host $_ }

$rev = $cleaned -join "`n"
Assert ($rev -match '(?m)^memory=12GB$') "memory restored to 12GB"
Assert ($rev -notmatch 'kernel=') "kernel line removed"
Assert ($rev -notmatch 'sparseVhd') "sparseVhd removed"
Assert ($rev -notmatch '\[experimental\]') "empty experimental section removed"
Assert ($rev -match '(?m)^processors=4$') "unrelated key still there"
Assert ($rev -match '(?m)^\[interop\]$') "interop section still there"
Assert ($rev -match '(?m)^# my notes$') "comment still there"

Write-Host "ALL MERGE/REVERT TESTS PASS" -ForegroundColor Green
