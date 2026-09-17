#requires -Version 5.1
# Shared, side-effect-free helpers. Dot-sourcing does not read or change user settings.

function ConvertFrom-PortableJson {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text,
          [ValidateSet('Any', 'Object', 'Array')][string]$Kind = 'Any')
    try {
        $trimmed = $Text.TrimStart()
        if ($Kind -eq 'Object' -and -not $trimmed.StartsWith('{')) { throw 'object required' }
        if ($Kind -eq 'Array' -and -not $trimmed.StartsWith('[')) { throw 'array required' }
        if ($Kind -eq 'Any' -and $Text.Trim() -ceq 'null') { return ,$null }
        $value = ConvertFrom-Json -InputObject $Text -ErrorAction Stop
        if ($Kind -eq 'Object' -and $null -eq $value) { throw 'object required' }
        if ($Kind -eq 'Array') {
            if ($trimmed -match '^\[\s*\]$') { return ,([object[]]@()) }
            return ,@($value)
        }
        return ,$value
    } catch {
        throw 'JSON 설정 형식이 올바르지 않습니다. 원본 내용은 출력하지 않습니다.'
    }
}

function Read-PortableJson {
    param([string]$Path, [ValidateSet('Any', 'Object', 'Array')][string]$Kind = 'Any')
    return ,(ConvertFrom-PortableJson -Text ([IO.File]::ReadAllText($Path)) -Kind $Kind)
}

function Get-PortableJsonLayout {
    param([string]$Text)
    $null = ConvertFrom-PortableJson -Text $Text -Kind Object
    $members = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $depth = 0
    $expectName = $false
    $current = $null
    $rootStart = -1
    # Strings are one token, so braces and property-like text inside them are ignored.
    foreach ($token in [regex]::Matches($Text, '"(?:\\.|[^"\\])*"|[{}\[\]:,]')) {
        $part = $token.Value
        if ($part -eq '{' -or $part -eq '[') {
            if ($depth -eq 0) { $rootStart = $token.Index; $expectName = $true }
            $depth++
        } elseif ($part -eq '}' -or $part -eq ']' -or ($part -eq ',' -and $depth -eq 1)) {
            if ($depth -eq 1 -and $null -ne $current) {
                $end = $token.Index
                while ($end -gt $current.ValueStart -and [char]::IsWhiteSpace($Text[$end - 1])) { $end-- }
                $current.End = $end
                if ($members.ContainsKey($current.Name)) { throw '최상위 JSON 속성이 중복되어 자동 편집하지 않습니다.' }
                $members.Add($current.Name, $current)
                $current = $null
            }
            if ($part -eq ',') { $expectName = $true } else { $depth-- }
        } elseif ($depth -eq 1 -and $part -eq ':') {
            $current.ValueStart = $token.Index + 1
            while ([char]::IsWhiteSpace($Text[$current.ValueStart])) { $current.ValueStart++ }
        } elseif ($depth -eq 1 -and $expectName -and $part.StartsWith('"')) {
            $current = [pscustomobject]@{
                Name = [string](ConvertFrom-Json -InputObject $part)
                Start = $token.Index
                ValueStart = 0
                End = 0
            }
            $expectName = $false
        }
    }
    return [pscustomobject]@{ Start = $rootStart; Members = $members }
}

function Set-PortableJsonString {
    param([string]$Text,
          [ValidateSet('appshotHotkey', 'hotkeyWindowHotkey')][string]$Name,
          [AllowNull()]$Value, [bool]$Exists = $true)
    if ($null -ne $Value -and $Value -isnot [string]) { throw '단축키 값은 문자열 또는 null이어야 합니다.' }
    $layout = Get-PortableJsonLayout -Text $Text
    $member = $null
    if ($layout.Members.ContainsKey($Name)) {
        $member = $layout.Members[$Name]
        $old = ConvertFrom-PortableJson -Text $Text.Substring($member.ValueStart, $member.End - $member.ValueStart)
        if ($null -ne $old -and $old -isnot [string]) { throw '기존 단축키 값의 형식이 달라 자동 편집하지 않습니다.' }
        if ($Exists -and [object]::Equals($old, $Value)) { return $Text }
    } elseif (-not $Exists) { return $Text }

    if ($Exists) {
        $jsonValue = if ($null -eq $Value) { 'null' } else { ConvertTo-Json -InputObject $Value -Compress }
        $pair = '"' + $Name + '":' + $jsonValue
        if ($null -ne $member) {
            $result = $Text.Substring(0, $member.Start) + $pair + $Text.Substring($member.End)
        } else {
            $separator = if ($layout.Members.Count) { ',' } else { '' }
            $result = $Text.Insert($layout.Start + 1, $pair + $separator)
        }
    } else {
        $left = $Text.Substring(0, $member.Start)
        $right = $Text.Substring($member.End)
        if ($right -match '^\s*,') { $right = [regex]::Replace($right, '^\s*,', '') }
        else { $left = [regex]::Replace($left, ',\s*$', '') }
        $result = $left + $right
    }
    $null = ConvertFrom-PortableJson -Text $result -Kind Object
    return $result
}

function Assert-PortableFileState {
    param([string]$Path, [bool]$Exists, [AllowNull()][AllowEmptyString()][string]$Text)
    if ([IO.File]::Exists($Path) -ne $Exists) { throw '설정 파일의 존재 여부가 작업 중 변경되어 저장하지 않습니다.' }
    if ($Exists -and [IO.File]::ReadAllText($Path) -cne $Text) { throw '설정 파일이 작업 중 변경되어 저장하지 않습니다.' }
}

function Set-PortableTextFile {
    param([string]$Path, [bool]$Exists = $true,
          [AllowNull()][AllowEmptyString()][string]$Text,
          [bool]$BeforeExists,
          [AllowNull()][AllowEmptyString()][string]$BeforeText,
          [scriptblock]$Guard)
    Assert-PortableFileState -Path $Path -Exists $BeforeExists -Text $BeforeText
    if ($Exists -eq $BeforeExists -and (-not $Exists -or $Text -ceq $BeforeText)) { return }
    if (-not $Exists) {
        if ($Guard) { & $Guard }
        Assert-PortableFileState -Path $Path -Exists $BeforeExists -Text $BeforeText
        [IO.File]::Delete($Path)
        return
    }
    # Same-directory staging permits an atomic rename/replace. Never truncate the destination.
    $temp = $Path + '.numberpad-' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $stream = [IO.File]::Open($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally { $stream.Dispose() }
        if ($Guard) { & $Guard }
        Assert-PortableFileState -Path $Path -Exists $BeforeExists -Text $BeforeText
        if ($BeforeExists) { [IO.File]::Replace($temp, $Path, $null) }
        else { [IO.File]::Move($temp, $Path) }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

function Invoke-PortableFileTransaction {
    param([object[]]$Changes, [scriptblock]$Guard, [scriptblock]$AfterCommit)
    $completed = [Collections.Generic.List[object]]::new()
    foreach ($change in $Changes) {
        Assert-PortableFileState -Path $change.Path -Exists $change.BeforeExists -Text $change.BeforeText
    }
    try {
        foreach ($change in $Changes) {
            Set-PortableTextFile -Path $change.Path -Exists $change.AfterExists -Text $change.AfterText `
                -BeforeExists $change.BeforeExists -BeforeText $change.BeforeText -Guard $Guard
            $completed.Add($change)
        }
        if ($AfterCommit) { & $AfterCommit }
    } catch {
        $failure = $_
        $rollbackFailed = $false
        for ($i = $completed.Count - 1; $i -ge 0; $i--) {
            $change = $completed[$i]
            try {
                Set-PortableTextFile -Path $change.Path -Exists $change.BeforeExists -Text $change.BeforeText `
                    -BeforeExists $change.AfterExists -BeforeText $change.AfterText -Guard $Guard
            } catch { $rollbackFailed = $true }
        }
        if ($rollbackFailed) { throw '자동 복구를 완료하지 못했습니다. 백업을 확인하세요. 이후 변경된 파일은 덮어쓰지 않았습니다.' }
        throw $failure
    }
}

function Save-PortableJson {
    param([string]$Path, $Value)
    $exists = [IO.File]::Exists($Path)
    $before = if ($exists) { [IO.File]::ReadAllText($Path) } else { $null }
    Set-PortableTextFile -Path $Path -Text (ConvertTo-Json -InputObject $Value -Depth 100) `
        -BeforeExists $exists -BeforeText $before
}

function Resolve-PortableBackup {
    param([string]$Root, [string]$Pointer)
    if (-not [IO.File]::Exists($Pointer)) { throw '이 PC에서 만든 복구 백업이 없습니다.' }
    $path = [IO.Path]::GetFullPath([IO.File]::ReadAllText($Pointer).Trim())
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not [IO.Directory]::Exists($path)) {
        throw '백업 경로가 올바르지 않습니다.'
    }
    return $path
}

function Merge-PortableKeybindings {
    param([AllowEmptyCollection()][object[]]$Existing, [object[]]$Source)
    $commands = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($binding in $Source) {
        if ($binding.command -isnot [string] -or [string]::IsNullOrWhiteSpace($binding.command) -or
            $null -eq $binding.PSObject.Properties['key'] -or
            ($null -ne $binding.key -and $binding.key -isnot [string])) { throw '단축키 프로필 형식이 올바르지 않습니다.' }
        if (-not $commands.Add($binding.command)) { throw '단축키 프로필에 같은 명령이 중복되어 있습니다.' }
    }
    $merged = [Collections.Generic.List[object]]::new()
    foreach ($binding in $Existing) {
        if ($binding.command -isnot [string] -or [string]::IsNullOrWhiteSpace($binding.command)) { throw '기존 단축키 형식이 올바르지 않습니다.' }
        if (-not $commands.Contains($binding.command)) { $merged.Add($binding) }
    }
    foreach ($binding in $Source) { $merged.Add($binding) }
    return ,$merged.ToArray()
}

function Assert-PortableAppsClosed {
    param([switch]$IncludeKeyboardCenter)
    $names = @('ChatGPT', 'Codex')
    if ($IncludeKeyboardCenter) { $names += 'MouseKeyboardCenter' }
    if (Get-Process -Name $names -ErrorAction SilentlyContinue) {
        throw 'Codex와 Microsoft 마우스·키보드 센터를 완전히 종료한 뒤 실행하세요. 강제 종료하지 않습니다.'
    }
}
