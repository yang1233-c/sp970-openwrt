[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu',
    [string]$LinuxSource = $env:Q410_OPENWRT_TREE,
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
if (-not $LinuxSource) {
    throw 'Set Q410_OPENWRT_TREE or pass -LinuxSource with the WSL OpenWrt tree.'
}
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputDir) {
    $OutputDir = Join-Path (Split-Path $Root) 'artifacts\A-SP970-openwrt-25.12.5-perf-fix-persistent-root-20260812'
}
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Convert-ToWslPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^([A-Za-z]):\\(.*)$') { throw "Expected a Windows path: $full" }
    return '/mnt/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\', '/')
}

$compileScript = Convert-ToWslPath (Join-Path $PSScriptRoot 'compile-sp970-dtb.sh')
& wsl.exe -d $Distro -- sh $compileScript $LinuxSource
if ($LASTEXITCODE -ne 0) { throw "DTB build failed with exit code $LASTEXITCODE" }

$uncRoot = '\\wsl.localhost\' + $Distro + ($LinuxSource -replace '/', '\')
$kernelBuild = Get-ChildItem -LiteralPath (Join-Path $uncRoot 'build_dir\target-aarch64_cortex-a53_musl\linux-msm89xx_msm8916') -Directory |
    Where-Object Name -Match '^linux-[0-9]' | Select-Object -First 1
if (-not $kernelBuild) { throw 'Linux kernel build directory was not found.' }

$image = Join-Path $kernelBuild.FullName 'arch\arm64\boot\Image'
$dtb = Join-Path $kernelBuild.FullName 'arch\arm64\boot\dts\qcom\msm8916-gexing-sp970.dtb'
$config = Join-Path $kernelBuild.FullName '.config'
foreach ($input in @($image, $dtb, $config)) {
    if (-not (Test-Path -LiteralPath $input -PathType Leaf)) { throw "Missing build input: $input" }
}

$resolved = Get-Content -LiteralPath $config -Raw
foreach ($required in @(
    'CONFIG_QCOM_A53PLL=y', 'CONFIG_QCOM_CLK_APCS_MSM8916=y',
    'CONFIG_CPU_FREQ=y', 'CONFIG_CPUFREQ_DT=y', 'CONFIG_EXT4_FS=y',
    'CONFIG_DEVTMPFS=y', 'CONFIG_DEVTMPFS_MOUNT=y',
    'CONFIG_QCOM_RMTFS_MEM=y', 'CONFIG_QCOM_PD_MAPPER=y',
    'CONFIG_RPMSG_WWAN_CTRL=y', 'CONFIG_INITRAMFS_SOURCE=""'
)) {
    if ($resolved -notmatch "(?m)^$([regex]::Escape($required))$") {
        throw "Persistent-root RAM kernel invariant missing: $required"
    }
}
if ($resolved -notmatch '(?m)^CONFIG_EXTRA_FIRMWARE="[^"]*wcnss\.mdt[^"]*"$') {
    throw 'Persistent-root RAM kernel does not contain the early WCN firmware set.'
}

$kernelOut = Join-Path $OutputDir 'kernel-persistent-root.bin.gz'
$dtbOut = Join-Path $OutputDir 'msm8916-gexing-sp970.dtb'
$configOut = Join-Path $OutputDir 'kernel-persistent-root.config'
$imageOut = Join-Path $OutputDir 'A-SP970-OpenWrt-25.12.5-perf-fix-fastboot.img'
Copy-Item -LiteralPath $dtb -Destination $dtbOut -Force
Copy-Item -LiteralPath $config -Destination $configOut -Force

# Match the established persistent build: gzip -n -9 leaves no timestamp/name.
$wslImage = $LinuxSource + '/build_dir/target-aarch64_cortex-a53_musl/linux-msm89xx_msm8916/' + $kernelBuild.Name + '/arch/arm64/boot/Image'
$wslKernelOut = Convert-ToWslPath $kernelOut
& wsl.exe -d $Distro -- sh -c "gzip -n -9 -c '$wslImage' > '$wslKernelOut'"
if ($LASTEXITCODE -ne 0) { throw "Kernel gzip failed with exit code $LASTEXITCODE" }

$cmdline = 'earlycon console=ttyMSM0,115200n8 root=/dev/mmcblk0p14 rootfstype=ext4 rootwait rw no_framebuffer=true'
$workspace = Split-Path $Root
$basePath = Join-Path $workspace 'artifacts\A-SP970-openwrt-25.12.5-initramfs-20260810\A-SP970-OpenWrt-25.12.5-initramfs-ncm19-led2-status-leds-lk1st.img'
$expectedBaseHash = 'E3A2B3D1847314B13ED81410E7EA824D613B6EAD2992ED1C857EDA792AC61150'
if (-not (Test-Path -LiteralPath $basePath -PathType Leaf)) { throw "Missing stable LK1ST base image: $basePath" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $basePath).Hash -ne $expectedBaseHash) {
    throw 'Stable LK1ST base image hash mismatch.'
}

# Preserve the exact layout of the deployed stable image: Android boot v0 with
# dt_size=0 and a single raw DTB appended directly to the gzip kernel payload.
$base = [IO.File]::ReadAllBytes($basePath)
$pageBytes = [BitConverter]::ToUInt32($base, 36)
$baseKernelBytes = [BitConverter]::ToUInt32($base, 8)
$baseRamdiskBytes = [BitConverter]::ToUInt32($base, 16)
$baseSecondBytes = [BitConverter]::ToUInt32($base, 24)
$baseHeaderDtbBytes = [BitConverter]::ToUInt32($base, 40)
if ([Text.Encoding]::ASCII.GetString($base, 0, 8) -ne 'ANDROID!' -or
    $pageBytes -ne 2048 -or $baseRamdiskBytes -ne 0 -or
    $baseSecondBytes -ne 0 -or $baseHeaderDtbBytes -ne 0) {
    throw 'Stable LK1ST base image layout mismatch.'
}
$stableFdtOffset = -1
for ($i = $pageBytes; $i -le ($pageBytes + $baseKernelBytes - 4); $i++) {
    if ($base[$i] -eq 0xD0 -and $base[$i + 1] -eq 0x0D -and
        $base[$i + 2] -eq 0xFE -and $base[$i + 3] -eq 0xED) { $stableFdtOffset = $i; break }
}
if ($stableFdtOffset -lt $pageBytes) { throw 'Stable appended DTB was not found.' }
$stableDtbBytes = $pageBytes + $baseKernelBytes - $stableFdtOffset
$stableDtb = [byte[]]::new($stableDtbBytes)
[Array]::Copy($base, $stableFdtOffset, $stableDtb, 0, $stableDtbBytes)
$compiledDtb = [IO.File]::ReadAllBytes($dtbOut)
$sha256 = [Security.Cryptography.SHA256]::Create()
try {
    $stableDtbHash = [BitConverter]::ToString($sha256.ComputeHash($stableDtb)).Replace('-', '')
    $compiledDtbHash = [BitConverter]::ToString($sha256.ComputeHash($compiledDtb)).Replace('-', '')
} finally { $sha256.Dispose() }
if ($stableDtbHash -ne $compiledDtbHash) { throw 'Compiled DTB differs from the deployed stable DTB tail.' }

$kernelGzip = [IO.File]::ReadAllBytes($kernelOut)
$kernelPayload = [byte[]]::new($kernelGzip.Length + $compiledDtb.Length)
[Array]::Copy($kernelGzip, 0, $kernelPayload, 0, $kernelGzip.Length)
[Array]::Copy($compiledDtb, 0, $kernelPayload, $kernelGzip.Length, $compiledDtb.Length)
$header = [byte[]]::new($pageBytes)
[Array]::Copy($base, 0, $header, 0, $pageBytes)
[Array]::Copy([BitConverter]::GetBytes([uint32]$kernelPayload.Length), 0, $header, 8, 4)
[Array]::Clear($header, 48, 16)
$nameBytes = [Text.Encoding]::ASCII.GetBytes('SP970-CPUF')
[Array]::Copy($nameBytes, 0, $header, 48, $nameBytes.Length)
[Array]::Clear($header, 64, 512)
$cmdlineBytes = [Text.Encoding]::ASCII.GetBytes($cmdline)
[Array]::Copy($cmdlineBytes, 0, $header, 64, $cmdlineBytes.Length)

$digestInput = [byte[]]::new($kernelPayload.Length + 12)
[Array]::Copy($kernelPayload, 0, $digestInput, 0, $kernelPayload.Length)
[Array]::Copy([BitConverter]::GetBytes([uint32]$kernelPayload.Length), 0, $digestInput, $kernelPayload.Length, 4)
$sha1 = [Security.Cryptography.SHA1]::Create()
try { $bootId = $sha1.ComputeHash($digestInput) } finally { $sha1.Dispose() }
[Array]::Clear($header, 576, 32)
[Array]::Copy($bootId, 0, $header, 576, $bootId.Length)

$unpaddedBytes = $pageBytes + $kernelPayload.Length
$imageBytes = [int]([math]::Ceiling($unpaddedBytes / [double]$pageBytes) * $pageBytes)
$boot = [byte[]]::new($imageBytes)
[Array]::Copy($header, 0, $boot, 0, $header.Length)
[Array]::Copy($kernelPayload, 0, $boot, $pageBytes, $kernelPayload.Length)
[IO.File]::WriteAllBytes($imageOut, $boot)

$magic = [Text.Encoding]::ASCII.GetString($boot, 0, 8)
$kernelBytes = [BitConverter]::ToUInt32($boot, 8)
$ramdiskBytes = [BitConverter]::ToUInt32($boot, 16)
$headerDtbBytes = [BitConverter]::ToUInt32($boot, 40)
$fdtOffset = $pageBytes + $kernelGzip.Length
$partitionBytes = 16MB
$verification = [ordered]@{
    Magic = $magic
    ImageBytes = $boot.Length
    PartitionBytes = $partitionBytes
    HeadroomBytes = $partitionBytes - $boot.Length
    KernelBytes = $kernelBytes
    KernelGzipBytes = $kernelGzip.Length
    RamdiskBytes = $ramdiskBytes
    DtbBytes = $compiledDtb.Length
    DtbSha256 = $compiledDtbHash
    DtbLayout = 'raw DTB appended to gzip kernel (deployed stable layout)'
    HeaderDtbBytes = $headerDtbBytes
    EmbeddedFdtOffset = $fdtOffset
    StableBaseSha256 = $expectedBaseHash
    KernelBoot = 'fastboot RAM-only'
    Rootfs = '/dev/mmcblk0p14 (existing persistent ext4, rw)'
    Cmdline = $cmdline
    Under16MiB = ($boot.Length -lt $partitionBytes)
}
if ($magic -ne 'ANDROID!' -or $ramdiskBytes -ne 0 -or -not $verification.Under16MiB -or
    $headerDtbBytes -ne 0 -or $kernelBytes -ne ($kernelGzip.Length + $compiledDtb.Length) -or
    $boot[$fdtOffset] -ne 0xD0 -or $boot[$fdtOffset + 1] -ne 0x0D -or
    $boot[$fdtOffset + 2] -ne 0xFE -or $boot[$fdtOffset + 3] -ne 0xED) {
    throw 'Packaged persistent-root RAM kernel failed stable-layout, FDT, or size validation.'
}
$verification | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDir 'boot-image-verification.json') -Encoding UTF8

$hashRows = Get-ChildItem -LiteralPath $OutputDir -File |
    Where-Object Name -NE 'SHA256SUMS.csv' | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ File = $_.Name; Bytes = $_.Length; SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    }
$hashRows | Export-Csv -LiteralPath (Join-Path $OutputDir 'SHA256SUMS.csv') -NoTypeInformation -Encoding UTF8
$verification
