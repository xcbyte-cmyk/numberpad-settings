param([ValidateSet('Check','Apply','Restore')][string]$Mode='Check')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$root=if($env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path $env:USERPROFILE '.codex'}
$keysFile=Join-Path $root 'keybindings.json'
$stateFile=Join-Path $root '.codex-global-state.json'
$source=Get-Content -Raw -Encoding UTF8 -LiteralPath "$PSScriptRoot\keybindings.json"|ConvertFrom-Json
$globals=Get-Content -Raw -Encoding UTF8 -LiteralPath "$PSScriptRoot\global-hotkeys.json"|ConvertFrom-Json
$backupRoot=Join-Path $env:LOCALAPPDATA 'NumberPad-Codex-Shortcuts'
$utf8=[Text.UTF8Encoding]::new($false)
function ReadJson($path){try{return [IO.File]::ReadAllText($path)|ConvertFrom-Json -ErrorAction Stop}catch{throw 'JSON 설정을 읽지 못했습니다. 원본 내용은 출력하지 않습니다.'}}
function GlobalText($text,$name,$value,$exists){
    if($name -notin @('appshotHotkey','hotkeyWindowHotkey')){throw '허용되지 않는 설정 이름'}
    $pattern='"'+$name+'"\s*:\s*(?:"(?:\\.|[^"\\])*"|null)'
    $m=[regex]::Matches($text,$pattern)
    if($m.Count -gt 1){throw '중복 설정 이름이 있어 자동 편집하지 않습니다.'}
    if($exists){
        $pair='"'+$name+'":'+(ConvertTo-Json -InputObject $value -Compress)
        if($m.Count){return $text.Substring(0,$m[0].Index)+$pair+$text.Substring($m[0].Index+$m[0].Length)}
        $at=$text.IndexOf('{');$hasOther=$text.Substring($at+1).Trim() -ne '}'
        return $text.Insert($at+1,$pair+$(if($hasOther){','}else{''}))
    }
    if(-not $m.Count){return $text}
    $left=$text.Substring(0,$m[0].Index);$right=$text.Substring($m[0].Index+$m[0].Length)
    if($right -match '^\s*,'){$right=[regex]::Replace($right,'^\s*,','')}else{$left=[regex]::Replace($left,',\s*$','')}
    return $left+$right
}
if($Mode -eq 'Check'){
    $source|Select-Object command,key|Format-Table -AutoSize
    Write-Host '내보낸 사용자 지정 단축키 목록입니다. null은 해당 명령의 단축키 해제를 뜻합니다.'
    if(Test-Path -LiteralPath $stateFile){$s=ReadJson $stateFile;Write-Host ('현재 앱샷: '+$s.appshotHotkey);Write-Host ('현재 창 호출: '+$s.hotkeyWindowHotkey)}
    exit 0
}
if(Get-Process ChatGPT -ErrorAction SilentlyContinue){throw 'Codex를 파일 → ChatGPT 종료로 완전히 종료한 후 실행하세요.'}
if(-not(Test-Path -LiteralPath $stateFile)){throw '이 PC에서 Codex를 먼저 실행하고 로그인한 뒤 종료하세요.'}
$original=[IO.File]::ReadAllText($stateFile);$state=ReadJson $stateFile
$changed=$original
if($Mode -eq 'Restore'){
    $latest=Join-Path $backupRoot 'latest.txt'
    if(-not(Test-Path -LiteralPath $latest)){throw '이 PC의 복구 백업이 없습니다.'}
    $backup=[IO.File]::ReadAllText($latest).Trim()
    if(-not ([IO.Path]::GetFullPath($backup)).StartsWith(([IO.Path]::GetFullPath($backupRoot)+'\'),[StringComparison]::OrdinalIgnoreCase)){throw '잘못된 백업 경로'}
    $manifest=ReadJson "$backup\before.json"
    if($manifest.restored){throw '이미 복구한 백업입니다.'}
    if((Get-FileHash -LiteralPath $keysFile).Hash -ne $manifest.appliedHash){throw '단축키가 이후 변경됐습니다. 덮어쓰지 않습니다.'}
    foreach($p in $globals.PSObject.Properties){if($state.($p.Name) -ne $p.Value){throw '전역 단축키가 이후 변경됐습니다. 덮어쓰지 않습니다.'};$old=$manifest.globals.($p.Name);$changed=GlobalText $changed $p.Name $old.value $old.existed}
    $null=$changed|ConvertFrom-Json
    if([IO.File]::ReadAllText($stateFile) -ne $original){throw '설정이 작업 중 변경됐습니다.'}
    if($manifest.keysExisted){Copy-Item -LiteralPath "$backup\keybindings.json" -Destination $keysFile -Force}else{Remove-Item -LiteralPath $keysFile}
    [IO.File]::WriteAllText($stateFile,$changed,$utf8)
    $manifest.restored=$true;[IO.File]::WriteAllText("$backup\before.json",($manifest|ConvertTo-Json -Depth 10),$utf8)
    Write-Host '이 PC의 이전 Codex 단축키로 복구했습니다. Codex를 다시 실행하세요.'
    exit 0
}
$existing=if(Test-Path -LiteralPath $keysFile){@(ReadJson $keysFile)}else{@()}
$sourceCommands=@($source|ForEach-Object {$_.command})
$merged=@($existing|Where-Object {$_.command -notin $sourceCommands})+@($source)
$oldGlobals=@{}
foreach($p in $globals.PSObject.Properties){$oldGlobals[$p.Name]=@{existed=($null -ne $state.PSObject.Properties[$p.Name]);value=$state.($p.Name)};$changed=GlobalText $changed $p.Name $p.Value $true}
$null=$changed|ConvertFrom-Json
$backup=Join-Path $backupRoot ((Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $backup -Force|Out-Null
$manifest=@{keysExisted=(Test-Path -LiteralPath $keysFile);globals=$oldGlobals;appliedHash=$null;restored=$false}
if($manifest.keysExisted){Copy-Item -LiteralPath $keysFile -Destination "$backup\keybindings.json"}
[IO.File]::WriteAllText("$backup\before.json",($manifest|ConvertTo-Json -Depth 10),$utf8)
if([IO.File]::ReadAllText($stateFile) -ne $original){throw '설정이 작업 중 변경됐습니다.'}
try{
    [IO.File]::WriteAllText($keysFile,(ConvertTo-Json -InputObject $merged -Depth 20),$utf8)
    [IO.File]::WriteAllText($stateFile,$changed,$utf8)
    $manifest.appliedHash=(Get-FileHash -LiteralPath $keysFile).Hash
    [IO.File]::WriteAllText("$backup\before.json",($manifest|ConvertTo-Json -Depth 10),$utf8)
    [IO.File]::WriteAllText((Join-Path $backupRoot 'latest.txt'),$backup,$utf8)
}catch{
    if($manifest.keysExisted){Copy-Item -LiteralPath "$backup\keybindings.json" -Destination $keysFile -Force}elseif(Test-Path -LiteralPath $keysFile){Remove-Item -LiteralPath $keysFile}
    if([IO.File]::ReadAllText($stateFile) -eq $changed){[IO.File]::WriteAllText($stateFile,$original,$utf8)}
    throw
}
Write-Host 'Codex 사용자 지정 단축키 13개와 전역 단축키 2개를 저장했습니다. Codex를 다시 실행하세요.'
Write-Host '동일 명령은 이 프로필로 바꾸고, 프로필에 없는 기존 명령은 유지했습니다.'
