# PowerShell profile managed by envpilot.
$EnvpilotConfigDir = Join-Path $HOME ".config/envpilot"
$EnvpilotSecrets = Join-Path $HOME ".config/secrets/api.env.ps1"

function Add-PathFront {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $parts = [System.Collections.Generic.List[string]]::new()
        $env:PATH -split [System.IO.Path]::PathSeparator | Where-Object { $_ } | ForEach-Object { [void]$parts.Add($_) }
        if ($parts -notcontains $Path) {
            $env:PATH = $Path + [System.IO.Path]::PathSeparator + $env:PATH
        }
    }
}

Add-PathFront (Join-Path $HOME ".local/bin")
Add-PathFront (Join-Path $HOME "bin")
Add-PathFront (Join-Path $HOME "software/bin")

function Use-EnvpilotSecrets {
    param([string]$Path = $EnvpilotSecrets)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Secret file not found: $Path"
    }
    . $Path
}

function Enable-EnvpilotProxy {
    param([string]$HostName = "127.0.0.1", [int]$Port = 7890)
    $proxy = "http://${HostName}:${Port}"
    $env:http_proxy = $proxy
    $env:https_proxy = $proxy
    $env:HTTP_PROXY = $proxy
    $env:HTTPS_PROXY = $proxy
    $env:all_proxy = "socks5://${HostName}:${Port}"
    $env:ALL_PROXY = $env:all_proxy
    $env:no_proxy = "localhost,127.0.0.1,::1"
    $env:NO_PROXY = $env:no_proxy
}

function Disable-EnvpilotProxy {
    "http_proxy","https_proxy","HTTP_PROXY","HTTPS_PROXY","all_proxy","ALL_PROXY","no_proxy","NO_PROXY" | ForEach-Object {
        Remove-Item "Env:\$_" -ErrorAction SilentlyContinue
    }
}

$localProfile = Join-Path $EnvpilotConfigDir "profile.local.ps1"
if (Test-Path -LiteralPath $localProfile) {
    . $localProfile
}

