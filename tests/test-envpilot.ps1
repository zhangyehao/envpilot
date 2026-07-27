$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("envpilot-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempHome | Out-Null
$env:ENVPILOT_CONFIG_DIR = Join-Path $TempHome ".config/envpilot"

Write-Host "[TEST] PowerShell parser"
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath (Join-Path $Root "envpilot.ps1") -Raw), [ref]$null)

Write-Host "[TEST] doctor"
& (Join-Path $Root "envpilot.ps1") doctor | Out-String | Select-String "OS:"

Write-Host "[TEST] profile template"
$template = Join-Path $Root "templates/Microsoft.PowerShell_profile.ps1"
if (-not (Test-Path -LiteralPath $template)) {
    throw "PowerShell profile template missing"
}
if (-not ((Get-Content -LiteralPath $template -Raw) -match "Use-EnvpilotSecrets")) {
    throw "PowerShell profile template does not define Use-EnvpilotSecrets"
}

Write-Host "[TEST] ok"


