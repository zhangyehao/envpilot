$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('envpilot-cli-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($name in @('ENVPILOT_CONFIG_DIR','ENVPILOT_CORE','ENVPILOT_MODE','ENVPILOT_LANG')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
    $copy = Join-Path $fixture 'repo'
    New-Item -ItemType Directory -Force -Path (Join-Path $copy 'lib'), (Join-Path $fixture 'config') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'envpilot.ps1'),(Join-Path $root 'VERSION') -Destination $copy
    Copy-Item -LiteralPath (Join-Path $root 'lib/config.ps1') -Destination (Join-Path $copy 'lib')
    $env:ENVPILOT_CONFIG_DIR = Join-Path $fixture 'config'
    $env:ENVPILOT_CORE = Join-Path $fixture 'missing-core.exe'
    $env:ENVPILOT_MODE = 'offline'
    $env:ENVPILOT_LANG = 'en'
    [IO.File]::WriteAllText((Join-Path $env:ENVPILOT_CONFIG_DIR 'config.yaml'), "invalid: [`n")
    $version = (Get-Content -LiteralPath (Join-Path $copy 'VERSION') -Raw).Trim()
    $powershell = (Get-Process -Id $PID).Path
    foreach ($option in @('version','-v','-V','-version','--version')) {
        $output = & $powershell -NoProfile -File (Join-Path $copy 'envpilot.ps1') $option
        if ($LASTEXITCODE -ne 0 -or ($output | Out-String).Trim() -ne "envpilot $version") { throw "Version alias failed: $option" }
    }
    foreach ($option in @('help','-h','-H','-help','--help')) {
        $output = & $powershell -NoProfile -File (Join-Path $copy 'envpilot.ps1') $option
        if ($LASTEXITCODE -ne 0 -or ($output | Out-String) -notmatch 'envpilot version') { throw "Help alias failed: $option" }
    }
    if (@(Get-ChildItem -LiteralPath $env:ENVPILOT_CONFIG_DIR -Recurse -File).Count -ne 1) { throw 'Help/version wrote configuration state.' }
    Write-Output '[TEST] help/version work offline without a helper, valid YAML or setup side effects'
} finally {
    foreach ($entry in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value) }
    $resolved = [IO.Path]::GetFullPath($fixture)
    $temporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($temporary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
