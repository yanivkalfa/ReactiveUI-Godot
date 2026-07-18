<#
.SYNOPSIS
    Build, package, and publish the GUITKX VS Code extension (VS Marketplace + Open VSX).

.DESCRIPTION
    Local publish pipeline, mirroring the publish-extensions.yml workflow:
      1. (Optional) bump the patch version in the extension's package.json
      2. Add a changelog entry to ide-extensions/changelog.json + regenerate CHANGELOG.md
      3. Build the TypeScript language server + bundle it into ./server
      4. npm run build  (the extension)
      5. vsce package   -> guitkx.vsix
      6. local install via the VS Code CLI
      7. vsce publish   (VS Marketplace)  +  ovsx publish (Open VSX)   [skipped with -LocalOnly]

    Tokens resolve from parameters, then env (VSCE_PAT / OVSX_TOKEN), then
    publisher-secrets.json at the repo root ({ vscePatToken, ovsxToken }).

.PARAMETER PAT          VS Marketplace PAT (Marketplace > Manage). Falls back to $env:VSCE_PAT / secrets file.
.PARAMETER OvsxToken    Open VSX token. Falls back to $env:OVSX_TOKEN / secrets file.
.PARAMETER ChangelogEntry  One-line shared changelog summary (prompted if omitted).
.PARAMETER LocalOnly    Package + local-install only; do not publish to any marketplace.
.PARAMETER SkipOpenVsx  Publish to VS Marketplace only (skip Open VSX).
.PARAMETER SkipBuild    Skip the npm build steps.
.PARAMETER SkipServerBuild  Skip building + bundling the language server.
.PARAMETER BumpVersion  Increment the patch version before building.

.EXAMPLE  .\ide-extensions\scripts\publish-extension.ps1 -BumpVersion -ChangelogEntry "Add formatter"
.EXAMPLE  .\ide-extensions\scripts\publish-extension.ps1 -LocalOnly
#>
[CmdletBinding()]
param(
    [string] $PAT            = '',
    [string] $OvsxToken      = '',
    [string] $ChangelogEntry = '',
    [switch] $LocalOnly,
    [switch] $SkipOpenVsx,
    [switch] $SkipBuild,
    [switch] $SkipServerBuild,
    [switch] $BumpVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── paths ─────────────────────────────────────────────────────────────────────
$scriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$ideRoot       = Split-Path -Parent $scriptDir            # ide-extensions/
$repoRoot      = Split-Path -Parent $ideRoot
$extensionDir  = Join-Path $ideRoot 'vscode'
$serverSrcDir  = Join-Path $ideRoot 'lsp-server'
$pkgJsonPath   = Join-Path $extensionDir 'package.json'
$changelogTool = Join-Path $scriptDir 'changelog.mjs'
$secretsPath   = Join-Path $repoRoot 'publisher-secrets.json'

if (-not (Test-Path $extensionDir)) { Write-Error "Extension directory not found: $extensionDir"; exit 1 }

# ── helpers ───────────────────────────────────────────────────────────────────
function Write-Step([string] $msg) { Write-Host ''; Write-Host "-- $msg" -ForegroundColor Cyan }
function Get-PkgVersion([string] $path) { return (Get-Content $path -Raw | ConvertFrom-Json).version }

function Set-PkgPatchBump([string] $path) {
    $text    = Get-Content $path -Raw
    $current = ($text | ConvertFrom-Json).version
    $parts   = $current -split '\.'
    $next    = "$($parts[0]).$($parts[1]).$([int]$parts[2] + 1)"
    $text    = $text -replace '"version"\s*:\s*"[^"]+"', "`"version`": `"$next`""
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
    return $next
}

function Resolve-Secret([string] $explicit, [string] $envName, [string] $jsonKey) {
    if (-not [string]::IsNullOrWhiteSpace($explicit)) { return $explicit }
    $envVal = [Environment]::GetEnvironmentVariable($envName)
    if (-not [string]::IsNullOrWhiteSpace($envVal)) { return $envVal }
    if (Test-Path $secretsPath) {
        try {
            $val = (Get-Content $secretsPath -Raw | ConvertFrom-Json).$jsonKey
            if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
        } catch { }
    }
    return ''
}

function Invoke-InDir([string] $cwd, [string] $cmd) {
    Write-Host "   > $cmd" -ForegroundColor DarkGray
    $prev = $PWD; Set-Location $cwd
    try { cmd.exe /c $cmd; if ($LASTEXITCODE -ne 0) { throw "command exited $LASTEXITCODE" } }
    finally { Set-Location $prev }
}

# ── version bump ──────────────────────────────────────────────────────────────
$publishVersion = Get-PkgVersion $pkgJsonPath
if ($BumpVersion) {
    Write-Step 'Bumping patch version'
    $publishVersion = Set-PkgPatchBump $pkgJsonPath
    Write-Host "  -> v$publishVersion" -ForegroundColor Green
}

# ── changelog (centralized) ───────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($ChangelogEntry)) {
    Write-Host ''
    $ChangelogEntry = Read-Host 'Enter a changelog summary for this version'
    if ([string]::IsNullOrWhiteSpace($ChangelogEntry)) { $ChangelogEntry = 'Minor improvements and bug fixes.' }
}
Write-Step "Recording changelog entry for v$publishVersion"
# Use --message-file so non-ASCII content survives PowerShell's CP1252 argv transcoding.
$msgFile = Join-Path $env:TEMP "guitkx-changelog-msg.txt"
[System.IO.File]::WriteAllText($msgFile, $ChangelogEntry, (New-Object System.Text.UTF8Encoding $false))
& node $changelogTool add --scope shared --message-file $msgFile --vscode $publishVersion
& node $changelogTool extract --ide vscode --out (Join-Path $extensionDir 'CHANGELOG.md')
Remove-Item $msgFile -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '======================================================' -ForegroundColor Yellow
Write-Host "  GUITKX VS Code Extension   v$publishVersion"          -ForegroundColor Yellow
Write-Host "  LocalOnly=$LocalOnly  SkipOpenVsx=$SkipOpenVsx"        -ForegroundColor Yellow
Write-Host '======================================================' -ForegroundColor Yellow

# ── 1. language server build + bundle ─────────────────────────────────────────
if (-not $SkipServerBuild) {
    Write-Step 'Building + bundling the language server'
    Invoke-InDir $serverSrcDir 'npm install'
    Invoke-InDir $serverSrcDir 'npm run build'
    Invoke-InDir $extensionDir 'node scripts/bundle-server.js'
    Write-Host '  Server bundled into ./server.' -ForegroundColor Green
}

# ── 2. extension build ────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Step 'Building extension (npm run build)'
    Invoke-InDir $extensionDir 'npm install'
    Invoke-InDir $extensionDir 'npm run build'
}

# ── 3. package ────────────────────────────────────────────────────────────────
Write-Step 'Packaging extension (vsce package)'
Invoke-InDir $extensionDir 'npx --yes @vscode/vsce package --no-dependencies -o guitkx.vsix'
$vsixPath = Join-Path $extensionDir 'guitkx.vsix'
if (-not (Test-Path $vsixPath)) { Write-Error 'VSIX not found.'; exit 1 }
Write-Host "  Packaged: $vsixPath" -ForegroundColor Green

# ── 4. local install ──────────────────────────────────────────────────────────
Write-Step 'Installing locally via the VS Code CLI'
$codeCli = @(
    "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd", 'code.cmd', 'code'
) | Where-Object { (Get-Command $_ -ErrorAction SilentlyContinue) -or (Test-Path $_) } | Select-Object -First 1
if ($codeCli) {
    & cmd.exe /c "`"$codeCli`" --install-extension `"$vsixPath`" --force" | ForEach-Object { Write-Host "  $_" }
    Write-Host '  Reload the VS Code window to activate.' -ForegroundColor DarkGray
} else {
    Write-Host '  VS Code CLI not found — install the .vsix manually.' -ForegroundColor Yellow
}

# ── 5. publish ────────────────────────────────────────────────────────────────
if ($LocalOnly) {
    Write-Host '  Marketplace publish skipped (-LocalOnly).' -ForegroundColor DarkGray
} else {
    $vscePat = Resolve-Secret $PAT 'VSCE_PAT' 'vscePatToken'
    if ([string]::IsNullOrWhiteSpace($vscePat)) {
        Write-Error 'No VS Marketplace PAT. Use -PAT, $env:VSCE_PAT, or publisher-secrets.json { vscePatToken }.'; exit 1
    }
    Write-Step 'Publishing to VS Marketplace'
    Invoke-InDir $extensionDir "npx --yes @vscode/vsce publish --no-dependencies --packagePath guitkx.vsix --pat $vscePat"
    Write-Host "  Published v$publishVersion to VS Marketplace." -ForegroundColor Green

    if (-not $SkipOpenVsx) {
        $ovsx = Resolve-Secret $OvsxToken 'OVSX_TOKEN' 'ovsxToken'
        if ([string]::IsNullOrWhiteSpace($ovsx)) {
            Write-Host '  Open VSX token not found — skipping Open VSX (use -OvsxToken / $env:OVSX_TOKEN).' -ForegroundColor Yellow
        } else {
            Write-Step 'Publishing to Open VSX'
            Invoke-InDir $extensionDir "npx --yes ovsx publish guitkx.vsix -p $ovsx"
            Write-Host "  Published v$publishVersion to Open VSX." -ForegroundColor Green
        }
    }
}

Write-Host ''
Write-Host "======  Done  v$publishVersion  ======" -ForegroundColor Green
