[CmdletBinding()]
param(
    [ValidateSet('Validate','Write','WriteBoot','Rollback')]
    [string]$Action = 'Validate',
    [string]$ManagementHost = '169.254.41.129'
)

$ErrorActionPreference = 'Stop'
$Workspace = Split-Path -Parent $PSScriptRoot
$ArtifactDir = Join-Path $Workspace 'artifacts\A-SP970-persistent-wwan-20260811'
$Ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
$Scp = (Get-Command scp.exe -ErrorAction Stop).Source
$SshOptions = @(
    '-o','BatchMode=yes','-o','ConnectTimeout=8',
    '-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=NUL',
    '-o','LogLevel=ERROR'
)

$Expected = @{
    'rootfs-payload-256MiB.ext4' = @{ Bytes=268435456L; Sha='CF2B02D00337B95DC439B48FA4EC4042B256602BE17DFEF023BAB33765BCAE4F' }
    'rootfs-payload-256MiB.ext4.gz' = @{ Bytes=37622168L; Sha='D75B208C10206FA2066B33A939318D39E24BD0D1ACD364DC574D547A69BC7403' }
    'boot-payload-64MiB.bin' = @{ Bytes=67108864L; Sha='A6B12ADA86E6193C9AB116CFFBB9F230855F5C044EF249E08CD45CB1A4F1A00E' }
    'boot-payload-64MiB.bin.gz' = @{ Bytes=8073188L; Sha='2507775E45574A28B5B3F9B5DBCDAA759D7DFF49E7BDB343091FE3E5DD9650F9' }
    'preimage-rootfs-p14-first-256MiB.bin' = @{ Bytes=268435456L; Sha='A6D72AC7690F53BE6AE46BA88506BD97302A093F7108472BD9EFC3CEFDA06484' }
    'preimage-rootfs-p14-first-256MiB.bin.gz' = @{ Bytes=261734L; Sha='1151BDCE0E6E7033C3E33F046B1AA7E2E9C46B6AD2B27EAD776946E8BC5FF139' }
    'preimage-boot-p12-64MiB.bin' = @{ Bytes=67108864L; Sha='AF73D68370B17452DCF10CBAE30F69A33069B224DA103635D4D2796DBE2A3BC9' }
    'preimage-boot-p12-64MiB.bin.gz' = @{ Bytes=12290362L; Sha='907CBA82980395F3BF09AF69E1F72F907EAFF6AD336E9D08A3995E4D73975016' }
}

function Assert-LocalArtifacts {
    foreach ($Name in $Expected.Keys | Sort-Object) {
        $Path = Join-Path $ArtifactDir $Name
        $File = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($File.Length -ne $Expected[$Name].Bytes) {
            throw "SIZE_MISMATCH $Name expected=$($Expected[$Name].Bytes) actual=$($File.Length)"
        }
        $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        if ($Hash -ne $Expected[$Name].Sha) {
            throw "SHA256_MISMATCH $Name expected=$($Expected[$Name].Sha) actual=$Hash"
        }
        Write-Output "LOCAL_PASS $Name bytes=$($File.Length) sha256=$Hash"
    }
}

function Invoke-Ssh([string]$Command) {
    $Output = & $Ssh @SshOptions "root@$ManagementHost" $Command 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SSH_FAILED exit=$LASTEXITCODE output=$($Output -join ' ')"
    }
    $Output | ForEach-Object { Write-Output $_ }
}

function Send-Archive([string]$LocalName, [string]$RemotePath) {
    $LocalPath = Join-Path $ArtifactDir $LocalName
    & $Scp '-O' @SshOptions $LocalPath ("root@{0}:{1}" -f $ManagementHost,$RemotePath)
    if ($LASTEXITCODE -ne 0) {
        throw "SCP_FAILED exit=$LASTEXITCODE file=$LocalName"
    }
    Write-Output "UPLOAD_PASS $LocalName remote=$RemotePath"
}

function Write-And-Verify(
    [string]$LocalGzip,
    [string]$GzipSha,
    [string]$RawSha,
    [string]$Target,
    [int]$ReadCountMiB
) {
    $Remote = '/tmp/' + $LocalGzip
    Send-Archive $LocalGzip $Remote
    $Command = @'
set -e
archive=$(sha256sum __REMOTE__ | cut -d ' ' -f 1)
test "$archive" = "__GZSHA__"
raw=$(gzip -dc __REMOTE__ | sha256sum | cut -d ' ' -f 1)
test "$raw" = "__RAWSHA__"
gzip -dc __REMOTE__ | dd of=__TARGET__ bs=1048576 2>/tmp/q410-write-dd.log
sync
readback=$(dd if=__TARGET__ bs=1048576 count=__COUNT__ 2>/dev/null | sha256sum | cut -d ' ' -f 1)
echo WRITE_READBACK target=__TARGET__ sha256=$readback
test "$readback" = "__RAWSHA__"
rm -f __REMOTE__
'@
    $Command = $Command.Replace('__REMOTE__',$Remote).
        Replace('__GZSHA__',$GzipSha.ToLowerInvariant()).
        Replace('__RAWSHA__',$RawSha.ToLowerInvariant()).
        Replace('__TARGET__',$Target).
        Replace('__COUNT__',[string]$ReadCountMiB)
    Invoke-Ssh $Command
}

Assert-LocalArtifacts
if ($Action -eq 'Validate') {
    Write-Output 'VALIDATE_PASS persistent payloads and rollback preimages'
    exit 0
}

Invoke-Ssh "set -e; test `$(cat /sys/class/block/mmcblk0p12/size) -eq 131072; test `$(cat /sys/class/block/mmcblk0p14/size) -ge 524288; echo DEVICE_PREFLIGHT_PASS"

if ($Action -eq 'WriteBoot') {
    Write-And-Verify 'boot-payload-64MiB.bin.gz' $Expected['boot-payload-64MiB.bin.gz'].Sha $Expected['boot-payload-64MiB.bin'].Sha '/dev/mmcblk0p12' 64
    Invoke-Ssh "sha256sum /dev/mmcblk0p7 /dev/mmcblk0p8 /dev/mmcblk0p9 /dev/mmcblk0p10; echo PERSISTENT_BOOT_WRITE_PASS"
    exit 0
}

Invoke-Ssh "set -e; if grep -q 'root=/dev/mmcblk0p14' /proc/cmdline; then echo P14_IS_ACTIVE_ROOT; exit 2; fi; test -z `"`$(mount | grep 'mmcblk0p14' || true)`"; echo ROOTFS_WRITE_PREFLIGHT_PASS"

if ($Action -eq 'Write') {
    # Rootfs first: a failed transfer leaves the current boot partition intact.
    Write-And-Verify 'rootfs-payload-256MiB.ext4.gz' $Expected['rootfs-payload-256MiB.ext4.gz'].Sha $Expected['rootfs-payload-256MiB.ext4'].Sha '/dev/mmcblk0p14' 256
    Write-And-Verify 'boot-payload-64MiB.bin.gz' $Expected['boot-payload-64MiB.bin.gz'].Sha $Expected['boot-payload-64MiB.bin'].Sha '/dev/mmcblk0p12' 64
    Invoke-Ssh "sha256sum /dev/mmcblk0p7 /dev/mmcblk0p8 /dev/mmcblk0p9 /dev/mmcblk0p10; echo PERSISTENT_WRITE_PASS"
    exit 0
}

# Roll back the same exact ranges, again committing boot last.
Write-And-Verify 'preimage-rootfs-p14-first-256MiB.bin.gz' $Expected['preimage-rootfs-p14-first-256MiB.bin.gz'].Sha $Expected['preimage-rootfs-p14-first-256MiB.bin'].Sha '/dev/mmcblk0p14' 256
Write-And-Verify 'preimage-boot-p12-64MiB.bin.gz' $Expected['preimage-boot-p12-64MiB.bin.gz'].Sha $Expected['preimage-boot-p12-64MiB.bin'].Sha '/dev/mmcblk0p12' 64
Invoke-Ssh "sha256sum /dev/mmcblk0p7 /dev/mmcblk0p8 /dev/mmcblk0p9 /dev/mmcblk0p10; echo ROLLBACK_PASS"
