#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$script:passed = 0
function Assert-True($Condition, [string]$Message = 'Assertion failed') {
    if (-not $Condition) { throw $Message }
}
function Assert-Equal($Actual, $Expected) {
    if ((ConvertTo-Json -InputObject $Actual -Depth 100 -Compress) -cne
        (ConvertTo-Json -InputObject $Expected -Depth 100 -Compress)) { throw 'Values differ' }
}
function Assert-Throws([scriptblock]$Action) {
    $thrown = $false
    try { & $Action | Out-Null } catch { $thrown = $true }
    Assert-True $thrown 'Expected an error'
}
function Test-Case([string]$Name, [scriptblock]$Action) {
    & $Action
    $script:passed++
    Write-Host ('PASS ' + $Name)
}
foreach ($file in Get-ChildItem -LiteralPath $repo -Filter '*.ps1' -Recurse) {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ('PowerShell syntax error in ' + $file.Name + ': ' + $errors[0].Message) }
}
. (Join-Path $repo 'shared/Settings.ps1')
Test-Case 'empty JSON arrays stay empty' {
    $value = ConvertFrom-PortableJson -Text '[]' -Kind Array
    Assert-Equal $value.Count 0
}
Test-Case 'only top-level properties are edited' {
    $text = '{"nested":{"appshotHotkey":"KEEP"},"appshotHotkey":"OLD","n":1e+09}'
    $after = Set-PortableJsonString -Text $text -Name appshotHotkey -Value 'NEW'
    Assert-Equal $after '{"nested":{"appshotHotkey":"KEEP"},"appshotHotkey":"NEW","n":1e+09}'
}
Test-Case 'property-like text in a string is not edited' {
    $text = '{"text":"\"appshotHotkey\":\"KEEP\"","items":[{"appshotHotkey":"KEEP"}]}'
    $after = Set-PortableJsonString -Text $text -Name appshotHotkey -Value 'NEW'
    Assert-Equal $after ('{"appshotHotkey":"NEW",' + $text.Substring(1))
}
Test-Case 'escaped property names are recognized' {
    $after = Set-PortableJsonString -Text '{"appshot\u0048otkey":"OLD"}' -Name appshotHotkey -Value 'NEW'
    Assert-Equal $after '{"appshotHotkey":"NEW"}'
}
Test-Case 'identical values preserve formatting exactly' {
    $text = "{`n  `"appshotHotkey`" : `"SAME`"`n}"
    Assert-Equal (Set-PortableJsonString -Text $text -Name appshotHotkey -Value 'SAME') $text
}
Test-Case 'null and absent are distinct' {
    Assert-Equal (Set-PortableJsonString -Text '{}' -Name appshotHotkey -Value $null) '{"appshotHotkey":null}'
    Assert-Equal (Set-PortableJsonString -Text '{"appshotHotkey":null}' -Name appshotHotkey -Value $null -Exists $false) '{}'
}
Test-Case 'removal works for first middle last and only properties' {
    foreach ($text in @('{"appshotHotkey":"x","a":1}', '{"a":1,"appshotHotkey":"x","b":2}',
                         '{"a":1,"appshotHotkey":"x"}', '{"appshotHotkey":"x"}')) {
        $after = Set-PortableJsonString -Text $text -Name appshotHotkey -Value $null -Exists $false
        $layout = Get-PortableJsonLayout -Text $after
        Assert-True (-not $layout.Members.ContainsKey('appshotHotkey'))
    }
}
Test-Case 'invalid or ambiguous state is rejected' {
    foreach ($text in @('null', '[]', '{bad}', '{"appshotHotkey":42}', '{"appshotHotkey":false}',
                         '{"appshotHotkey":"a","appshotHotkey":"b"}')) {
        Assert-Throws { Set-PortableJsonString -Text $text -Name appshotHotkey -Value 'x' }
    }
}
Test-Case 'unknown global property is rejected' {
    Assert-Throws { Set-PortableJsonString -Text '{}' -Name 'unrelated' -Value 'x' }
}
Test-Case 'empty strings and escaped values are supported' {
    $after = Set-PortableJsonString -Text '{}' -Name appshotHotkey -Value ''
    Assert-Equal ((ConvertFrom-PortableJson -Text $after).appshotHotkey) ''
    $value = 'Ctrl+"quoted"\path'
    $after = Set-PortableJsonString -Text $after -Name appshotHotkey -Value $value
    Assert-Equal ((ConvertFrom-PortableJson -Text $after).appshotHotkey) $value
}
Test-Case 'merge keeps unrelated commands order and null unbindings' {
    $old = ConvertFrom-PortableJson -Text '[{"command":"keep","key":"K"},{"command":"REPLACE","key":"OLD"}]' -Kind Array
    $new = ConvertFrom-PortableJson -Text '[{"command":"replace","key":null},{"command":"add","key":"A"}]' -Kind Array
    $merged = Merge-PortableKeybindings -Existing $old -Source $new
    Assert-Equal @($merged.command) @('keep', 'replace', 'add')
    Assert-True ($null -eq $merged[1].key)
}
Test-Case 'duplicate source commands are rejected' {
    $source = ConvertFrom-PortableJson -Text '[{"command":"x","key":null},{"command":"X","key":"Y"}]' -Kind Array
    Assert-Throws { Merge-PortableKeybindings -Existing @() -Source $source }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('NumberPad-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $file = Join-Path $temp 'settings with spaces.json'
    Test-Case 'atomic create replace and delete' {
        Set-PortableTextFile -Path $file -Text 'before' -BeforeExists $false
        Set-PortableTextFile -Path $file -Text 'after' -BeforeExists $true -BeforeText 'before'
        Assert-Equal ([IO.File]::ReadAllText($file)) 'after'
        Set-PortableTextFile -Path $file -Exists $false -BeforeExists $true -BeforeText 'after'
        Assert-True (-not [IO.File]::Exists($file))
    }
    Test-Case 'concurrent changes are not overwritten' {
        [IO.File]::WriteAllText($file, 'newer')
        Assert-Throws { Set-PortableTextFile -Path $file -Text 'after' -BeforeExists $true -BeforeText 'old' }
        Assert-Equal ([IO.File]::ReadAllText($file)) 'newer'
    }
    Test-Case 'second-file failure rolls back the first file' {
        [IO.File]::WriteAllText($file, 'before')
        $changes = @(
            @{ Path=$file; BeforeExists=$true; BeforeText='before'; AfterExists=$true; AfterText='after' }
            @{ Path=(Join-Path $temp 'missing/second.json'); BeforeExists=$false; BeforeText=$null; AfterExists=$true; AfterText='x' }
        )
        Assert-Throws { Invoke-PortableFileTransaction -Changes $changes }
        Assert-Equal ([IO.File]::ReadAllText($file)) 'before'
    }
    Test-Case 'metadata failure also rolls back settings' {
        $changes = @(@{ Path=$file; BeforeExists=$true; BeforeText='before'; AfterExists=$true; AfterText='after' })
        Assert-Throws { Invoke-PortableFileTransaction -Changes $changes -AfterCommit { throw 'metadata failure' } }
        Assert-Equal ([IO.File]::ReadAllText($file)) 'before'
    }
    Test-Case 'rollback refuses to overwrite a later edit' {
        $changes = @(@{ Path=$file; BeforeExists=$true; BeforeText='before'; AfterExists=$true; AfterText='after' })
        Assert-Throws { Invoke-PortableFileTransaction -Changes $changes -AfterCommit { [IO.File]::WriteAllText($file, 'newer'); throw 'failure' } }
        Assert-Equal ([IO.File]::ReadAllText($file)) 'newer'
    }
    Test-Case 'temporary files are cleaned up' {
        Assert-Equal @(Get-ChildItem -LiteralPath $temp -Filter '*.tmp').Count 0
    }
    Test-Case 'backup pointer cannot escape its root' {
        $root = Join-Path $temp 'backups'
        New-Item -ItemType Directory -Path $root | Out-Null
        $pointer = Join-Path $root 'latest.txt'
        [IO.File]::WriteAllText($pointer, $temp)
        Assert-Throws { Resolve-PortableBackup -Root $root -Pointer $pointer }
    }

    # Integration tests touch only temporary files, never the real .codex folder or registry.
    $savedHome = $env:CODEX_HOME; $savedLocal = $env:LOCALAPPDATA
    try {
        $env:CODEX_HOME = Join-Path $temp 'codex home'
        $env:LOCALAPPDATA = Join-Path $temp 'local app data'
        New-Item -ItemType Directory -Path $env:CODEX_HOME, $env:LOCALAPPDATA | Out-Null
        $keys = Join-Path $env:CODEX_HOME 'keybindings.json'
        $state = Join-Path $env:CODEX_HOME '.codex-global-state.json'
        $originalKeys = '[{"command":"custom","key":"K"},{"command":"quickChat","key":"OLD"}]'
        $originalState = '{"nested":{"appshotHotkey":"KEEP"},"n":1e+09,"text":"keep { braces }"}'
        [IO.File]::WriteAllText($keys, $originalKeys)
        [IO.File]::WriteAllText($state, $originalState)
        function Invoke-CodexTest([string]$Mode, [bool]$Success = $true) {
            $preference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $output = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -ExecutionPolicy Bypass `
                    -File (Join-Path $repo 'codex/Transfer.ps1') -Mode $Mode 2>&1
                $code = $LASTEXITCODE
            } finally { $ErrorActionPreference = $preference }
            if (($code -eq 0) -ne $Success) { throw ('Unexpected exit code: ' + $code + [Environment]::NewLine + ($output -join [Environment]::NewLine)) }
        }
        Test-Case 'Codex apply preserves unrelated settings and commands' {
            Invoke-CodexTest Apply
            $result = Read-PortableJson -Path $keys -Kind Array
            Assert-Equal $result.Count 14
            Assert-Equal $result[0].command 'custom'
            Assert-Equal @($result | Where-Object { $null -eq $_.key }).Count 3
            $text = [IO.File]::ReadAllText($state)
            Assert-True ($text.Contains('"n":1e+09'))
            Assert-True ($text.Contains('"nested":{"appshotHotkey":"KEEP"}'))
        }
        Test-Case 'Codex repeat apply preserves the restore point' {
            $pointer = Join-Path $env:LOCALAPPDATA 'NumberPad-Codex-Shortcuts/latest.txt'
            $before = [IO.File]::ReadAllText($pointer)
            $keyTime = [IO.File]::GetLastWriteTimeUtc($keys)
            Invoke-CodexTest Apply
            Assert-Equal ([IO.File]::ReadAllText($pointer)) $before
            Assert-Equal ([IO.File]::GetLastWriteTimeUtc($keys)) $keyTime
        }
        Test-Case 'Codex restore returns to the original settings' {
            Invoke-CodexTest Restore
            Assert-Equal ([IO.File]::ReadAllText($keys)) $originalKeys
            Assert-Equal ([IO.File]::ReadAllText($state)) $originalState
            Invoke-CodexTest Restore $false
        }
        Test-Case 'Codex handles an originally absent keybindings file' {
            [IO.File]::Delete($keys)
            Invoke-CodexTest Apply
            Assert-Equal (Read-PortableJson -Path $keys -Kind Array).Count 13
            Invoke-CodexTest Restore
            Assert-True (-not [IO.File]::Exists($keys))
        }
        Test-Case 'Codex handles an empty keybindings array' {
            [IO.File]::WriteAllText($keys, '[]')
            Invoke-CodexTest Apply
            Invoke-CodexTest Restore
            Assert-Equal ([IO.File]::ReadAllText($keys)) '[]'
        }
        Test-Case 'Codex rejects malformed keybindings without changing state' {
            [IO.File]::WriteAllText($keys, '{bad}')
            Invoke-CodexTest Apply $false
            Assert-Equal ([IO.File]::ReadAllText($state)) $originalState
            Assert-Equal ([IO.File]::ReadAllText($keys)) '{bad}'
        }
        Test-Case 'Codex restore does not overwrite later edits' {
            [IO.File]::WriteAllText($keys, $originalKeys)
            Invoke-CodexTest Apply
            [IO.File]::WriteAllText($keys, '[]')
            $before = [IO.File]::ReadAllText($state)
            Invoke-CodexTest Restore $false
            Assert-Equal ([IO.File]::ReadAllText($keys)) '[]'
            Assert-Equal ([IO.File]::ReadAllText($state)) $before
        }
    } finally {
        $env:CODEX_HOME = $savedHome; $env:LOCALAPPDATA = $savedLocal
    }
    Test-Case 'Windows payload checksums match' {
        foreach ($line in Get-Content -LiteralPath (Join-Path $repo 'windows/SHA256.txt')) {
            if ($line -match '^([0-9A-Fa-f]{64})  (.+)$') {
                $expected = $Matches[1]
                $relative = $Matches[2].Replace('\', [IO.Path]::DirectorySeparatorChar)
                Assert-Equal (Get-FileHash -LiteralPath (Join-Path (Join-Path $repo 'windows') $relative)).Hash $expected.ToUpperInvariant()
            } else { throw 'Invalid SHA256 manifest line' }
        }
    }
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Host ('Passed ' + $script:passed + ' tests on PowerShell ' + $PSVersionTable.PSVersion)
