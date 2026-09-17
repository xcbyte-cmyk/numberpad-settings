param([ValidateSet('Check','Apply','Restore')][string]$Mode='Check')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
function ParseJson([string]$text){try{return ConvertFrom-Json -InputObject $text -ErrorAction Stop}catch{throw 'JSON 설정을 읽지 못했습니다. 원본 설정 내용은 출력하지 않습니다.'}}
$profile=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'profile.json') | ConvertFrom-Json
$reg='HKCU\Software\Microsoft\IntelliType Pro\ModelSpecific\7026\EventMapping'
$psReg='HKCU:\Software\Microsoft\IntelliType Pro\ModelSpecific\7026\EventMapping'
$macroRoot=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Microsoft Hardware\Macros'
$codexRoot=if($env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path $env:USERPROFILE '.codex'}
$stateFile=Join-Path $codexRoot '.codex-global-state.json'
$backupRoot=Join-Path $env:LOCALAPPDATA 'NumberPad-Portable\Backups'
$latestFile=Join-Path $backupRoot 'latest.txt'
$utf8=[Text.UTF8Encoding]::new($false)
function SaveJson($file,$value){[IO.File]::WriteAllText($file,($value|ConvertTo-Json -Depth 100),$utf8)}
function NeedClosed {
    if(Get-Process ChatGPT,MouseKeyboardCenter -ErrorAction SilentlyContinue){throw 'Codex와 Microsoft 마우스·키보드 센터 창을 완전히 종료한 뒤 다시 실행하세요. 강제 종료하지 않습니다.'}
}
function HotkeyText([string]$text,[bool]$exists,$value){
    $parsed=ParseJson $text
    $pattern='"appshotHotkey"\s*:\s*(?:"(?:\\.|[^"\\])*"|null)'
    $matches=[regex]::Matches($text,$pattern)
    if($matches.Count -gt 1){throw '앱샷 설정 위치가 중복되어 자동 편집하지 않습니다.'}
    if($exists){
        $pair='"appshotHotkey":'+(ConvertTo-Json -InputObject $value -Compress)
        if($matches.Count -eq 1){$m=$matches[0];$result=$text.Substring(0,$m.Index)+$pair+$text.Substring($m.Index+$m.Length)}
        else {$at=$text.IndexOf('{');if($at -lt 0){throw '잘못된 Codex 설정 파일'};$hasOther=$parsed.PSObject.Properties.Count -gt 0;$result=$text.Insert($at+1,$pair+$(if($hasOther){','}else{''}))}
    } elseif($matches.Count -eq 1){
        $m=$matches[0];$left=$text.Substring(0,$m.Index);$right=$text.Substring($m.Index+$m.Length)
        if($right -match '^\s*,'){$right=[regex]::Replace($right,'^\s*,','')}else{$left=[regex]::Replace($left,',\s*$','')}
        $result=$left+$right
    } else {$result=$text}
    $null=ParseJson $result
    return $result
}
function WriteState([string]$before,[string]$after){
    NeedClosed
    if([IO.File]::ReadAllText($stateFile) -ne $before){throw 'Codex 설정이 실행 중 변경되어 저장하지 않습니다.'}
    $tmp=$stateFile+'.numberpad.tmp'
    if(Test-Path -LiteralPath $tmp){throw '이전 임시 설정 파일이 있습니다. 확인 후 다시 실행하세요.'}
    try{[IO.File]::WriteAllText($tmp,$after,$utf8);[IO.File]::Replace($tmp,$stateFile,$null)}finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp}}
}
foreach($name in $profile.macros){
    if([IO.Path]::GetFileName($name) -ne $name -or $name -notlike '*.mhm'){throw '허용되지 않는 매크로 파일 이름'}
    if(-not(Test-Path -LiteralPath (Join-Path "$PSScriptRoot\macros" $name))){throw "매크로 파일이 없습니다: $name"}
}
if($Mode -eq 'Check'){
    Write-Host ('프로필 저장 날짜: '+$profile.capturedAt)
    Write-Host ('Number Pad 키 설정: '+$profile.events.Count+'개 / 매크로 파일: '+$profile.macros.Count+'개')
    foreach($id in @('937','941')){if(Test-Path -LiteralPath "$psReg\$id"){Get-ItemProperty -LiteralPath "$psReg\$id"|Select-Object Command,KeystrokeText,Macro|Format-List}}
    if(Test-Path -LiteralPath $stateFile){Write-Host ('이 PC 앱샷: '+(ParseJson ([IO.File]::ReadAllText($stateFile))).appshotHotkey)}else{Write-Host '이 PC에 Codex 설정이 아직 없습니다. 앱샷은 Codex 최초 실행 후 다시 적용하세요.'}
    Write-Host '조회만 했습니다. 설정은 변경하지 않았습니다.'
    exit 0
}
NeedClosed
if($Mode -eq 'Restore'){
    if(-not(Test-Path -LiteralPath $latestFile)){throw '이 PC에서 만든 복구 백업이 없습니다.'}
    $backup=Get-Content -Raw -Encoding UTF8 -LiteralPath $latestFile
    $backup=$backup.Trim()
    $resolved=[IO.Path]::GetFullPath($backup)
    if(-not $resolved.StartsWith(([IO.Path]::GetFullPath($backupRoot)+'\'),[StringComparison]::OrdinalIgnoreCase)){throw '백업 경로가 올바르지 않습니다.'}
    $manifest=Get-Content -Raw -Encoding UTF8 -LiteralPath "$backup\before.json"|ConvertFrom-Json
    if($manifest.restored){throw '이 백업은 이미 복구했습니다. 중복 복구하지 않습니다.'}
    if($manifest.codexChanged -and (Test-Path -LiteralPath $stateFile)){
        $text=[IO.File]::ReadAllText($stateFile)
        if((ParseJson $text).appshotHotkey -ne $profile.appshotHotkey){throw 'Codex 단축키가 이후 변경되어 자동 복구하지 않습니다.'}
        $newText=HotkeyText $text $manifest.hotkeyExisted $manifest.hotkey
    }
    if(Test-Path -LiteralPath $psReg){& reg.exe delete $reg /f|Out-Null;if($LASTEXITCODE -ne 0){throw 'Number Pad 설정 삭제 실패'}}
    if($manifest.registryExisted){& reg.exe import "$backup\before.reg"|Out-Null;if($LASTEXITCODE -ne 0){throw '레지스트리 복구 실패'}}
    foreach($entry in $manifest.macros){$dest=Join-Path $macroRoot $entry.name;if($entry.existed){Copy-Item -LiteralPath (Join-Path "$backup\macros" $entry.name) -Destination $dest -Force}elseif(Test-Path -LiteralPath $dest){Remove-Item -LiteralPath $dest}}
    if($manifest.codexChanged -and $null -ne $newText){WriteState $text $newText}
    $manifest.restored=$true;SaveJson "$backup\before.json" $manifest
    Write-Host '이 PC의 적용 전 Number Pad·매크로·앱샷 설정으로 복구했습니다. Windows Shift 변환은 별도 복구 파일을 사용하세요.'
    exit 0
}
$mkc=Join-Path $env:ProgramFiles 'Microsoft Mouse and Keyboard Center\MouseKeyboardCenter.exe'
if(-not(Test-Path -LiteralPath $mkc)){throw 'Microsoft 마우스·키보드 센터를 먼저 설치하고 Number Pad를 연결하세요. 사용안내의 공식 링크를 확인하세요.'}
$beforeText=$null;$afterText=$null;$hadHotkey=$false;$oldHotkey=$null
if(Test-Path -LiteralPath $stateFile){$beforeText=[IO.File]::ReadAllText($stateFile);$state=ParseJson $beforeText;$hadHotkey=$null -ne $state.PSObject.Properties['appshotHotkey'];$oldHotkey=$state.appshotHotkey;$afterText=HotkeyText $beforeText $true $profile.appshotHotkey}
$backup=Join-Path $backupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path "$backup\macros" -Force|Out-Null
$manifest=[ordered]@{registryExisted=(Test-Path -LiteralPath $psReg);hotkeyExisted=$hadHotkey;hotkey=$oldHotkey;codexChanged=($null -ne $afterText -and $beforeText -ne $afterText);macros=@();restored=$false;status='backed-up'}
if($manifest.registryExisted){& reg.exe export $reg "$backup\before.reg" /y|Out-Null;if($LASTEXITCODE -ne 0){throw '기존 설정 백업 실패'}}
foreach($name in $profile.macros){$dest=Join-Path $macroRoot $name;$exists=Test-Path -LiteralPath $dest;if($exists){Copy-Item -LiteralPath $dest -Destination (Join-Path "$backup\macros" $name)};$manifest.macros+=@{name=$name;existed=$exists}}
SaveJson "$backup\before.json" $manifest
[IO.File]::WriteAllText($latestFile,$backup,$utf8)
try{
    NeedClosed
    if(Test-Path -LiteralPath $psReg){& reg.exe delete $reg /f|Out-Null;if($LASTEXITCODE -ne 0){throw 'Number Pad 기존 설정 교체 실패'}}
    & reg.exe import (Join-Path $PSScriptRoot 'numberpad.reg')|Out-Null
    if($LASTEXITCODE -ne 0){throw 'Number Pad 설정 가져오기 실패'}
    New-Item -ItemType Directory -Path $macroRoot -Force|Out-Null
    foreach($name in $profile.macros){Copy-Item -LiteralPath (Join-Path "$PSScriptRoot\macros" $name) -Destination (Join-Path $macroRoot $name) -Force}
    if($manifest.codexChanged){WriteState $beforeText $afterText}
    foreach($event in $profile.events){$key=Get-Item -LiteralPath "$psReg\$($event.id)";foreach($value in $event.values){if($key.GetValue($value.name) -ne $value.value){throw "저장값 확인 실패: $($event.id)/$($value.name)"}}}
    foreach($name in $profile.macros){if((Get-FileHash -LiteralPath (Join-Path "$PSScriptRoot\macros" $name)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $macroRoot $name)).Hash){throw '매크로 복사 검증 실패'}}
    $manifest.status='saved';SaveJson "$backup\before.json" $manifest
    Write-Host '키 설정과 매크로를 저장했습니다. PC 재부팅 후 Microsoft 센터에서 키 배치와 실제 입력을 확인하세요.'
    if($null -eq $afterText){Write-Host 'Codex 미설정: 앱샷은 Codex를 처음 실행해 로그인한 뒤, 완전히 종료하고 이 파일을 다시 실행하세요.'}else{Write-Host ('Codex 앱샷 단축키: '+$profile.appshotHotkey)}
    Write-Host ('이 PC 복구 백업: '+$backup)
}catch{
    $manifest.status='failed';SaveJson "$backup\before.json" $manifest
    Write-Host '일부 설정만 적용됐을 수 있습니다. Restore.cmd로 이 PC의 백업을 복구하세요.'
    throw
}
