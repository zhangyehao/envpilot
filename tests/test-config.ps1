param([switch]$Child, [string]$Fixture)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Child) {
    $fixturePath = Join-Path ([IO.Path]::GetTempPath()) ('envpilot-config-' + [guid]::NewGuid().ToString('N'))
    $previousProfile = $env:USERPROFILE
    try {
        $env:USERPROFILE = $fixturePath
        $executable = (Get-Process -Id $PID).Path
        & $executable -NoProfile -File $PSCommandPath -Child -Fixture $fixturePath
        if ($LASTEXITCODE -ne 0) { throw 'Configuration integration test failed.' }
    } finally {
        $env:USERPROFILE = $previousProfile
        $resolved = [IO.Path]::GetFullPath($fixturePath)
        $temporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($temporary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
    return
}
if ([IO.Path]::GetFullPath($HOME) -ne [IO.Path]::GetFullPath($Fixture)) { throw 'Test did not isolate HOME.' }
$env:ENVPILOT_CONFIG_DIR = Join-Path $HOME '.config/envpilot'
$env:ENVPILOT_LANG = 'en'
$env:ENVPILOT_PROFILE = Join-Path $HOME 'Documents/PowerShell/Microsoft.PowerShell_profile.ps1'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $env:ENVPILOT_PROFILE) | Out-Null
$original = '# user profile' + "`n" + 'function Existing-CustomFunction { "original" }' + "`n"
[IO.File]::WriteAllText($env:ENVPILOT_PROFILE, $original)
& "$Root/envpilot.ps1" init -Lang en
& "$Root/envpilot.ps1" config validate
$localized = & "$Root/envpilot.ps1" plan -Lang zh-CN | Out-String
if ($localized -notmatch '配置文件') { throw 'Chinese plan is missing.' }
& "$Root/envpilot.ps1" apply -Yes -NonInteractive
$first = [IO.File]::ReadAllText($env:ENVPILOT_PROFILE)
if (-not $first.StartsWith($original)) { throw 'Original profile was changed.' }
& "$Root/envpilot.ps1" apply -Yes -NonInteractive
if ([IO.File]::ReadAllText($env:ENVPILOT_PROFILE) -ne $first) { throw 'Repeated apply changed the profile.' }
. $env:ENVPILOT_PROFILE
if ((Existing-CustomFunction) -ne 'original') { throw 'Original command was lost.' }
$configFile = Join-Path $env:ENVPILOT_CONFIG_DIR 'config.yaml'
$updatedYaml = [IO.File]::ReadAllText($configFile).Replace('proxy_port: 42290','proxy_port: 43000')
[IO.File]::WriteAllText($configFile,$updatedYaml)
$effective = & "$Root/envpilot.ps1" config show | ConvertFrom-Json
if ($effective.config.mihomo.proxy_port -ne 43000) { throw 'Generated environment masked an edited YAML value.' }
& "$Root/envpilot.ps1" shell remove
if ([IO.File]::ReadAllText($env:ENVPILOT_PROFILE) -ne $original) { throw 'Shell removal changed user content.' }
Write-Output '[TEST] configuration and shell integration passed'
