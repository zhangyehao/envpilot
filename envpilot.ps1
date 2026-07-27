[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet("doctor","install","apply-shell","rollback","resume","reset","update-manifests","self-test","help")]
    [string]$Command = "help",

    [Parameter(Position=1)]
    [string]$Component = "all",

    [ValidateSet("online","offline")]
    [string]$Mode = "online",

    [string]$Prefix = (Join-Path $HOME "software"),
    [string]$AssetPath,
    [switch]$Yes
)

$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:ConfigDir = if ($env:ENVPILOT_CONFIG_DIR) { $env:ENVPILOT_CONFIG_DIR } else { Join-Path $HOME ".config/envpilot" }
$Script:StateFile = Join-Path $Script:ConfigDir "state.ps1.txt"
$Script:RollbackLog = Join-Path $Script:ConfigDir "rollback.ps1.tsv"
$Script:ReportFile = Join-Path $Script:ConfigDir "install-report.json"
$Script:RunId = Get-Date -Format "yyyyMMddHHmmss"
$Script:Events = @()
$Script:Platform = $null

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" }
function Write-Warn { param([string]$Message) Write-Warning $Message }
function Stop-Envpilot { param([string]$Message) throw "[ERROR] $Message" }

function Initialize-Envpilot {
    New-Item -ItemType Directory -Force -Path $Script:ConfigDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Script:ConfigDir "logs") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $HOME ".local/bin") | Out-Null
}

function Test-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-EnvpilotPlatform {
    $arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
        "X64" { "amd64" }
        "Arm64" { "arm64" }
        default { $_.ToLowerInvariant() }
    }
    [pscustomobject]@{
        OS = "windows"
        Arch = $arch
        Shell = "powershell"
        IsRoot = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Prefix = $Prefix
    }
}

function Confirm-Step {
    param([string]$Prompt, [bool]$DefaultYes = $false)
    if ($Yes -and $DefaultYes) { return $true }
    $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $answer = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
        switch -Regex ($answer) {
            "^(y|yes)$" { return $true }
            "^(n|no)$" { return $false }
            default { Write-Host "Please answer yes or no." }
        }
    }
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $backup = "$Path.bak.$Script:RunId"
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    "$Path`t$backup" | Add-Content -LiteralPath $Script:RollbackLog
    Write-Info "Backed up $Path -> $backup"
}

function Add-ReportEvent {
    param([string]$Component, [string]$Status, [string]$Message, [string]$Version = "", [string]$Source = "", [string]$Path = "")
    $Script:Events += [pscustomobject]@{
        component = $Component
        status = $Status
        message = $Message
        version = $Version
        source = $Source
        path = $Path
        time = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
}

function Save-Report {
    param([string]$Action, [string]$RequestedComponent)
    $report = [pscustomobject]@{
        run_id = $Script:RunId
        action = $Action
        requested_component = $RequestedComponent
        mode = $Mode
        prefix = $Prefix
        platform = $Script:Platform
        events = $Script:Events
        finished_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Script:ReportFile -Encoding UTF8
}

function Mark-StateDone { param([string]$Name) "$Name=done:$(Get-Date -Format o)" | Add-Content -LiteralPath $Script:StateFile }
function Test-StateDone { param([string]$Name) (Test-Path $Script:StateFile) -and (Select-String -LiteralPath $Script:StateFile -Pattern "^$Name=done:" -Quiet) }

function Invoke-EnvpilotDownload {
    param([string]$Url, [string]$Destination)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Find-OfflineAsset {
    param([string]$Pattern)
    if ($AssetPath) {
        if (-not (Test-Path -LiteralPath $AssetPath)) { Stop-Envpilot "--asset-path does not exist: $AssetPath" }
        return $AssetPath
    }
    $downloads = Join-Path $Script:Root "downloads"
    $asset = Get-ChildItem -LiteralPath $downloads -File -Filter $Pattern -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $asset) { Stop-Envpilot "Offline asset not found in downloads/: $Pattern" }
    return $asset.FullName
}

function Resolve-GitHubAsset {
    param([string]$Owner, [string]$Repo, [string]$AssetRegex)
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases"
    $asset = $releases |
        Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -notmatch "alpha|beta|rc|pre" } |
        ForEach-Object { $_.assets } |
        Where-Object { $_.name -match $AssetRegex -and $_.name -notmatch "alpha|beta|rc|pre" } |
        Select-Object -First 1
    if (-not $asset) { Stop-Envpilot "Could not resolve stable GitHub asset: $Owner/$Repo $AssetRegex" }
    return $asset.browser_download_url
}

function Show-Doctor {
    $Script:Platform = Get-EnvpilotPlatform
    Write-Info "OS: $($Script:Platform.OS)"
    Write-Info "Architecture: $($Script:Platform.Arch)"
    Write-Info "Administrator: $($Script:Platform.IsRoot)"
    Write-Info "Prefix: $Prefix"
    foreach ($cmd in "git","gh","ssh","conda","mamba","node","npm","codex","wsl") {
        if (Test-Command $cmd) {
            Write-Info "${cmd}: $(Get-Command $cmd | Select-Object -ExpandProperty Source)"
        } else {
            Write-Warn "${cmd}: not found"
        }
    }
}

function Install-Conda {
    if (Test-Command conda) {
        Add-ReportEvent "conda" "skipped" "already installed" (& conda --version 2>$null) "" ((Get-Command conda).Source)
        Mark-StateDone "conda"
        return
    }
    if ($Script:Platform.Arch -ne "amd64") { Stop-Envpilot "Windows Conda installer rule currently supports amd64 only." }
    $url = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
    $installer = Join-Path ([System.IO.Path]::GetTempPath()) "envpilot-miniconda.exe"
    $target = Join-Path $Prefix "miniconda3"
    Write-Info "Selected Miniconda installer for Windows amd64"
    Write-Info "Install target: $target"
    if (-not (Confirm-Step "Install Conda to $target?" $true)) { Add-ReportEvent "conda" "skipped" "user declined"; return }
    if ($Mode -eq "offline") {
        Copy-Item -LiteralPath (Find-OfflineAsset "Miniconda3-*.exe") -Destination $installer -Force
    } else {
        Invoke-EnvpilotDownload $url $installer
    }
    Start-Process -FilePath $installer -ArgumentList @("/InstallationType=JustMe","/RegisterPython=0","/S","/D=$target") -Wait
    Copy-Item -LiteralPath (Join-Path $Script:Root "templates/condarc") -Destination (Join-Path $HOME ".condarc") -Force
    Add-ReportEvent "conda" "installed" "installed Miniconda" "" $url $target
    Mark-StateDone "conda"
}

function Install-Mihomo {
    $regex = if ($Script:Platform.Arch -eq "amd64") { "mihomo-windows-amd64-compatible-.*\.zip$" } else { "mihomo-windows-arm64-.*\.zip$" }
    $installDir = Join-Path $HOME "software/mihomo"
    $bin = Join-Path $installDir "mihomo.exe"
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Write-Info "Selected mihomo asset rule: $regex"
    if (-not (Confirm-Step "Install mihomo to $bin?" $true)) { Add-ReportEvent "mihomo" "skipped" "user declined"; return }
    $archive = Join-Path ([System.IO.Path]::GetTempPath()) "envpilot-mihomo.zip"
    if ($Mode -eq "offline") {
        Copy-Item -LiteralPath (Find-OfflineAsset "mihomo-windows-*.zip") -Destination $archive -Force
        $source = $archive
    } else {
        $source = Resolve-GitHubAsset "MetaCubeX" "mihomo" $regex
        Invoke-EnvpilotDownload $source $archive
    }
    $extract = Join-Path ([System.IO.Path]::GetTempPath()) "envpilot-mihomo"
    Remove-Item -Recurse -Force -LiteralPath $extract -ErrorAction SilentlyContinue
    Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force
    $exe = Get-ChildItem -LiteralPath $extract -Recurse -File -Filter "mihomo*.exe" | Select-Object -First 1
    if (-not $exe) { Stop-Envpilot "Could not find mihomo executable in archive." }
    Copy-Item -LiteralPath $exe.FullName -Destination $bin -Force
    Add-ReportEvent "mihomo" "installed" "installed mihomo binary; subscription config is user supplied" "" $source $bin
    Mark-StateDone "mihomo"
}

function Install-Codex {
    Write-Info "Codex config will use env_key=OPENAI_API_KEY and will not write auth.json."
    if (-not (Test-Command npm)) {
        if (Test-Command winget) {
            if (Confirm-Step "Install Node.js LTS with winget?" $true) {
                winget install --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
            }
        }
    }
    if (-not (Test-Command npm)) { Stop-Envpilot "npm is required for Codex. Install Node.js and rerun." }
    if (-not (Test-Command codex)) { npm install -g "@openai/codex" }
    $codexDir = Join-Path $HOME ".codex"
    New-Item -ItemType Directory -Force -Path $codexDir | Out-Null
    $config = Join-Path $codexDir "config.toml"
    Backup-File $config
    @'
model_provider = "codex"
model = "gpt-5.5"
review_model = "gpt-5.5"
model_reasoning_effort = "high"
disable_response_storage = true
network_access = "enabled"

[model_providers.codex]
name = "codex"
base_url = "https://yanhuoapi.com/v1"
wire_api = "responses"
env_key = "OPENAI_API_KEY"
'@ | Set-Content -LiteralPath $config -Encoding UTF8
    Add-ReportEvent "codex" "installed" "configured Codex with env_key" "" "npm:@openai/codex" (Get-Command codex -ErrorAction SilentlyContinue).Source
    Mark-StateDone "codex"
}

function Install-GitHubCli {
    if (-not (Test-Command gh)) {
        if (-not (Test-Command winget)) { Stop-Envpilot "GitHub CLI not found and winget is unavailable." }
        winget install --id GitHub.cli --silent --accept-package-agreements --accept-source-agreements
    }
    if (Test-Command gh) {
        try {
            gh auth status | Out-String | ForEach-Object { Write-Info $_.TrimEnd() }
        } catch {
            Write-Warn "Run: gh auth login -h github.com --git-protocol ssh"
        }
    }
    Add-ReportEvent "github" "installed" "GitHub CLI checked/installed; auth may require user action" "" "winget/GitHub.cli" (Get-Command gh -ErrorAction SilentlyContinue).Source
    Mark-StateDone "github"
}

function Install-Tmux {
    if (Test-Command tmux) {
        Add-ReportEvent "tmux" "skipped" "already available" "" "" (Get-Command tmux).Source
        Mark-StateDone "tmux"
        return
    }
    if (Test-Command wsl) {
        Write-Warn "Windows native tmux is not installed by envpilot. Use WSL: wsl bash envpilot.sh install tmux"
        Add-ReportEvent "tmux" "skipped" "use WSL/MSYS2 for tmux" "" "" ""
        Mark-StateDone "tmux"
        return
    }
    Write-Warn "tmux is a Unix terminal multiplexer; install WSL/MSYS2/Git Bash for tmux support."
    Add-ReportEvent "tmux" "skipped" "Windows native tmux unsupported" "" "" ""
}

function Install-One {
    param([string]$Name)
    switch ($Name) {
        "conda" { Install-Conda }
        "mamba" { Write-Warn "Install mamba from an initialized Conda shell: conda install -n base -y -c conda-forge mamba"; Add-ReportEvent "mamba" "skipped" "requires conda shell initialization" }
        "mihomo" { Install-Mihomo }
        "codex" { Install-Codex }
        "github" { Install-GitHubCli }
        "tmux" { Install-Tmux }
        default { Stop-Envpilot "Unknown component: $Name" }
    }
}

function Invoke-Install {
    $Script:Platform = Get-EnvpilotPlatform
    $names = if ($Component -eq "all") { @("conda","mamba","mihomo","codex","github","tmux") } else { @($Component) }
    foreach ($name in $names) {
        if (Test-StateDone $name) {
            Write-Info "Skip ${name}: already marked done. Use reset to clear state."
            Add-ReportEvent $name "skipped" "already marked done"
            continue
        }
        Install-One $name
    }
    Save-Report "install" $Component
    Write-Info "Install report: $Script:ReportFile"
}

function Apply-ShellProfile {
    $profilePath = $PROFILE.CurrentUserCurrentHost
    $template = Join-Path $Script:Root "templates/Microsoft.PowerShell_profile.ps1"
    Write-Info "PowerShell profile target: $profilePath"
    if (-not (Confirm-Step "Replace PowerShell profile with envpilot template?" $false)) {
        Write-Warn "PowerShell profile unchanged."
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $profilePath) | Out-Null
    Backup-File $profilePath
    Copy-Item -LiteralPath $template -Destination $profilePath -Force
    Write-Info "Applied PowerShell profile: $profilePath"
}

function Rollback-Latest {
    if (-not (Test-Path -LiteralPath $Script:RollbackLog)) { Stop-Envpilot "No rollback records found." }
    $line = Get-Content -LiteralPath $Script:RollbackLog | Select-Object -Last 1
    $parts = $line -split "`t", 2
    if ($parts.Count -ne 2 -or -not (Test-Path -LiteralPath $parts[1])) { Stop-Envpilot "Invalid rollback record." }
    Copy-Item -LiteralPath $parts[1] -Destination $parts[0] -Force
    Write-Info "Restored $($parts[0]) from $($parts[1])"
}

function Update-Manifests {
    $script = Join-Path $Script:Root "scripts/update-manifests.py"
    $python = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $python) { Stop-Envpilot "python3 or python is required to update manifests" }
    & $python.Source $script
    if ($LASTEXITCODE -ne 0) { Stop-Envpilot "Manifest update failed." }
}
function Show-Usage {
@"
envpilot - cross-platform user-space environment bootstrapper

Usage:
  .\envpilot.ps1 doctor
  .\envpilot.ps1 install [all|conda|mamba|mihomo|codex|github|tmux] [-Mode online|offline] [-Prefix PATH] [-AssetPath PATH] [-Yes]
  .\envpilot.ps1 apply-shell
  .\envpilot.ps1 rollback
  .\envpilot.ps1 resume
  .\envpilot.ps1 reset
  .\envpilot.ps1 update-manifests
"@
}

try {
    Initialize-Envpilot
    switch ($Command) {
        "doctor" { Show-Doctor }
        "install" { Invoke-Install }
        "apply-shell" { Apply-ShellProfile }
        "rollback" { Rollback-Latest }
        "resume" { if (Test-Path $Script:StateFile) { Get-Content $Script:StateFile }; $Component = "all"; Invoke-Install }
        "reset" { Remove-Item -LiteralPath $Script:StateFile -Force -ErrorAction SilentlyContinue; Write-Info "State reset." }
        "update-manifests" { Update-Manifests }
        "self-test" { & (Join-Path $Script:Root "tests/test-envpilot.ps1") }
        "help" { Show-Usage }
    }
} catch {
    Write-Error $_
    exit 1
}



