[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [int]$Jobs = 2,
    [switch]$Initramfs,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Source = (Resolve-Path $SourceDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $Source 'include/version.mk'))) {
    throw "SourceDir does not look like an extracted OpenWrt tree: $Source"
}
if ($Source -match '(?i)(com[0-9]|fastboot|edl|adb)') { throw 'SourceDir must be a local OpenWrt source tree' }

function Stage-Tree([string]$relative) {
    $from = Join-Path $Root $relative
    $to = Join-Path $Source $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination $to -Recurse -Force }
}

Stage-Tree 'target/linux/msm89xx'
Stage-Tree 'package/firmware/sp970-firmware'
Stage-Tree 'package/network/utils/q410qmi'
Stage-Tree 'package/utils/qcom-modem-daemons'
Stage-Tree 'files'

$openWrtPatch = Join-Path $Root 'patches/openwrt/0001-mac80211-add-wcn36xx-package.patch'
if (Test-Path -LiteralPath $openWrtPatch) {
    & git -C $Source apply --check $openWrtPatch 2>$null
    if ($LASTEXITCODE -eq 0) {
        & git -C $Source apply $openWrtPatch
        if ($LASTEXITCODE -ne 0) { throw "OpenWrt patch failed: $openWrtPatch" }
    } else {
        & git -C $Source apply --reverse --check $openWrtPatch 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "OpenWrt patch is neither applicable nor already present: $openWrtPatch"
        }
    }
}

$seedName = if ($Initramfs) { 'config/initramfs-seed.config' } else { 'config/seed.config' }
$seed = Join-Path $Root $seedName
$config = Join-Path $Source '.config'
Copy-Item -LiteralPath $seed -Destination $config -Force

$commands = @(
    "make defconfig",
    "make -j$Jobs world V=s"
)
if ($DryRun) {
    Write-Host "SourceDir: $Source"
    Write-Host "Staged target, firmware hook and files overlay."
    $commands | ForEach-Object { Write-Host "DRY-RUN: $_" }
    exit 0
}

Push-Location $Source
try {
    & make defconfig
    if ($LASTEXITCODE -ne 0) { throw "make defconfig failed with exit code $LASTEXITCODE" }
    & make "-j$Jobs" world V=s
    if ($LASTEXITCODE -ne 0) { throw "make world failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }
Write-Host 'Build completed; inspect bin/targets/msm89xx/ before any separate RAM-only validation.'
