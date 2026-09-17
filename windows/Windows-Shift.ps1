#requires -Version 5.1
param([ValidateSet('Check', 'Apply', 'Restore')][string]$Mode = 'Check')
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'shared/Settings.ps1')

function DecodeMap([byte[]]$Bytes) {
    $map = [ordered]@{}
    if ($null -eq $Bytes) { return $map }
    if ($Bytes.Length -lt 16 -or [BitConverter]::ToUInt64($Bytes, 0) -ne 0) { throw '기존 Windows 키 변환 헤더가 올바르지 않습니다.' }
    $count = [BitConverter]::ToUInt32($Bytes, 8)
    if ($count -lt 1 -or $Bytes.Length -ne (12L + 4L * $count) -or
        [BitConverter]::ToUInt32($Bytes, $Bytes.Length - 4) -ne 0) { throw '기존 Windows 키 변환 길이 또는 종료값이 올바르지 않습니다.' }
    for ($i = 0; $i -lt $count - 1; $i++) {
        $offset = 12 + 4 * $i
        $src = [string][BitConverter]::ToUInt16($Bytes, $offset + 2)
        $dst = [int][BitConverter]::ToUInt16($Bytes, $offset)
        if ($src -eq '0' -or $map.Contains($src)) { throw '기존 Windows 키 변환에 잘못되거나 중복된 원본 키가 있습니다.' }
        $map[$src] = $dst
    }
    return $map
}
function EncodeMap($Map) {
    $bytes = New-Object byte[] (12 + 4 * ($Map.Count + 1))
    [BitConverter]::GetBytes([uint32]($Map.Count + 1)).CopyTo($bytes, 8)
    $offset = 12
    foreach ($src in $Map.Keys) {
        $source = [uint16]$src; $target = [uint16]$Map[$src]
        if ($source -eq 0) { throw '원본 스캔 코드는 0일 수 없습니다.' }
        [BitConverter]::GetBytes($target).CopyTo($bytes, $offset)
        [BitConverter]::GetBytes($source).CopyTo($bytes, $offset + 2)
        $offset += 4
    }
    return ,$bytes
}
function MapToken([byte[]]$Bytes) {
    if ($null -eq $Bytes) { return 'absent' }
    return [Convert]::ToBase64String($Bytes)
}
if ($MyInvocation.InvocationName -eq '.') { return }
if ($Mode -ne 'Check') {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1}' -f $PSCommandPath, $Mode
        $process = Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        exit $process.ExitCode
    }
}
$profile = Read-PortableJson -Path (Join-Path $PSScriptRoot 'profile.json') -Kind Object
$desired = [ordered]@{}
foreach ($entry in $profile.scanMappings) {
    $source = [string]$entry.source
    if ($source -notin @('109', '110') -or $desired.Contains($source) -or
        ($entry.target -isnot [int] -and $entry.target -isnot [long]) -or $entry.target -lt 0 -or $entry.target -gt [uint16]::MaxValue) { throw 'F22/F23 프로필 형식이 올바르지 않습니다.' }
    $desired[$source] = $entry.target
}
if ($desired.Count -ne 2) { throw 'F22와 F23 프로필이 모두 필요합니다.' }
$key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
$bytes = (Get-Item -LiteralPath $key).GetValue('Scancode Map')
$map = DecodeMap $bytes
if ($Mode -eq 'Check') {
    Write-Host ('F22 변환: ' + $map['109'] + ' / F23 변환: ' + $map['110'])
    Write-Host ('목표: ' + $desired['109'] + ', ' + $desired['110'] + '. 조회만 했습니다.')
    return
}
$folder = Join-Path $env:ProgramData 'NumberPad-Portable'
$backupFile = Join-Path $folder 'shift-before.json'
if ($Mode -eq 'Apply') {
    if ($map['109'] -eq $desired['109'] -and $map['110'] -eq $desired['110']) { Write-Host '이미 같은 Windows 변환입니다. 변경하지 않았습니다.'; return }
    if ([IO.File]::Exists($backupFile)) { throw 'Windows 변환 백업이 이미 있습니다. 먼저 복구하거나 기존 백업을 확인하세요.' }
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $before = @{}
    foreach ($src in $desired.Keys) { $before[$src] = @{ existed = $map.Contains($src); value = $map[$src]; applied = $desired[$src] } }
    Save-PortableJson -Path $backupFile -Value $before
    foreach ($src in $desired.Keys) { $map[$src] = $desired[$src] }
} else {
    $before = Read-PortableJson -Path $backupFile -Kind Object
    foreach ($src in $desired.Keys) {
        $property = $before.PSObject.Properties[$src]
        if ($null -eq $property -or $property.Value.existed -isnot [bool]) { throw 'Windows 변환 백업 형식이 올바르지 않습니다.' }
        $entry = $property.Value
        $applied = if ($entry.PSObject.Properties['applied']) { $entry.applied } else { $desired[$src] }
        if ($map[$src] -ne $applied) { throw 'Windows 키 변환이 이후 바뀌었습니다. 자동으로 덮어쓰지 않습니다.' }
        if ($entry.existed) { $map[$src] = [int][uint16]$entry.value } else { $map.Remove($src) }
    }
}
if ((MapToken ((Get-Item -LiteralPath $key).GetValue('Scancode Map'))) -cne (MapToken $bytes)) { throw 'Windows 키 변환이 작업 중 변경되어 저장하지 않습니다.' }
if ($map.Count -gt 0) {
    New-ItemProperty -LiteralPath $key -Name 'Scancode Map' -PropertyType Binary -Value (EncodeMap $map) -Force | Out-Null
} elseif ($null -ne $bytes) { Remove-ItemProperty -LiteralPath $key -Name 'Scancode Map' }
$actual = DecodeMap ((Get-Item -LiteralPath $key).GetValue('Scancode Map'))
if ($actual.Count -ne $map.Count) { throw 'Windows 키 변환 저장 개수 확인 실패' }
foreach ($src in $map.Keys) { if ($actual[$src] -ne $map[$src]) { throw 'Windows 키 변환 저장 확인 실패' } }
if ($Mode -eq 'Restore') { Move-Item -LiteralPath $backupFile -Destination ($backupFile + '.restored-' + [guid]::NewGuid().ToString('N')) }
Write-Host 'Windows 키 변환을 저장했습니다. PC를 재부팅하면 반영됩니다. 자동으로 재부팅하지 않습니다.'
