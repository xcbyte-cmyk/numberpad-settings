#requires -Version 5.1
param([ValidateSet('Check', 'Apply', 'Restore')][string]$Mode = 'Check')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'shared/Settings.ps1')

$root = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$keysFile = Join-Path $root 'keybindings.json'
$stateFile = Join-Path $root '.codex-global-state.json'
$backupRoot = Join-Path $env:LOCALAPPDATA 'NumberPad-Codex-Shortcuts'
$latestFile = Join-Path $backupRoot 'latest.txt'
$guard = { Assert-PortableAppsClosed }

if ($Mode -ne 'Restore') {
    $source = Read-PortableJson -Path (Join-Path $PSScriptRoot 'keybindings.json') -Kind Array
    $globals = Read-PortableJson -Path (Join-Path $PSScriptRoot 'global-hotkeys.json') -Kind Object
    $null = Merge-PortableKeybindings -Existing @() -Source $source
    foreach ($p in $globals.PSObject.Properties) {
        $null = Set-PortableJsonString -Text '{}' -Name $p.Name -Value $p.Value
    }
}
if ($Mode -eq 'Check') {
    $source | Select-Object command, key | Format-Table -AutoSize
    Write-Host '내보낸 사용자 지정 단축키입니다. null은 해당 명령의 단축키 해제를 뜻합니다.'
    if ([IO.File]::Exists($stateFile)) {
        $state = Read-PortableJson -Path $stateFile -Kind Object
        Write-Host ('현재 앱샷: ' + $state.appshotHotkey)
        Write-Host ('현재 창 호출: ' + $state.hotkeyWindowHotkey)
    }
    return
}
& $guard
if (-not [IO.File]::Exists($stateFile)) { throw '이 PC에서 Codex를 먼저 실행하고 로그인한 뒤 종료하세요.' }
$stateBefore = [IO.File]::ReadAllText($stateFile)
$state = ConvertFrom-PortableJson -Text $stateBefore -Kind Object
$keysExisted = [IO.File]::Exists($keysFile)
$keysBefore = if ($keysExisted) { [IO.File]::ReadAllText($keysFile) } else { $null }
$stateAfter = $stateBefore

if ($Mode -eq 'Restore') {
    $backup = Resolve-PortableBackup -Root $backupRoot -Pointer $latestFile
    $manifest = Read-PortableJson -Path (Join-Path $backup 'before.json') -Kind Object
    if ($manifest.restored) { throw '이미 복구한 백업입니다.' }
    if (-not $keysExisted -or (Get-FileHash -LiteralPath $keysFile).Hash -ne $manifest.appliedHash) {
        throw '단축키가 이후 변경됐습니다. 덮어쓰지 않습니다.'
    }
    # New backups carry applied values, so later profile updates do not invalidate recovery.
    $applied = if ($manifest.PSObject.Properties['appliedGlobals']) { $manifest.appliedGlobals }
               else { Read-PortableJson -Path (Join-Path $PSScriptRoot 'global-hotkeys.json') -Kind Object }
    foreach ($p in $applied.PSObject.Properties) {
        $current = $state.PSObject.Properties[$p.Name]
        if ($null -eq $current -or -not [object]::Equals($current.Value, $p.Value)) {
            throw '전역 단축키가 이후 변경됐습니다. 덮어쓰지 않습니다.'
        }
        $old = $manifest.globals.PSObject.Properties[$p.Name]
        if ($null -eq $old) { throw '전역 단축키 복구 정보가 없습니다.' }
        $stateAfter = Set-PortableJsonString -Text $stateAfter -Name $p.Name -Value $old.Value.value -Exists $old.Value.existed
    }
    $keysAfterExists = [bool]$manifest.keysExisted
    $keysAfter = if ($keysAfterExists) { [IO.File]::ReadAllText((Join-Path $backup 'keybindings.json')) } else { $null }
    if ($keysAfterExists) { $null = ConvertFrom-PortableJson -Text $keysAfter -Kind Array }
    $changes = @(
        @{ Path = $keysFile; BeforeExists = $keysExisted; BeforeText = $keysBefore; AfterExists = $keysAfterExists; AfterText = $keysAfter }
        @{ Path = $stateFile; BeforeExists = $true; BeforeText = $stateBefore; AfterExists = $true; AfterText = $stateAfter }
    )
    Invoke-PortableFileTransaction -Changes $changes -Guard $guard -AfterCommit {
        $manifest.restored = $true
        Save-PortableJson -Path (Join-Path $backup 'before.json') -Value $manifest
    }
    Write-Host '이 PC의 이전 Codex 단축키로 복구했습니다. Codex를 다시 실행하세요.'
    return
}

$existing = [object[]]@()
if ($keysExisted) { $existing = ConvertFrom-PortableJson -Text $keysBefore -Kind Array }
$merged = Merge-PortableKeybindings -Existing @($existing) -Source $source
$oldGlobals = @{}
foreach ($p in $globals.PSObject.Properties) {
    $old = $state.PSObject.Properties[$p.Name]
    $oldGlobals[$p.Name] = @{ existed = ($null -ne $old); value = $(if ($null -ne $old) { $old.Value } else { $null }) }
    $stateAfter = Set-PortableJsonString -Text $stateAfter -Name $p.Name -Value $p.Value
}
$keysAfter = ConvertTo-Json -InputObject $merged -Depth 100
$sameKeys = $keysExisted -and ((ConvertTo-Json -InputObject @($existing) -Depth 100 -Compress) -ceq
    (ConvertTo-Json -InputObject $merged -Depth 100 -Compress))
if ($sameKeys -and $stateBefore -ceq $stateAfter) {
    Write-Host '이미 같은 Codex 단축키입니다. 설정과 기존 복구 백업을 변경하지 않았습니다.'
    return
}
# Preserve original formatting when only global hotkeys need an update.
if ($sameKeys) { $keysAfter = $keysBefore }
$backup = Join-Path $backupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$manifest = @{
    version = 2; keysExisted = $keysExisted; globals = $oldGlobals
    appliedGlobals = $globals; appliedHash = $null; restored = $false; status = 'backed-up'
}
if ($keysExisted) {
    # Back up the exact snapshot used for the merge, not a second, potentially changed read.
    Set-PortableTextFile -Path (Join-Path $backup 'keybindings.json') -Text $keysBefore -BeforeExists $false
}
Save-PortableJson -Path (Join-Path $backup 'before.json') -Value $manifest
$changes = @(
    @{ Path = $keysFile; BeforeExists = $keysExisted; BeforeText = $keysBefore; AfterExists = $true; AfterText = $keysAfter }
    @{ Path = $stateFile; BeforeExists = $true; BeforeText = $stateBefore; AfterExists = $true; AfterText = $stateAfter }
)
try {
    Invoke-PortableFileTransaction -Changes $changes -Guard $guard -AfterCommit {
        $manifest.appliedHash = (Get-FileHash -LiteralPath $keysFile).Hash
        $manifest.status = 'saved'
        Save-PortableJson -Path (Join-Path $backup 'before.json') -Value $manifest
        $pointerExists = [IO.File]::Exists($latestFile)
        $pointerBefore = if ($pointerExists) { [IO.File]::ReadAllText($latestFile) } else { $null }
        Set-PortableTextFile -Path $latestFile -Text $backup -BeforeExists $pointerExists -BeforeText $pointerBefore
    }
} catch {
    $manifest.status = 'failed'
    Save-PortableJson -Path (Join-Path $backup 'before.json') -Value $manifest
    Write-Host ('적용하지 못했습니다. 복구용 백업: ' + $backup)
    throw
}
Write-Host ('Codex 사용자 지정 단축키 ' + $source.Count + '개와 전역 단축키 ' + @($globals.PSObject.Properties).Count + '개를 저장했습니다.')
Write-Host '동일 명령은 이 프로필로 바꾸고 다른 명령은 유지했습니다. Codex를 다시 실행하세요.'
