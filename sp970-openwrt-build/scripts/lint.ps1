[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fail = New-Object System.Collections.Generic.List[string]
function Need([string]$p) { if (-not (Test-Path -LiteralPath (Join-Path $Root $p))) { $fail.Add("missing: $p") } }

@(
    'README.md', 'SOURCE-LOCK.md', 'HERMES-DOWNLOADS.md',
    'config/seed.config', 'config/initramfs.config', 'config/initramfs-seed.config',
    'target/linux/msm89xx/Makefile', 'target/linux/msm89xx/config-6.12',
    'target/linux/msm89xx/msm8916/target.mk',
    'target/linux/msm89xx/image/Makefile', 'target/linux/msm89xx/dts/msm8916-gexing-sp970.dts',
    'target/linux/msm89xx/files-6.12/arch/arm64/boot/dts/qcom/msm8916-gexing-sp970.dts',
    'target/linux/msm89xx/sp970-preserved-gpt.cmdline',
    'package/firmware/sp970-firmware/Makefile',
    'package/network/utils/q410qmi/Makefile',
    'patches/openwrt/0001-mac80211-add-wcn36xx-package.patch',
    'files/etc/config/network', 'files/etc/config/wireless', 'files/etc/config/dhcp',
    'files/etc/config/firewall', 'files/etc/config/system', 'files/etc/uci-defaults/99-sp970'
) | ForEach-Object { Need $_ }

$dtbFactsPath = Join-Path $Root 'facts/SP970-openstick-dtb.json'
if (Test-Path -LiteralPath $dtbFactsPath) {
    $dtbFacts = Get-Content $dtbFactsPath -Raw | ConvertFrom-Json
    if ($dtbFacts.sha256 -ne '35BB2D3648D8C26F3379C5CCC05CCCE3E021C36150102C9815B2BACDA45A4D42') { $fail.Add('DTB fact hash changed') }
    if ($dtbFacts.root.model -ne 'Handsome OpenStick SP970') { $fail.Add('DTB model mismatch') }
    if (-not ($dtbFacts.root.compatible -contains 'qcom,msm8916')) { $fail.Add('DTB compatible missing qcom,msm8916') }
}
$gptFactsPath = Join-Path $Root 'facts/A-SP970-gpt.json'
if (Test-Path -LiteralPath $gptFactsPath) {
    $gpt = Get-Content $gptFactsPath -Raw | ConvertFrom-Json
    $system = $gpt.partitions | Where-Object name -eq 'system'
    $userdata = $gpt.partitions | Where-Object name -eq 'userdata'
    if ($system.length_bytes -ne 838860800) { $fail.Add('system size mismatch') }
    if ($userdata.length_bytes -ne 2665938432) { $fail.Add('userdata size mismatch') }
}

$seed = Get-Content (Join-Path $Root 'config/seed.config') -Raw
foreach ($bad in @('docker','dockerd','luci-app-dockerman','luci-lib-docker','luci-app-openclash','luci-app-adguardhome','adguardhome','samba4-server','luci-app-samba4','aria2','luci-app-aria2')) {
    if ($seed -match "(?m)^CONFIG_PACKAGE_$([regex]::Escape($bad))=y$") { $fail.Add("forbidden package selected: $bad") }
}
$scanDirs = @('config','files','target','package') | ForEach-Object { Join-Path $Root $_ }
$scanFiles = Get-ChildItem $scanDirs -Recurse -File -ErrorAction SilentlyContinue
foreach ($f in $scanFiles) {
    $text = Get-Content -LiteralPath $f.FullName -Raw
    if ($text -match '(?i)\bsleep\s+25\b') { $fail.Add("sleep 25 found in $($f.FullName)") }
}

$fallback = @{
    'source-cache/openwrt-25.12.4.tar.gz' = 'FD8B78EC4675C8B19831EBF0299335F5C65CAA60E34655490A8979720633EE2D'
    'source-cache/linux-6.12.87.tar.xz' = 'CC12A7644B4CEF9E06627B29DE8753E22B3D076703A9B52BE84263E05C8B9830'
}
foreach ($pair in $fallback.GetEnumerator()) {
    $path = Join-Path $Root $pair.Key
    if (Test-Path -LiteralPath $path) {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant()
        if ($actual -ne $pair.Value) { $fail.Add("fallback hash mismatch: $($pair.Key)") }
    }
}

if ($fail.Count) { $fail | ForEach-Object { Write-Error $_ }; exit 1 }
Write-Host 'SP970 offline lint PASS: public structure, optional local facts/cache, package policy and sleep invariant verified.'
