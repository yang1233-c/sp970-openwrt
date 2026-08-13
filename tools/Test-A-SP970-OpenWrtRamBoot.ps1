[CmdletBinding()]
param(
    [string]$ImagePath,
    [string]$FastbootPath = $env:Q410_FASTBOOT,
    [string]$Ssid = 'SP970-CAR',
    [string]$ProbeAddress = '169.254.41.129',
    [int]$TimeoutSec = 120,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
if (-not $FastbootPath) {
    $fastbootCommand = Get-Command fastboot.exe -ErrorAction SilentlyContinue
    if (-not $fastbootCommand) { throw 'Pass -FastbootPath or set Q410_FASTBOOT.' }
    $FastbootPath = $fastbootCommand.Source
}
if (-not $ImagePath) { throw 'Pass -ImagePath with the RAM-only boot image.' }
if (-not $LogPath) {
    $LogPath = Join-Path $workspaceRoot ("reports\A-SP970-openwrt-ramboot-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

function Write-Log([string]$Message) {
    $elapsed = if ($script:Timer) { [math]::Round($script:Timer.Elapsed.TotalMilliseconds) } else { 0 }
    $line = '{0} [{1,8} ms] {2}' -f (Get-Date -Format o), $elapsed, $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Invoke-Fastboot([string[]]$Arguments) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $FastbootPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    [pscustomobject]@{
        ExitCode = $exitCode
        Text = (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
    }
}

function Get-QcomMode {
    $ids = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PNPDeviceID -match 'VID_05C6&PID_(9008|9024|F00E)' -or
            $_.PNPDeviceID -match 'VID_18D1&PID_D00D'
        } | Select-Object -ExpandProperty PNPDeviceID -Unique)
    if ($ids.Count -eq 0) {
        $raw = (& pnputil.exe /enum-devices /connected 2>&1) -join "`n"
        $ids = @([regex]::Matches($raw, '(?im)USB\\VID_(?:05C6|18D1)&PID_[0-9A-F]{4}\\[^\r\n]+') |
            ForEach-Object { $_.Value.Trim() } | Sort-Object -Unique)
    }
    if ($ids -match 'VID_05C6&PID_9008') { return 'EDL 05c6:9008' }
    if ($ids -match 'VID_18D1&PID_D00D') { return 'FASTBOOT 18d1:d00d' }
    if ($ids -match 'VID_05C6&PID_9024') { return 'STOCK 05c6:9024' }
    if ($ids -match 'VID_05C6&PID_F00E') { return 'USB 05c6:f00e' }
    return 'DISCONNECTED/OTHER'
}

New-Item -ItemType Directory -Force -Path (Split-Path $LogPath -Parent) | Out-Null
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
Write-Log 'ACTION=A_SP970_OPENWRT_RAM_BOOT_ONLY'
Write-Log 'GUARD=fastboot getvar + fastboot boot; zero erase/flash/format/oem commands; COM4 excluded'

foreach ($required in @($FastbootPath, $ImagePath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing file: $required" }
}
$image = Get-Item -LiteralPath $ImagePath
$bytes = [IO.File]::ReadAllBytes($ImagePath)
$magic = [Text.Encoding]::ASCII.GetString($bytes, 0, 8)
$hash = (Get-FileHash -LiteralPath $ImagePath -Algorithm SHA256).Hash
if ($magic -ne 'ANDROID!' -or $image.Length -ge 16MB) { throw 'Boot-image magic or 16 MiB size guard failed.' }

$sumPath = Join-Path $image.DirectoryName 'SHA256SUMS.csv'
if (Test-Path -LiteralPath $sumPath) {
    $expected = Import-Csv -LiteralPath $sumPath | Where-Object File -EQ $image.Name | Select-Object -First 1
    if (-not $expected -or $expected.SHA256 -ne $hash) { throw 'Artifact checksum manifest mismatch.' }
}
Write-Log "IMAGE=$($image.FullName)"
Write-Log "IMAGE_BYTES=$($image.Length) HEADROOM_BYTES=$((16MB)-$image.Length) SHA256=$hash"

$devices = Invoke-Fastboot -Arguments @('devices')
$deviceLines = @($devices.Text -split '[\r\n]+' | Where-Object { $_ -match '\sfastboot\s*$' })
Write-Log "FASTBOOT_DEVICES=$($devices.Text -replace '[\r\n]+','; ')"
if ($devices.ExitCode -ne 0 -or $deviceLines.Count -ne 1) {
    Write-Log "RESULT=PRECHECK_FASTBOOT_COUNT_$($deviceLines.Count)"
    exit 4
}

foreach ($name in @('product', 'version', 'max-download-size', 'partition-size:boot')) {
    $value = Invoke-Fastboot -Arguments @('getvar', $name)
    Write-Log "GETVAR_$($name.ToUpperInvariant()) exit=$($value.ExitCode) output=$($value.Text -replace '[\r\n]+','; ')"
}
$product = Invoke-Fastboot -Arguments @('getvar', 'product')
if ($product.Text -notmatch 'MSM8916') {
    Write-Log 'RESULT=PRODUCT_GUARD_STOP'
    exit 5
}

$script:Timer = [Diagnostics.Stopwatch]::StartNew()
Write-Log "COMMAND=fastboot boot `"$ImagePath`""
$boot = Invoke-Fastboot -Arguments @('boot', $ImagePath)
Write-Log "BOOT_EXIT=$($boot.ExitCode) OUTPUT=$($boot.Text -replace '[\r\n]+','; ')"
$acceptedBeforeDisconnect = $boot.Text -match "Sending 'boot\.img'.*OKAY" -and
    $boot.Text -match 'Status read failed|Too many links'
if ($boot.ExitCode -ne 0 -and -not $acceptedBeforeDisconnect) {
    Write-Log 'RESULT=BOOT_COMMAND_FAILED_BEFORE_TRANSITION'
    exit 6
}

$lastMode = $null
$lastWifiScan = [TimeSpan]::FromSeconds(-10)
$beaconSeen = $false
$pingSeen = $false
while ($script:Timer.Elapsed.TotalSeconds -lt $TimeoutSec) {
    $mode = Get-QcomMode
    if ($mode -ne $lastMode) {
        Write-Log "USB_MODE=$mode"
        $lastMode = $mode
    }
    if (($script:Timer.Elapsed - $lastWifiScan).TotalSeconds -ge 2) {
        $lastWifiScan = $script:Timer.Elapsed
        $scan = (& netsh.exe wlan show networks mode=bssid 2>&1) -join "`n"
        if ($scan -match [regex]::Escape($Ssid)) {
            Write-Log "WIFI_BEACON=$Ssid"
            $beaconSeen = $true
        }
    }
    if ($mode -eq 'USB 05c6:f00e') {
        & ping.exe -n 1 -w 150 $ProbeAddress *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "PING_READY=$ProbeAddress"
            $pingSeen = $true
        }
    }
    if ($beaconSeen -or $pingSeen) { break }
    Start-Sleep -Milliseconds 400
}

if ($beaconSeen -or $pingSeen) {
    Write-Log "RESULT=RAM_BOOT_NETWORK_OBSERVED beacon=$beaconSeen ping=$pingSeen"
    exit 0
}
Write-Log "RESULT=RAM_BOOT_TIMEOUT final_usb=$lastMode"
exit 7
