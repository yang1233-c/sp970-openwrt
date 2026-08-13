[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if ($OutputRoot.StartsWith($SourceRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must be outside the private engineering workspace.'
}
if (Test-Path -LiteralPath $OutputRoot) {
    if (@(Get-ChildItem -LiteralPath $OutputRoot -Force).Count) {
        throw "OutputRoot must be absent or empty: $OutputRoot"
    }
} else {
    New-Item -ItemType Directory -Path $OutputRoot | Out-Null
}

function Copy-Relative([string]$Relative) {
    $source = Join-Path $SourceRoot $Relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing public source file: $Relative"
    }
    $target = Join-Path $OutputRoot $Relative
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
}

function Copy-Tree([string]$Relative) {
    $source = Join-Path $SourceRoot $Relative
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Missing public source tree: $Relative"
    }
    Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object {
        if ($_.FullName -match '[\\/]__pycache__[\\/]' -or $_.Extension -eq '.pyc') { return }
        $child = $_.FullName.Substring($SourceRoot.Length + 1)
        Copy-Relative $child
    }
}

@(
    '.gitattributes', '.gitignore', 'README.md', 'LICENSE', 'NOTICE.md',
    'SECURITY.md', 'docs\STATUS.md', 'docs\ROLLBACK.md',
    'docs\PUBLIC-RELEASE-AUDIT.md',
    'docs\2026-08-13-SP970-OpenWrt-QCN-lessons.md',
    'docs\2026-08-13-SP970-QCN-policy-and-redaction.md',
    'manifests\q410-qcn-redacted-assets.json',
    'sp970-openwrt-build\README.md',
    'sp970-openwrt-build\SOURCE-LOCK.md',
    'sp970-openwrt-build\HERMES-DOWNLOADS.md',
    'tools\Build-A-NCM19-Persistent-Wwan.sh',
    'tools\Invoke-A-Q410-Persistent-Wwan.ps1',
    'tools\q410-quiesce-qmi-pollers.sh',
    'tools\Patch-A-SP970-Rootfs-ModemRuntime.sh',
    'tests\test-q410-sim-profile.sh',
    'A-openstick-conversion\pack-ncm19-persistent-wwan.py'
) | ForEach-Object { Copy-Relative $_ }

@(
    'sp970-openwrt-build\config',
    'sp970-openwrt-build\files',
    'sp970-openwrt-build\package',
    'sp970-openwrt-build\patches',
    'sp970-openwrt-build\scripts',
    'sp970-openwrt-build\target',
    'baselines\ncm16\overlay',
    'baselines\ncm19\overlay'
) | ForEach-Object { Copy-Tree $_ }

$baselineReadme = @'
# Immutable runtime overlay

This directory contains selected runtime files extracted byte-for-byte from an
immutable comparison image. The image itself, host paths and raw evidence are
excluded from the public repository. See the root README for the corresponding
image SHA-256 and provenance boundary.
'@
foreach ($name in 'ncm16','ncm19') {
    $path = Join-Path $OutputRoot "baselines\$name\README.md"
    [IO.File]::WriteAllText($path, $baselineReadme,
        (New-Object Text.UTF8Encoding($false)))
}

# The public tree ships source and the OpenWrt package, not locally built ELF
# files. Fail closed if a future overlay reintroduces them.
$forbiddenBinaries = @(
    'sp970-openwrt-build\files\usr\sbin\q410-qmi-uim-provision',
    'sp970-openwrt-build\files\usr\sbin\q410-qmi-wds-connect',
    'sp970-openwrt-build\files\usr\sbin\rmtfs',
    'sp970-openwrt-build\files\usr\bin\tqftpserv'
)
foreach ($relative in $forbiddenBinaries) {
    if (Test-Path -LiteralPath (Join-Path $OutputRoot $relative)) {
        throw "Unstripped local binary entered public tree: $relative"
    }
}

$rules = [ordered]@{
    private_key = 'BEGIN\s+(?:RSA\s+|OPENSSH\s+|EC\s+|DSA\s+)?PRIVATE KEY'
    provider_token = '(?:AKIA|ASIA)[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}'
    authorization = 'Authorization:\s*(?:Bearer|Basic)\s+[A-Za-z0-9+/=_-]{8,}'
    credential_assignment = '(?i)(?:password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token)\s*[=:]\s*["'']?[^\s"''#,;]{6,}'
    long_decimal_identifier = '(?<![0-9])[0-9]{14,22}(?![0-9])'
    windows_user_path = '(?i)[A-Z]:\\Users\\'
    private_linux_home = '/home/(?!USER(?:/|\b))[a-z_][a-z0-9_-]*(?:/|\b)'
    wsl_user_path = '(?i)/mnt/[a-z]/Users/'
    private_backup_drive = '(?i)(?:backup|archive)[_-]?drive\s*[=:]\s*[A-Z]:\\'
    private_key_path = '(?i)(?:id_rsa|id_ed25519|MP1800X-40|target_known_hosts)'
    labeled_device_identity = '(?im)(?:fastboot[_ -]?serial|serialno|emmc[_ -]?cid)\s*[=:]\s*[0-9a-f]{8,32}'
    private_rf_bssid = '(?i)(?:08:97:58:2b:46:e8|64:64:4a:e2:18:a[cd]|f8:c9:03:2b:45:c4|80:8f:1d:63:24:ec)'
}

$findings = New-Object Collections.Generic.List[object]
$binaryFiles = New-Object Collections.Generic.List[string]
$files = @(Get-ChildItem -LiteralPath $OutputRoot -Recurse -File)
foreach ($file in $files) {
    if ($file.Length -gt 1MB) {
        $findings.Add([pscustomobject]@{ Rule='oversize'; Path=$file.FullName; Match=$file.Length })
        continue
    }
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes -contains 0) {
        $binaryFiles.Add($file.FullName.Substring($OutputRoot.Length + 1))
        continue
    }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    foreach ($entry in $rules.GetEnumerator()) {
        if ($file.Name -eq '.gitignore' -and $entry.Key -eq 'private_key_path') { continue }
        foreach ($match in [regex]::Matches($text, $entry.Value)) {
            $findings.Add([pscustomobject]@{
                Rule = $entry.Key
                Path = $file.FullName.Substring($OutputRoot.Length + 1)
                Match = $match.Value
            })
        }
    }
}
if ($binaryFiles.Count) {
    foreach ($path in $binaryFiles) {
        $findings.Add([pscustomobject]@{ Rule='binary'; Path=$path; Match='NUL byte' })
    }
}
if ($findings.Count) {
    $findings | Format-Table -AutoSize | Out-String | Write-Error
    throw "PUBLIC_RELEASE_AUDIT_FAILED findings=$($findings.Count)"
}

$manifestPath = Join-Path $OutputRoot 'PUBLIC-MANIFEST.sha256'
$manifest = Get-ChildItem -LiteralPath $OutputRoot -Recurse -File |
    Where-Object FullName -NE $manifestPath |
    Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($OutputRoot.Length + 1).Replace('\','/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
[IO.File]::WriteAllLines($manifestPath, $manifest,
    (New-Object Text.UTF8Encoding($false)))

$audit = [ordered]@{
    schema = 'q410-public-release-audit-v1'
    generated_at = (Get-Date).ToString('o')
    source_commit = (& git -C $SourceRoot rev-parse HEAD).Trim()
    publication_model = 'new-root-commit; private engineering history excluded'
    files = $files.Count + 2
    bytes = (Get-ChildItem -LiteralPath $OutputRoot -Recurse -File |
        Measure-Object Length -Sum).Sum
    sensitive_findings = 0
    binary_files = 0
    manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
}
$audit | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (
    Join-Path $OutputRoot 'PUBLIC-AUDIT.json') -Encoding UTF8

Write-Output ("PUBLIC_RELEASE_AUDIT_PASS root={0} files={1} bytes={2}" -f
    $OutputRoot, $audit.files, $audit.bytes)
