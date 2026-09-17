#requires -Version 5.1
# Called by Run.Tests.ps1. Only pure functions are loaded; no registry access or UAC.
. (Join-Path $repo 'windows/Windows-Shift.ps1')
. (Join-Path $repo 'windows/Transfer.ps1')
Test-Case 'scancode map round-trip preserves unrelated and disabled keys' {
    $map = [ordered]@{ '109' = 42; '110' = 54; '1' = 0; '57421' = 57419 }
    $decoded = DecodeMap (EncodeMap $map)
    Assert-Equal @($decoded.Keys) @($map.Keys)
    foreach ($key in $map.Keys) { Assert-Equal $decoded[$key] $map[$key] }
}
Test-Case 'absent and empty scancode maps are supported' {
    Assert-Equal (DecodeMap $null).Count 0
    Assert-Equal (DecodeMap (EncodeMap ([ordered]@{}))).Count 0
}
Test-Case 'bad scancode headers lengths and terminators are rejected' {
    $bytes = EncodeMap ([ordered]@{ '109' = 42 })
    $bytes[0] = 1
    Assert-Throws { DecodeMap $bytes }
    $bytes = EncodeMap ([ordered]@{ '109' = 42 })
    $bytes[$bytes.Length - 1] = 1
    Assert-Throws { DecodeMap $bytes }
    Assert-Throws { DecodeMap ([byte[]]@(0, 0, 0)) }
}
Test-Case 'duplicate scancode sources are rejected' {
    $bytes = EncodeMap ([ordered]@{ '109' = 42; '110' = 54 })
    [BitConverter]::GetBytes([uint16]109).CopyTo($bytes, 18)
    Assert-Throws { DecodeMap $bytes }
}
Test-Case 'zero scancode sources are rejected but zero destinations work' {
    Assert-Throws { EncodeMap ([ordered]@{ '0' = 42 }) }
    $disabled = DecodeMap (EncodeMap ([ordered]@{ '109' = 0 }))
    Assert-Equal $disabled['109'] 0
}
Test-Case 'exported profile still contains the confirmed mappings' {
    $profile = Read-PortableJson -Path (Join-Path $repo 'windows/profile.json') -Kind Object
    Assert-NumberPadProfile $profile
    Assert-Equal $profile.events.Count 16
    Assert-Equal $profile.macros.Count 2
    $expected = @{ '59' = 27; '937' = 133; '938' = 134; '941' = 1671 }
    foreach ($id in $expected.Keys) {
        $event = $profile.events | Where-Object { $_.id -eq $id }
        Assert-Equal ($event.values | Where-Object { $_.name -eq 'Keystroke' }).value $expected[$id]
    }
    Assert-Equal $profile.appshotHotkey 'Ctrl+Alt+F24'
    Assert-Equal @($profile.scanMappings.source) @(109, 110)
    Assert-Equal @($profile.scanMappings.target) @(42, 54)
}
Test-Case 'unsafe macro names and profile paths are rejected' {
    foreach ($name in @('../escape.mhm', '..\escape.mhm', 'C:\escape.mhm', 'x.mhm:stream', 'x.txt', '')) {
        Assert-Throws { Assert-MacroName $name }
    }
    $profile = Read-PortableJson -Path (Join-Path $repo 'windows/profile.json') -Kind Object
    $profile.events[0].id = '../escape'
    Assert-Throws { Assert-NumberPadProfile $profile }
}
Test-Case 'duplicate event identifiers are rejected' {
    $profile = Read-PortableJson -Path (Join-Path $repo 'windows/profile.json') -Kind Object
    $profile.events[1].id = $profile.events[0].id
    Assert-Throws { Assert-NumberPadProfile $profile }
}
Test-Case 'CMD launchers preserve the PowerShell exit code' {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repo 'windows'), (Join-Path $repo 'codex') -Filter '*.cmd') {
        $text = [IO.File]::ReadAllText($file.FullName)
        Assert-True ($text.Contains('set "exitCode=%ERRORLEVEL%"'))
        Assert-True ($text.Contains('exit /b %exitCode%'))
    }
}
