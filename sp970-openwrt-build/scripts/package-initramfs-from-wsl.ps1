[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu',
    [string]$LinuxSource = $env:Q410_OPENWRT_TREE,
    [string]$OutputDir,
    [string]$PythonPath = 'python'
)

$ErrorActionPreference = 'Stop'
$LinuxSource = if ($LinuxSource) { $LinuxSource } else { '/home/' + $env:USERNAME.ToLowerInvariant() + '/q410/openwrt-25.12.5' }
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputDir) {
    $OutputDir = Join-Path (Split-Path $Root) 'artifacts\A-SP970-openwrt-25.12.5-initramfs-20260810'
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
$targetDir = Join-Path $uncRoot 'bin\targets\msm89xx\msm8916'
$kernelBuild = Get-ChildItem -LiteralPath (Join-Path $uncRoot 'build_dir\target-aarch64_cortex-a53_musl\linux-msm89xx_msm8916') -Directory |
    Where-Object Name -Match '^linux-[0-9]' | Select-Object -First 1
if (-not $kernelBuild) { throw 'Linux kernel build directory was not found.' }

$inputs = @{
    Kernel = Join-Path $targetDir 'openwrt-msm89xx-msm8916-sp970-initramfs-kernel.bin'
    Manifest = Join-Path $targetDir 'openwrt-msm89xx-msm8916-sp970.manifest'
    Config = Join-Path $uncRoot '.config'
    Dtb = Join-Path $kernelBuild.FullName 'arch\arm64\boot\dts\qcom\msm8916-gexing-sp970.dtb'
}
foreach ($item in $inputs.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $item.Value -PathType Leaf)) { throw "Missing $($item.Key): $($item.Value)" }
}

$kernelOut = Join-Path $OutputDir 'kernel-initramfs.bin.gz'
$dtbOut = Join-Path $OutputDir 'msm8916-gexing-sp970.dtb'
$configOut = Join-Path $OutputDir 'openwrt-resolved.config'
$manifestOut = Join-Path $OutputDir 'openwrt-sp970.manifest'
$imageOut = Join-Path $OutputDir 'A-SP970-OpenWrt-25.12.5-initramfs-fastboot.img'

Copy-Item -LiteralPath $inputs.Kernel -Destination $kernelOut -Force
Copy-Item -LiteralPath $inputs.Dtb -Destination $dtbOut -Force
Copy-Item -LiteralPath $inputs.Config -Destination $configOut -Force
Copy-Item -LiteralPath $inputs.Manifest -Destination $manifestOut -Force

$gzip = [IO.File]::ReadAllBytes($kernelOut)
if ($gzip.Length -lt 2 -or $gzip[0] -ne 0x1f -or $gzip[1] -ne 0x8b) {
    throw 'Kernel payload does not have a gzip header.'
}

$partitionBytes = 16MB
& $PythonPath (Join-Path $PSScriptRoot 'make-android-boot.py') `
    --kernel $kernelOut --dtb $dtbOut --dtb-mode qcdt-v2 --output $imageOut `
    --cmdline 'earlycon console=ttyMSM0,115200n8 rdinit=/sbin/init no_framebuffer=true' `
    --kernel-addr 0x80080000 --ramdisk-addr 0x82000000 --tags-addr 0x81E00000 `
    --name 'SP970-OWRT' --partition-bytes $partitionBytes
if ($LASTEXITCODE -ne 0) { throw "Android boot packaging failed with exit code $LASTEXITCODE" }

$image = [IO.File]::ReadAllBytes($imageOut)
$magic = [Text.Encoding]::ASCII.GetString($image, 0, 8)
$kernelGzipBytes = (Get-Item -LiteralPath $kernelOut).Length
$headerDtbBytes = [BitConverter]::ToUInt32($image, 40)
$headerKernelBytes = [BitConverter]::ToUInt32($image, 8)
$kernelPaddedBytes = [math]::Ceiling($headerKernelBytes / 2048.0) * 2048
$ramdiskPaddedBytes = [math]::Ceiling(([BitConverter]::ToUInt32($image, 16)) / 2048.0) * 2048
$secondPaddedBytes = [math]::Ceiling(([BitConverter]::ToUInt32($image, 24)) / 2048.0) * 2048
$qcdtOffset = 2048 + $kernelPaddedBytes + $ramdiskPaddedBytes + $secondPaddedBytes
$qcdtMagic = [Text.Encoding]::ASCII.GetString($image, $qcdtOffset, 4)
$fdtOffset = -1
for ($i = 2048; $i -le $image.Length - 4; $i++) {
    if ($image[$i] -eq 0xD0 -and $image[$i + 1] -eq 0x0D -and
        $image[$i + 2] -eq 0xFE -and $image[$i + 3] -eq 0xED) {
        $fdtOffset = $i
        break
    }
}
$verification = [ordered]@{
    Magic = $magic
    ImageBytes = $image.Length
    PartitionBytes = $partitionBytes
    HeadroomBytes = $partitionBytes - $image.Length
    KernelBytes = [BitConverter]::ToUInt32($image, 8)
    KernelGzipBytes = $kernelGzipBytes
    KernelAddr = ('0x{0:X8}' -f [BitConverter]::ToUInt32($image, 12))
    RamdiskBytes = [BitConverter]::ToUInt32($image, 16)
    RamdiskAddr = ('0x{0:X8}' -f [BitConverter]::ToUInt32($image, 20))
    TagsAddr = ('0x{0:X8}' -f [BitConverter]::ToUInt32($image, 32))
    PageBytes = [BitConverter]::ToUInt32($image, 36)
    DtbMode = 'qcdt-v2'
    DtbBytes = (Get-Item -LiteralPath $dtbOut).Length
    HeaderDtbBytes = $headerDtbBytes
    QcdtOffset = $qcdtOffset
    QcdtMagic = $qcdtMagic
    EmbeddedFdtOffset = $fdtOffset
    Under16MiB = ($image.Length -lt $partitionBytes)
}
if ($magic -ne 'ANDROID!' -or -not $verification.Under16MiB -or
    $headerDtbBytes -le 0 -or $qcdtMagic -ne 'QCDT' -or
    $fdtOffset -ne ($qcdtOffset + 2048)) {
    throw 'Packaged image failed header, QCDT, embedded-FDT, or size validation.'
}
$verification | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDir 'boot-image-verification.json') -Encoding UTF8

$hashRows = Get-ChildItem -LiteralPath $OutputDir -File |
    Where-Object Name -NE 'SHA256SUMS.csv' |
    Sort-Object Name |
    ForEach-Object {
        [pscustomobject]@{
            File = $_.Name
            Bytes = $_.Length
            SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }
$hashRows | Export-Csv -LiteralPath (Join-Path $OutputDir 'SHA256SUMS.csv') -NoTypeInformation -Encoding UTF8
$verification
