[CmdletBinding()]
param(
    [switch]$Extract,
    [switch]$AllowFallback,
    [string]$CacheDir = (Join-Path $PSScriptRoot '..\source-cache'),
    [string]$WorkDir = (Join-Path $PSScriptRoot '..\.work')
)

$ErrorActionPreference = 'Stop'
$MaxDirectBytes = 1GB
$sources = @(
    [ordered]@{
        Name = 'openwrt-25.12.5.tar.gz'
        Url = 'https://github.com/openwrt/openwrt/archive/refs/tags/v25.12.5.tar.gz'
        Sha256 = '19462C4D0D52824B33AE52F60EE5E66528BF103691AABDB5E1E15CC8924067DF'
        ExpectedBytes = 11564496
        ExtractRoot = 'openwrt-25.12.5'
    },
    [ordered]@{
        Name = 'linux-6.12.94.tar.xz'
        Url = 'https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.94.tar.xz'
        Sha256 = 'E998A232B9418DB3301CB58468E291A4F41D6AB8306029B30D991F56251DC8D2'
        ExpectedBytes = 148301108
        ExtractRoot = 'linux-6.12.94'
    }
)
$fallback = @{
    'openwrt' = 'openwrt-25.12.4.tar.gz'
    'linux' = 'linux-6.12.87.tar.xz'
}

New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
foreach ($source in $sources) {
    $file = Join-Path $CacheDir $source.Name
    if (-not (Test-Path -LiteralPath $file)) {
        $head = Invoke-WebRequest -Method Head -UseBasicParsing -Uri $source.Url
        $advertised = 0L
        if ($head.Headers['Content-Length']) { [Int64]::TryParse($head.Headers['Content-Length'], [ref]$advertised) | Out-Null }
        $limit = if ($advertised -gt 0) { $advertised } elseif ($source.ExpectedBytes) { [Int64]$source.ExpectedBytes } else { [Int64]$source.ExpectedMaxBytes }
        if ($limit -gt $MaxDirectBytes) { throw "Download exceeds the 1 GiB direct-fetch limit: $($source.Url)" }
        Write-Host "Downloading $($source.Url)"
        Invoke-WebRequest -UseBasicParsing -Uri $source.Url -OutFile $file
    }
    $item = Get-Item -LiteralPath $file
    if ($item.Length -gt $MaxDirectBytes) { throw "Downloaded $file is over 1 GiB" }
    if ($source.ExpectedBytes -and $item.Length -ne [Int64]$source.ExpectedBytes) {
        throw "Size mismatch for ${file}: got $($item.Length), expected $($source.ExpectedBytes)"
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToUpperInvariant()
    if ($source.Sha256 -and $hash -ne $source.Sha256) { throw "SHA256 mismatch for $file" }
    Write-Host ("verified {0} {1} bytes SHA256={2}" -f $file, $item.Length, $hash)
}

if (-not $Extract) { exit 0 }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$openwrt = Join-Path $CacheDir 'openwrt-25.12.5.tar.gz'
$linux = Join-Path $CacheDir 'linux-6.12.94.tar.xz'
if (-not (Test-Path -LiteralPath $openwrt) -or -not (Test-Path -LiteralPath $linux)) {
    if (-not $AllowFallback) { throw 'Current v25.12.5/6.12.94 archives are not cached; rerun without -Extract or pass -AllowFallback explicitly.' }
    Write-Warning 'Using fallback cache is not a current-baseline build.'
    $openwrt = Join-Path $CacheDir $fallback.openwrt
    $linux = Join-Path $CacheDir $fallback.linux
}
$openwrtOut = Join-Path $WorkDir 'openwrt'
if (-not (Test-Path -LiteralPath $openwrtOut)) {
    tar -xzf $openwrt -C $WorkDir
    $root = Get-ChildItem -LiteralPath $WorkDir -Directory | Where-Object Name -like 'openwrt-*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($root) { Move-Item -LiteralPath $root.FullName -Destination $openwrtOut }
}
$linuxOut = Join-Path $WorkDir 'linux'
if (-not (Test-Path -LiteralPath $linuxOut)) {
    tar -xJf $linux -C $WorkDir
    $root = Get-ChildItem -LiteralPath $WorkDir -Directory | Where-Object Name -like 'linux-*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($root) { Move-Item -LiteralPath $root.FullName -Destination $linuxOut }
}
Write-Host "sources extracted under $WorkDir (no device operation performed)"
