# Downloads the pinned Windows x64 Node runtime into .\server\node.exe so the VSIX is fully
# self-contained -- the VS2022 extension launches `server\node.exe server.js` and needs NO Node on the
# user's PATH. Run this after the server bundle has been copied into .\server and before building /
# packaging the VSIX. CI (the publish workflow) runs it too. Idempotent: skips if node.exe is present.
#
#   powershell -ExecutionPolicy Bypass -File fetch-node.ps1            # default pinned version
#   powershell -ExecutionPolicy Bypass -File fetch-node.ps1 -NodeVersion 20.18.0
param([string]$NodeVersion = "20.18.0")
$ErrorActionPreference = "Stop"

$serverDir = Join-Path $PSScriptRoot "server"
New-Item -ItemType Directory -Force -Path $serverDir | Out-Null
$dest = Join-Path $serverDir "node.exe"

if (Test-Path $dest) {
    Write-Host "node.exe already present at $dest -- skipping download."
    exit 0
}

$url = "https://nodejs.org/dist/v$NodeVersion/win-x64/node.exe"
Write-Host "Downloading Node $NodeVersion (win-x64) from $url ..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
$sizeMb = [math]::Round((Get-Item $dest).Length / 1MB, 1)
Write-Host "Bundled node.exe -> $dest ($sizeMb MB)"
