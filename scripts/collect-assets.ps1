[CmdletBinding()]
param(
    [string[]]$Roots,
    [string]$Destination,
    [int]$MaxDepth = 5,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$UploadRelease,
    [string]$Tag = "offline-cache-manual",
    [string]$Repo = "zhangyehao/envpilot",
    [string]$GhPath = "C:\Program Files\GitHub CLI\gh.exe",
    [int]$MaxSizeMB = 700
)

$ErrorActionPreference = "Stop"

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$RepoRoot = Split-Path -Parent $ScriptRoot
if (-not $Destination) {
    $Destination = Join-Path $RepoRoot "downloads"
}

$defaultRoots = @(
    (Join-Path $HOME "Downloads"),
    (Join-Path $HOME "software"),
    "C:\tmp",
    "D:\software",
    "D:\downloads",
    "D:\codex",
    "E:\software",
    "E:\downloads",
    "E:\mihomo"
)

if (-not $Roots -or $Roots.Count -eq 0) {
    $Roots = $defaultRoots
}

$patterns = @(
    "Miniforge3-*.sh",
    "Miniforge3-*.pkg",
    "Miniforge3-*.exe",
    "Miniconda3-*.sh",
    "Miniconda3-*.exe",
    "Anaconda3-*.sh",
    "Anaconda3-*.exe",
    "mihomo-*.gz",
    "mihomo-*.zip",
    "gh_*_linux_*.tar.gz",
    "gh_*_macOS_*.zip",
    "gh_*_windows_*.zip",
    "GitHubCLI*.msi",
    "node-v*.tar.gz",
    "node-v*.tar.xz",
    "node-v*.pkg",
    "node-v*.msi"
)

function Test-StableAssetName {
    param([string]$Name)
    return ($Name -notmatch "(?i)(alpha|beta|rc|pre|nightly|snapshot)")
}

function Get-FilesBounded {
    param([string]$Root, [int]$Depth)
    if (-not (Test-Path -LiteralPath $Root)) {
        return
    }

    $queue = New-Object System.Collections.Queue
    $queue.Enqueue([pscustomobject]@{ Path = (Resolve-Path -LiteralPath $Root).Path; Depth = 0 })

    while ($queue.Count -gt 0) {
        $item = $queue.Dequeue()
        try {
            Get-ChildItem -LiteralPath $item.Path -Force -ErrorAction Stop | ForEach-Object {
                if ($_.PSIsContainer) {
                    if ($item.Depth -lt $Depth) {
                        $queue.Enqueue([pscustomobject]@{ Path = $_.FullName; Depth = $item.Depth + 1 })
                    }
                } else {
                    $_
                }
            }
        } catch {
            Write-Warning "Skip unreadable path: $($item.Path)"
        }
    }
}

function Test-MatchesAnyPattern {
    param([string]$Name)
    foreach ($pattern in $patterns) {
        if ($Name -like $pattern) {
            return $true
        }
    }
    return $false
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

$matches = New-Object System.Collections.Generic.List[object]
foreach ($root in $Roots) {
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Host "[INFO] Skip missing root: $root"
        continue
    }
    Write-Host "[INFO] Scan root: $root"
    Get-FilesBounded -Root $root -Depth $MaxDepth | ForEach-Object {
        if ((Test-MatchesAnyPattern $_.Name) -and (Test-StableAssetName $_.Name)) {
            if (($_.Length / 1MB) -gt $MaxSizeMB) {
                Write-Warning "Skip large asset > ${MaxSizeMB}MB: $($_.FullName)"
            } else {
                $matches.Add($_)
            }
        }
    }
}

if ($matches.Count -eq 0) {
    Write-Warning "No matching installer assets found."
    exit 0
}

$copied = New-Object System.Collections.Generic.List[object]
foreach ($file in ($matches | Sort-Object Name, LastWriteTime -Descending)) {
    $target = Join-Path $Destination $file.Name
    $record = [pscustomobject]@{
        name = $file.Name
        source = $file.FullName
        destination = $target
        length = $file.Length
        last_write_time = $file.LastWriteTime.ToString("s")
    }

    if ($DryRun) {
        Write-Host "[DRYRUN] $($file.FullName) -> $target"
        $copied.Add($record)
        continue
    }

    if ((Test-Path -LiteralPath $target) -and -not $Force) {
        Write-Host "[INFO] Exists, skip: $target"
    } else {
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force:$Force
        Write-Host "[INFO] Copied: $target"
    }
    $copied.Add($record)
}

$indexPath = Join-Path $Destination "assets-index.json"
if (-not $DryRun) {
    $copied | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $indexPath -Encoding UTF8
    Write-Host "[INFO] Wrote index: $indexPath"
}

if ($UploadRelease) {
    if ($Repo -eq "zhangyehao/envpilot" -and $Tag -match "^v\d+\.\d+\.\d+$") {
        throw "Do not upload third-party installers to normal envpilot version releases. Use a dedicated offline-cache tag or a separate cache repository."
    }
    if ($DryRun) {
        Write-Host "[DRYRUN] Would upload copied assets to $Repo release $Tag"
        exit 0
    }
    if (-not (Test-Path -LiteralPath $GhPath)) {
        $gh = Get-Command gh -ErrorAction SilentlyContinue
        if (-not $gh) {
            throw "GitHub CLI not found. Pass -GhPath or install gh."
        }
        $GhPath = $gh.Source
    }

    foreach ($record in $copied) {
        if (Test-Path -LiteralPath $record.destination) {
            & $GhPath release upload $Tag $record.destination --repo $Repo --clobber
        }
    }
}

