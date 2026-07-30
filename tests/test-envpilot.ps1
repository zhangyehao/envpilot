$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("envpilot-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempHome | Out-Null
$env:ENVPILOT_CONFIG_DIR = Join-Path $TempHome ".config/envpilot"

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

try {
    Write-Host "[TEST] PowerShell parser"
    $parseTargets = @((Join-Path $Root "envpilot.ps1"), (Join-Path $Root "templates/Microsoft.PowerShell_profile.ps1"))
    $parseTargets += Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -Filter "*.ps1" | Select-Object -ExpandProperty FullName
    foreach ($target in $parseTargets) {
        $parseErrors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $target -Raw), [ref]$parseErrors)
        if ($parseErrors) { throw $parseErrors }
    }

    Write-Host "[TEST] doctor captures baseline"
    $doctorOutput = (& (Join-Path $Root "envpilot.ps1") doctor 6>&1 | Out-String)
    Assert-Match $doctorOutput "OS:" "doctor output did not include OS"
    $baseline = Join-Path $env:ENVPILOT_CONFIG_DIR "baseline/baseline.tsv"
    if (-not (Test-Path -LiteralPath $baseline)) { throw "baseline file was not created" }
    $baselineText = Get-Content -LiteralPath $baseline -Raw
    Assert-Match $baselineText "powershell-profile" "baseline missing PowerShell profile entry"
    Assert-Match $baselineText "mihomo-bin" "baseline missing mihomo binary entry"

    Write-Host "[TEST] mihomo status command"
    $mihomoStatus = (& (Join-Path $Root "envpilot.ps1") mihomo status 6>&1 | Out-String)
    Assert-Match $mihomoStatus "envpilot mihomo binary:" "mihomo status missing binary section"
    Assert-Match $mihomoStatus "proxy port:" "mihomo status missing proxy section"
    Assert-Match $mihomoStatus "127.0.0.1:" "mihomo status missing configured port"

    Write-Host "[TEST] profile template"
    $template = Join-Path $Root "templates/Microsoft.PowerShell_profile.ps1"
    $templateText = Get-Content -LiteralPath $template -Raw
    Assert-Match $templateText "Use-EnvpilotSecrets" "PowerShell profile template does not define Use-EnvpilotSecrets"
    Assert-Match $templateText "function mihomo" "PowerShell profile template does not define mihomo wrapper"
    Assert-Match $templateText "Stop-Mihomo" "PowerShell profile template does not define Stop-Mihomo"
    Assert-Match $templateText "Set-MihomoPort" "PowerShell profile template does not define Set-MihomoPort"

    Write-Host "[TEST] restore fixture"
    $restorePrefix = Join-Path $TempHome "software"
    $restoreConfig = Join-Path $TempHome ".config/envpilot-restore"
    $env:ENVPILOT_CONFIG_DIR = $restoreConfig
    $baselineDir = Join-Path $restoreConfig "baseline"
    $baselineFiles = Join-Path $baselineDir "files"
    New-Item -ItemType Directory -Force -Path $baselineFiles | Out-Null
    New-Item -ItemType Directory -Force -Path $restorePrefix | Out-Null

    $target = Join-Path $restorePrefix "restore.txt"
    $createdFile = Join-Path $restorePrefix "created.txt"
    $createdDir = Join-Path $restorePrefix "created-dir"
    Set-Content -LiteralPath $target -Value "before" -Encoding UTF8
    Copy-Item -LiteralPath $target -Destination (Join-Path $baselineFiles "restore.txt") -Force
    @(
        "# envpilot doctor baseline",
        "file`tfixture`t$target`t1`tfiles/restore.txt`t",
        "file`tcreated-file`t$createdFile`t0`t`t",
        "dir`tcreated-dir`t$createdDir`t0`t`t"
    ) | Set-Content -LiteralPath (Join-Path $baselineDir "baseline.tsv") -Encoding UTF8
    Set-Content -LiteralPath $target -Value "after" -Encoding UTF8
    Set-Content -LiteralPath $createdFile -Value "created" -Encoding UTF8
    New-Item -ItemType Directory -Force -Path $createdDir | Out-Null

    & (Join-Path $Root "envpilot.ps1") restore -Prefix $restorePrefix | Out-String | Select-String "Baseline restore complete"
    if ((Get-Content -LiteralPath $target -Raw) -notmatch "before") { throw "restore did not restore fixture file" }
    if (Test-Path -LiteralPath $createdFile) { throw "restore did not remove created file" }
    if (Test-Path -LiteralPath $createdDir) { throw "restore did not remove created directory" }

    Write-Host "[TEST] ok"
} finally {
    Remove-Item -LiteralPath $TempHome -Recurse -Force -ErrorAction SilentlyContinue
}