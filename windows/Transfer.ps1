#requires -Version 5.1
param([ValidateSet('Check', 'Apply', 'Restore')][string]$Mode = 'Check')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'shared/Settings.ps1')

function Assert-MacroName([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name) -or [IO.Path]::GetFileName($Name) -cne $Name -or
        $Name -match '[\\/:]' -or $Name -notlike '*.mhm') { throw '허용되지 않는 매크로 파일 이름입니다.' }
}
function Assert-NumberPadProfile($Profile) {
    if ($Profile.version -ne 1 -or $Profile.model -ne 7026 -or -not $Profile.events.Count) { throw '지원하지 않는 Number Pad 프로필입니다.' }
    $ids = [Collections.Generic.HashSet[string]]::new()
    foreach ($event in $Profile.events) {
        if ($event.id -notmatch '^\d+$' -or -not $ids.Add([string]$event.id) -or -not $event.values.Count) { throw '키 설정 ID가 잘못되었거나 중복되었습니다.' }
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($value in $event.values) {
            if ($value.name -notin @('Command', 'Keystroke', 'KeystrokeText', 'Macro') -or -not $names.Add($value.name)) { throw '키 설정 속성이 잘못되었거나 중복되었습니다.' }
            if ($value.kind -eq 'String') {
                if ($value.value -isnot [string]) { throw '문자열 키 설정 형식이 올바르지 않습니다.' }
            } elseif ($value.kind -eq 'DWord') {
                if (($value.value -isnot [int] -and $value.value -isnot [long]) -or
                    $value.value -lt [int]::MinValue -or $value.value -gt [int]::MaxValue) { throw '정수 키 설정 형식이 올바르지 않습니다.' }
            } else { throw '지원하지 않는 레지스트리 값 형식입니다.' }
        }
    }
    foreach ($name in $Profile.macros) { Assert-MacroName $name }
    $null = Set-PortableJsonString -Text '{}' -Name appshotHotkey -Value $Profile.appshotHotkey
}
function Test-NumberPadRegistry([string]$Path, $Events) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $rootKey = Get-Item -LiteralPath $Path
    if ($rootKey.GetSubKeyNames().Count -ne $Events.Count -or $rootKey.GetValueNames().Count -ne 0) { return $false }
    foreach ($event in $Events) {
        $eventPath = Join-Path $Path $event.id
        if (-not (Test-Path -LiteralPath $eventPath)) { return $false }
        $key = Get-Item -LiteralPath $eventPath
        if ($key.GetValueNames().Count -ne $event.values.Count -or $key.GetSubKeyNames().Count -ne 0) { return $false }
        foreach ($value in $event.values) {
            if ($key.GetValue($value.name) -cne $value.value -or
                $key.GetValueKind($value.name).ToString() -ne $value.kind) { return $false }
        }
    }
    return $true
}
if ($MyInvocation.InvocationName -eq '.') { return }

$reg = 'HKCU\Software\Microsoft\IntelliType Pro\ModelSpecific\7026\EventMapping'
$psReg = 'HKCU:\Software\Microsoft\IntelliType Pro\ModelSpecific\7026\EventMapping'
$macroRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Microsoft Hardware\Macros'
$codexRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$stateFile = Join-Path $codexRoot '.codex-global-state.json'
$backupRoot = Join-Path $env:LOCALAPPDATA 'NumberPad-Portable\Backups'
$latestFile = Join-Path $backupRoot 'latest.txt'
$guard = { Assert-PortableAppsClosed -IncludeKeyboardCenter }

if ($Mode -ne 'Restore') {
    $profile = Read-PortableJson -Path (Join-Path $PSScriptRoot 'profile.json') -Kind Object
    Assert-NumberPadProfile $profile
    $sourceHashes = @{}
    foreach ($name in $profile.macros) {
        $sourceHashes[$name] = (Get-FileHash -LiteralPath (Join-Path (Join-Path $PSScriptRoot 'macros') $name)).Hash
    }
}
if ($Mode -eq 'Check') {
    Write-Host ('프로필 저장 날짜: ' + $profile.capturedAt)
    Write-Host ('Number Pad 키 설정: ' + $profile.events.Count + '개 / 매크로 파일: ' + $profile.macros.Count + '개')
    Write-Host ('이 PC 레지스트리와 프로필 일치: ' + (Test-NumberPadRegistry -Path $psReg -Events $profile.events))
    foreach ($id in @('59', '937', '938', '939', '941', '952')) {
        if (Test-Path -LiteralPath "$psReg\$id") {
            Get-ItemProperty -LiteralPath "$psReg\$id" | Select-Object Command, KeystrokeText, Macro | Format-List
        }
    }
    if ([IO.File]::Exists($stateFile)) { Write-Host ('이 PC 앱샷: ' + (Read-PortableJson -Path $stateFile -Kind Object).appshotHotkey) }
    else { Write-Host 'Codex 설정이 아직 없습니다. 최초 실행 후 앱샷을 적용하세요.' }
    Write-Host '조회만 했습니다. 설정은 변경하지 않았습니다.'
    return
}
& $guard
if ($Mode -eq 'Restore') {
    $backup = Resolve-PortableBackup -Root $backupRoot -Pointer $latestFile
    $manifest = Read-PortableJson -Path (Join-Path $backup 'before.json') -Kind Object
    if ($manifest.restored) { throw '이 백업은 이미 복구했습니다.' }
    # Validate every required backup before deleting the current registry tree.
    if ($manifest.registryExisted) {
        $regBackup = Join-Path $backup 'before.reg'
        if (-not [IO.File]::Exists($regBackup)) { throw '레지스트리 백업이 없습니다. 현재 설정은 변경하지 않았습니다.' }
        if ($manifest.PSObject.Properties['registryHash'] -and (Get-FileHash -LiteralPath $regBackup).Hash -ne $manifest.registryHash) { throw '레지스트리 백업이 변경되었습니다.' }
    }
    foreach ($entry in $manifest.macros) {
        Assert-MacroName $entry.name
        $savedMacro = Join-Path (Join-Path $backup 'macros') $entry.name
        if ($entry.existed -and -not [IO.File]::Exists($savedMacro)) { throw '필요한 매크로 백업이 없습니다.' }
        if ($entry.existed -and $entry.PSObject.Properties['beforeHash'] -and (Get-FileHash -LiteralPath $savedMacro).Hash -ne $entry.beforeHash) { throw '매크로 백업이 변경되었습니다.' }
        if ($manifest.status -eq 'saved' -and $entry.PSObject.Properties['appliedHash']) {
            $dest = Join-Path $macroRoot $entry.name
            if (-not [IO.File]::Exists($dest) -or (Get-FileHash -LiteralPath $dest).Hash -ne $entry.appliedHash) { throw '매크로가 이후 변경되어 자동 복구하지 않습니다.' }
        }
    }
    if ($manifest.status -eq 'saved' -and $manifest.PSObject.Properties['appliedEvents'] -and
        -not (Test-NumberPadRegistry -Path $psReg -Events $manifest.appliedEvents)) { throw '키 설정이 이후 변경되어 자동 복구하지 않습니다.' }
    $stateBefore = $null; $stateAfter = $null
    if ($manifest.codexChanged) {
        if (-not [IO.File]::Exists($stateFile)) { throw 'Codex 설정 파일이 없어 자동 복구하지 않습니다.' }
        $stateBefore = [IO.File]::ReadAllText($stateFile)
        $state = ConvertFrom-PortableJson -Text $stateBefore -Kind Object
        $current = $state.PSObject.Properties['appshotHotkey']
        $applied = if ($manifest.PSObject.Properties['appliedHotkey']) { $manifest.appliedHotkey }
                   else { (Read-PortableJson -Path (Join-Path $PSScriptRoot 'profile.json') -Kind Object).appshotHotkey }
        $alreadyOriginal = (($null -ne $current) -eq [bool]$manifest.hotkeyExisted) -and
            (-not $manifest.hotkeyExisted -or [object]::Equals($current.Value, $manifest.hotkey))
        if (-not $alreadyOriginal -and ($null -eq $current -or -not [object]::Equals($current.Value, $applied))) {
            throw 'Codex 단축키가 이후 변경되어 자동 복구하지 않습니다.'
        }
        # A failed apply may never have reached the Codex write. That is still recoverable.
        $stateAfter = Set-PortableJsonString -Text $stateBefore -Name appshotHotkey -Value $manifest.hotkey -Exists $manifest.hotkeyExisted
    }
    & $guard
    if ($null -ne $stateAfter) { Assert-PortableFileState -Path $stateFile -Exists $true -Text $stateBefore }
    $manifest.status = 'restoring'
    Save-PortableJson -Path (Join-Path $backup 'before.json') -Value $manifest
    if (Test-Path -LiteralPath $psReg) { & reg.exe delete $reg /f | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Number Pad 설정 삭제 실패' } }
    if ($manifest.registryExisted) { & reg.exe import $regBackup | Out-Null; if ($LASTEXITCODE -ne 0) { throw '레지스트리 복구 실패' } }
    New-Item -ItemType Directory -Path $macroRoot -Force | Out-Null
    foreach ($entry in $manifest.macros) {
        $dest = Join-Path $macroRoot $entry.name
        if ($entry.existed) { Copy-Item -LiteralPath (Join-Path (Join-Path $backup 'macros') $entry.name) -Destination $dest -Force }
        elseif (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest }
    }
    if ($null -ne $stateAfter) { Set-PortableTextFile -Path $stateFile -Text $stateAfter -BeforeExists $true -BeforeText $stateBefore -Guard $guard }
    $manifest.restored = $true
    Save-PortableJson -Path (Join-Path $backup 'before.json') -Value $manifest
    Write-Host '이 PC의 적용 전 Number Pad·매크로·앱샷 설정으로 복구했습니다. Windows Shift 변환은 별도로 복구하세요.'
    return
}

$mkc = Join-Path $env:ProgramFiles 'Microsoft Mouse and Keyboard Center\MouseKeyboardCenter.exe'
if (-not [IO.File]::Exists($mkc)) { throw 'Microsoft 마우스·키보드 센터를 먼저 설치하고 Number Pad를 연결하세요.' }
$stateBefore = $null; $stateAfter = $null; $hadHotkey = $false; $oldHotkey = $null
if ([IO.File]::Exists($stateFile)) {
    $stateBefore = [IO.File]::ReadAllText($stateFile)
    $state = ConvertFrom-PortableJson -Text $stateBefore -Kind Object
    $hadHotkey = $null -ne $state.PSObject.Properties['appshotHotkey']
    $oldHotkey = $state.appshotHotkey
    $stateAfter = Set-PortableJsonString -Text $stateBefore -Name appshotHotkey -Value $profile.appshotHotkey
}
$sameMacros = $true
foreach ($name in $profile.macros) {
    $dest = Join-Path $macroRoot $name
    if (-not [IO.File]::Exists($dest) -or (Get-FileHash -LiteralPath $dest).Hash -ne $sourceHashes[$name]) { $sameMacros = $false }
}
if ($sameMacros -and $stateBefore -ceq $stateAfter -and (Test-NumberPadRegistry -Path $psReg -Events $profile.events)) {
    Write-Host '이미 같은 Number Pad 설정입니다. 설정과 기존 복구 백업을 변경하지 않았습니다.'
    if ($null -eq $stateAfter) { Write-Host 'Codex 최초 실행 후 앱샷 설정을 다시 적용하세요.' }
    return
}
$backup = Join-Path $backupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $backup 'macros') -Force | Out-Null
$manifest = [ordered]@{
    version = 2; registryExisted = (Test-Path -LiteralPath $psReg); registryHash = $null
    hotkeyExisted = $hadHotkey; hotkey = $oldHotkey; appliedHotkey = $profile.appshotHotkey
    codexChanged = ($null -ne $stateAfter -and $stateBefore -cne $stateAfter)
    appliedEvents = $profile.events; macros = @(); restored = $false; status = 'backed-up'
}
if ($manifest.registryExisted) {
    & reg.exe export $reg (Join-Path $backup 'before.reg') /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '기존 설정 백업 실패' }
    $manifest.registryHash = (Get-FileHash -LiteralPath (Join-Path $backup 'before.reg')).Hash
}
foreach ($name in $profile.macros) {
    $dest = Join-Path $macroRoot $name
    $exists = [IO.File]::Exists($dest)
    $beforeHash = $null
    if ($exists) {
        $savedMacro = Join-Path (Join-Path $backup 'macros') $name
        Copy-Item -LiteralPath $dest -Destination $savedMacro
        $beforeHash = (Get-FileHash -LiteralPath $savedMacro).Hash
    }
    $manifest.macros += @{ name = $name; existed = $exists; beforeHash = $beforeHash; appliedHash = $sourceHashes[$name] }
}
Save-PortableJson -Path (Join-Path $backup 'before.json') -Value $manifest
$pointerExists = [IO.File]::Exists($latestFile)
$pointerBefore = if ($pointerExists) { [IO.File]::ReadAllText($latestFile) } else { $null }
Set-PortableTextFile -Path $latestFile -Text $backup -BeforeExists $pointerExists -BeforeText $pointerBefore
try {
    & $guard
    if (Test-Path -LiteralPath $psReg) { & reg.exe delete $reg /f | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Number Pad 기존 설정 교체 실패' } }
    # profile.json is the single application source; numberpad.reg remains a reference export.
    New-Item -Path $psReg -Force | Out-Null
    foreach ($event in $profile.events) {
        $path = Join-Path $psReg $event.id
        New-Item -Path $path -Force | Out-Null
        foreach ($value in $event.values) { New-ItemProperty -LiteralPath $path -Name $value.name -PropertyType $value.kind -Value $value.value -Force | Out-Null }
    }
    New-Item -ItemType Directory -Path $macroRoot -Force | Out-Null
    foreach ($name in $profile.macros) {
        $dest = Join-Path $macroRoot $name
        Copy-Item -LiteralPath (Join-Path (Join-Path $PSScriptRoot 'macros') $name) -Destination $dest -Force
        if ((Get-FileHash -LiteralPath $dest).Hash -ne $sourceHashes[$name]) { throw '매크로 복사 검증 실패' }
    }
    if (-not (Test-NumberPadRegistry -Path $psReg -Events $profile.events)) { throw '저장한 레지스트리 값 또는 형식이 프로필과 다릅니다.' }
    if ($manifest.codexChanged) { Set-PortableTextFile -Path $stateFile -Text $stateAfter -BeforeExists $true -BeforeText $stateBefore -Guard $guard }
    $manifest.status = 'saved'
    Save-PortableJson -Path (Join-Path $backup 'before.json') -Value $manifest
    Write-Host '키 설정과 매크로를 저장했습니다. 재부팅 후 키 배치와 실제 입력을 확인하세요.'
    if ($null -eq $stateAfter) { Write-Host 'Codex 최초 실행·로그인 후 완전히 종료하고 앱샷 설정을 다시 적용하세요.' }
    Write-Host ('이 PC 복구 백업: ' + $backup)
} catch {
    $manifest.status = 'failed'
    Save-PortableJson -Path (Join-Path $backup 'before.json') -Value $manifest
    Write-Host '일부 설정만 적용됐을 수 있습니다. Restore.cmd로 이 PC의 백업을 복구하세요.'
    throw
}
