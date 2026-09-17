param([ValidateSet('Check','Apply','Restore')][string]$Mode='Check')
$ErrorActionPreference='Stop'
function DecodeMap([byte[]]$bytes){
    $map=[ordered]@{}
    if($bytes -and $bytes.Length){
        if($bytes.Length -lt 16){throw '기존 Windows 키 변환 형식이 올바르지 않습니다.'}
        $count=[BitConverter]::ToUInt32($bytes,8)
        if($count -lt 1 -or $bytes.Length -ne 12+4*$count -or [BitConverter]::ToUInt32($bytes,$bytes.Length-4) -ne 0){throw '기존 Windows 키 변환 형식을 안전하게 해석하지 못했습니다.'}
        for($i=0;$i -lt $count-1;$i++){$offset=12+4*$i;$src=[BitConverter]::ToUInt16($bytes,$offset+2);$dst=[BitConverter]::ToUInt16($bytes,$offset);$map[[string]$src]=[int]$dst}
    }
    return $map
}
function EncodeMap($map){
    $bytes=New-Object byte[] (12+4*($map.Count+1))
    [BitConverter]::GetBytes([uint32]($map.Count+1)).CopyTo($bytes,8)
    $offset=12;foreach($src in $map.Keys){[BitConverter]::GetBytes([uint16]$map[$src]).CopyTo($bytes,$offset);[BitConverter]::GetBytes([uint16]$src).CopyTo($bytes,$offset+2);$offset+=4}
    return ,$bytes
}
if($MyInvocation.InvocationName -eq '.'){return}
if($Mode -ne 'Check'){
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=[Security.Principal.WindowsPrincipal]::new($identity)
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
        $args='-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1}' -f $PSCommandPath,$Mode
        $p=Start-Process powershell.exe -ArgumentList $args -Verb RunAs -Wait -PassThru
        exit $p.ExitCode
    }
}
$key='HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
$regKey=Get-Item -LiteralPath $key
$bytes=$regKey.GetValue('Scancode Map')
$map=DecodeMap $bytes
$desired=@{'109'=42;'110'=54}
if($Mode -eq 'Check'){Write-Host ('F22 변환: '+$map['109']+' / F23 변환: '+$map['110']);Write-Host '목표: 42(왼쪽 Shift), 54(오른쪽 Shift). 조회만 했습니다.';exit 0}
$folder=Join-Path $env:ProgramData 'NumberPad-Portable'
$backupFile=Join-Path $folder 'shift-before.json'
if($Mode -eq 'Apply'){
    if($map['109'] -eq 42 -and $map['110'] -eq 54){Write-Host '이미 같은 Windows 변환입니다. 변경하지 않았습니다.';exit 0}
    if(Test-Path -LiteralPath $backupFile){throw 'Windows 변환 백업이 이미 있습니다. 먼저 복구하거나 기존 백업을 확인하세요.'}
    New-Item -ItemType Directory -Path $folder -Force|Out-Null
    $before=@{};foreach($src in $desired.Keys){$before[$src]=@{existed=$map.Contains($src);value=$map[$src]}}
    $before|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $backupFile -Encoding UTF8
    foreach($src in $desired.Keys){$map[$src]=$desired[$src]}
}else{
    if(-not(Test-Path -LiteralPath $backupFile)){throw '이 PC에서 생성된 Windows 키 변환 백업이 없습니다.'}
    if($map['109'] -ne 42 -or $map['110'] -ne 54){throw 'Windows 키 변환이 이후 바뀌었습니다. 자동으로 덮어쓰지 않습니다.'}
    $before=Get-Content -Raw -Encoding UTF8 -LiteralPath $backupFile|ConvertFrom-Json
    foreach($src in $desired.Keys){$entry=$before.PSObject.Properties[$src].Value;if($entry.existed){$map[$src]=[int]$entry.value}else{$map.Remove($src)}}
}
if($map.Count -gt 0){New-ItemProperty -LiteralPath $key -Name 'Scancode Map' -PropertyType Binary -Value (EncodeMap $map) -Force|Out-Null}else{Remove-ItemProperty -LiteralPath $key -Name 'Scancode Map' -ErrorAction SilentlyContinue}
$actual=DecodeMap ((Get-Item -LiteralPath $key).GetValue('Scancode Map'))
foreach($src in $map.Keys){if($actual[$src] -ne $map[$src]){throw 'Windows 키 변환 저장 확인 실패'}}
if($Mode -eq 'Restore'){Move-Item -LiteralPath $backupFile -Destination ($backupFile+'.restored-'+(Get-Date -Format yyyyMMddHHmmss))}
Write-Host 'Windows 키 변환을 저장했습니다. PC를 재부팅하면 반영됩니다. 자동으로 재부팅하지 않습니다.'
