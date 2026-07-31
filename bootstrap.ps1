[CmdletBinding()]
param([string]$TargetDirectory = "envpilot")

$ErrorActionPreference = "Stop"
$RepoUrl = if ($env:ENVPILOT_REPO_URL) { $env:ENVPILOT_REPO_URL } else { "https://github.com/zhangyehao/envpilot.git" }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is required." }
if (Test-Path -LiteralPath $TargetDirectory) { throw "Target already exists: $TargetDirectory" }

$arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
    "X64" { "amd64" }
    "Arm64" { "arm64" }
    default { "unknown" }
}
$assetPattern = if ($arch -eq "amd64") { "/downloads/mihomo-windows-amd64-compatible-*.zip" } else { "" }

$versionText = (git --version).Trim()
$versionMatch = [regex]::Match($versionText, '(\d+)\.(\d+)')
$sparseAvailable = $versionMatch.Success -and (([int]$versionMatch.Groups[1].Value -gt 2) -or (([int]$versionMatch.Groups[1].Value -eq 2) -and ([int]$versionMatch.Groups[2].Value -ge 25)))
if ($sparseAvailable) {
    Write-Host "[INFO] detected platform: windows/$arch"
    Write-Host "[INFO] cloning scripts and only the matching bundled Mihomo cache."
    git clone --filter=blob:none --no-checkout $RepoUrl $TargetDirectory
    if ($LASTEXITCODE -ne 0) { throw "git clone failed." }
    git -C $TargetDirectory sparse-checkout init --no-cone
    if ($LASTEXITCODE -ne 0) { throw "git sparse-checkout is unavailable." }
    $sparseRelative = (git -C $TargetDirectory rev-parse --git-path info/sparse-checkout).Trim()
    $sparsePath = Join-Path $TargetDirectory $sparseRelative
    $patterns = @(
        "/*",
        "!/downloads/*",
        "/downloads/.gitkeep",
        "/downloads/country.mmdb",
        "/downloads/geoip.metadb"
    )
    if ($assetPattern) { $patterns += $assetPattern }
    [System.IO.File]::WriteAllLines($sparsePath, $patterns, [System.Text.UTF8Encoding]::new($false))
    git -C $TargetDirectory checkout main
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed." }
} else {
    Write-Warning "This Git version lacks partial clone support; using a normal HTTPS clone."
    git clone $RepoUrl $TargetDirectory
    if ($LASTEXITCODE -ne 0) { throw "git clone failed." }
}

Write-Host "[OK] envpilot is ready: $TargetDirectory"
Write-Host "[INFO] next: cd $TargetDirectory; .\envpilot.ps1 doctor"