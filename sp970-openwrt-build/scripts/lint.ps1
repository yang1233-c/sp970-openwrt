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
    'package/utils/qcom-modem-daemons/Makefile',
    'package/utils/qcom-modem-daemons/UPSTREAM.md',
    'patches/openwrt/0001-mac80211-add-wcn36xx-package.patch',
    'scripts/package-persistent-root-ramkernel-from-wsl.ps1',
    'files/usr/sbin/q410-sim-profile',
    'files/etc/config/network', 'files/etc/config/wireless', 'files/etc/config/dhcp',
    'files/etc/hotplug.d/net/95-q410-cellular',
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
if ($seed -notmatch '(?m)^# CONFIG_TARGET_ROOTFS_INITRAMFS is not set$') {
    $fail.Add('persistent seed must explicitly disable TARGET_ROOTFS_INITRAMFS')
}
if ($seed -notmatch '(?m)^CONFIG_PACKAGE_qcom-modem-daemons=y$') {
    $fail.Add('persistent image must source-build the rmtfs and tqftpserv daemons')
}
$initramfsSeed = Get-Content (Join-Path $Root 'config/initramfs-seed.config') -Raw
if ($initramfsSeed -notmatch '(?m)^CONFIG_TARGET_ROOTFS_INITRAMFS=y$') {
    $fail.Add('RAM seed must enable TARGET_ROOTFS_INITRAMFS')
}

# Performance invariants. APCS consumes the A53 PLL as its CPU clock parent;
# omitting the PLL leaves both APCS and cpufreq-dt deferred indefinitely.
$kernelConfig = Get-Content (Join-Path $Root 'target/linux/msm89xx/config-6.12') -Raw
foreach ($required in @('CONFIG_QCOM_A53PLL=y', 'CONFIG_QCOM_CLK_APCS_MSM8916=y', 'CONFIG_CPU_FREQ=y', 'CONFIG_CPUFREQ_DT=y')) {
    if ($kernelConfig -notmatch "(?m)^$([regex]::Escape($required))$") { $fail.Add("kernel performance invariant missing: $required") }
}

$firewall = Get-Content (Join-Path $Root 'files/etc/config/firewall') -Raw
if ($firewall -notmatch "(?m)^\s*option\s+flow_offloading\s+'1'\s*$") {
    $fail.Add('software flow offloading is not enabled in firewall defaults')
}
if ($firewall -match "(?m)^\s*option\s+flow_offloading_hw\s+'1'\s*$") {
    $fail.Add('hardware flow offloading must stay disabled on MSM8916')
}

$network = Get-Content (Join-Path $Root 'files/etc/config/network') -Raw
foreach ($auto in @("option apn 'auto'", "option aid 'auto'")) {
    if ($network -notmatch "(?m)^\s*$([regex]::Escape($auto))\s*$") { $fail.Add("cellular auto-profile invariant missing: $auto") }
}
foreach ($binding in @("option device 'wwan0'", "option qmi_device '/dev/wwan0qmi0'")) {
    if ($network -notmatch "(?m)^\s*$([regex]::Escape($binding))\s*$") { $fail.Add("cellular device binding invariant missing: $binding") }
}
$system = Get-Content (Join-Path $Root 'files/etc/config/system') -Raw
if ($system -notmatch "(?m)^config timeserver 'ntp'$" -or
    $system -notmatch "(?m)^\s*option enabled '1'$" -or
    $system -notmatch "(?m)^\s*list server '0\.openwrt\.pool\.ntp\.org'$") {
    $fail.Add('NTP client defaults are incomplete')
}
$q410Proto = Get-Content (Join-Path $Root 'files/lib/netifd/proto/q410qmi.sh') -Raw
if ($q410Proto -notmatch '(?m)^\s*UIM_\*\|SIM_\*\|APN_\*\) proto_block_restart') {
    $fail.Add('q410qmi deterministic failure restart block is missing')
}
if ($q410Proto -match '(?m)^\s*no_device=1\s*$' -or
    $q410Proto -notmatch '(?m)^\s*proto_config_add_string qmi_device\s*$') {
    $fail.Add('q410qmi must bind netifd device separately from the QMI control endpoint')
}
$q410Hotplug = Get-Content (Join-Path $Root 'files/etc/hotplug.d/net/95-q410-cellular') -Raw
if ($q410Hotplug -notmatch '(?m)^\[ "\$\{INTERFACE:-\}" = wwan0 \]' -or
    $q410Hotplug -notmatch '(?m)^\s*ifup cellular\s*$') {
    $fail.Add('q410 wwan0 late-enumeration hotplug retry is incomplete')
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
