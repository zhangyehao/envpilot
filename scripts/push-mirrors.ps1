[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Branch = (git -C $Root branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not determine the current branch." }
if ($Branch -ne "main") { throw "Mirror publishing must run from main; current branch: $Branch" }

$status = git -C $Root status --porcelain
if ($LASTEXITCODE -ne 0) { throw "Could not inspect the working tree." }
if ($status) { throw "Working tree is not clean. Commit or remove local changes first." }

foreach ($remote in @("origin", "gitee")) {
    git -C $Root remote get-url $remote *> $null
    if ($LASTEXITCODE -ne 0) { throw "Missing git remote: $remote" }
}

Write-Host "[INFO] pushing main and tags to GitHub (origin)."
git -C $Root push origin main --follow-tags
if ($LASTEXITCODE -ne 0) { throw "GitHub push failed." }

Write-Host "[INFO] pushing main and tags to Gitee (gitee)."
git -C $Root push gitee main --follow-tags
if ($LASTEXITCODE -ne 0) { throw "Gitee push failed." }

Write-Host "[OK] GitHub and Gitee are synchronized."
