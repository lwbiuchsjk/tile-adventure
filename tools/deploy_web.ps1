# Function: Export current Godot project as Web build, deploy via SSH+SCP to self-hosted server.
# Reads deploy params from tools/local_env.json. Wraps: export -> clean remote -> scp -> print URL.
# Project-agnostic: all per-project values come from local_env.json's "deploy" section.
# Usage:
#   .\tools\deploy_web.ps1                       # Use default game_name from local_env.json
#   .\tools\deploy_web.ps1 -GameName some-game   # Override game name (multi-demo on same server)

[CmdletBinding()]
param(
    [string]$GameName
)

$ErrorActionPreference = "Stop"

# Load local_env.json
$localEnvPath = Join-Path $PSScriptRoot "local_env.json"
if (-not (Test-Path $localEnvPath)) {
    throw "local_env.json not found: $localEnvPath. Run /deploy-web in Claude Code to bootstrap interactively, or create the file manually with a 'deploy' section."
}
$localEnv = Get-Content $localEnvPath -Raw | ConvertFrom-Json

# Validate deploy section
if (-not $localEnv.deploy) {
    throw "Missing 'deploy' section in $localEnvPath. Run /deploy-web in Claude Code to bootstrap interactively."
}
$deploy = $localEnv.deploy
foreach ($field in @("ssh_target", "remote_root", "url_root", "game_name")) {
    if (-not $deploy.$field) {
        throw "Missing or empty: deploy.$field"
    }
}

# Optional fields with defaults
$exportPreset = if ($deploy.export_preset) { $deploy.export_preset } else { "Web" }

# Parameter override
if (-not $GameName) {
    $GameName = $deploy.game_name
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outputDir   = Join-Path $projectRoot "output"
$sshTarget   = $deploy.ssh_target
$remoteRoot  = $deploy.remote_root
$remotePath  = "$remoteRoot/$GameName"
$urlRoot     = $deploy.url_root.TrimEnd("/")
$finalUrl    = "$urlRoot/$GameName/"

Write-Host "===== Deploy Web =====" -ForegroundColor Cyan
Write-Host "Project: $projectRoot"
Write-Host "Game:    $GameName"
Write-Host "Preset:  $exportPreset"
Write-Host "Target:  ${sshTarget}:$remotePath"
Write-Host "URL:     $finalUrl"
Write-Host ""

# Step 1: Clean local output directory (avoid stale files getting scp'd)
Write-Host "[1/4] Clean local output\..." -ForegroundColor Cyan
if (Test-Path $outputDir) {
    Remove-Item -Recurse -Force "$outputDir\*" -ErrorAction SilentlyContinue
} else {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Step 2: Godot headless Web export (preset name from deploy.export_preset, default "Web")
Write-Host "[2/4] Godot export (preset: $exportPreset)..." -ForegroundColor Cyan
$runGodot = Join-Path $PSScriptRoot "run_godot.ps1"
$exportEntry = Join-Path $outputDir "index.html"
& $runGodot --headless --export-release $exportPreset $exportEntry
if ($LASTEXITCODE -ne 0) {
    throw "Godot export failed (exit code $LASTEXITCODE). Verify preset name '$exportPreset' exists in export_presets.cfg."
}
if (-not (Test-Path $exportEntry)) {
    throw "Export did not produce index.html. Check export_presets.cfg or Godot templates."
}

# Step 3: Clean remote target dir (scoped to this game's dir; leave sibling games alone)
Write-Host "[3/4] Clean remote $remotePath ..." -ForegroundColor Cyan
ssh $sshTarget "mkdir -p $remotePath; rm -f $remotePath/*"
if ($LASTEXITCODE -ne 0) {
    throw "Remote clean (ssh) failed"
}

# Step 4: scp upload all output files
Write-Host "[4/4] scp upload..." -ForegroundColor Cyan
scp "$outputDir\*" "${sshTarget}:$remotePath/"
if ($LASTEXITCODE -ne 0) {
    throw "scp upload failed"
}

Write-Host ""
Write-Host "===== Deploy complete =====" -ForegroundColor Green
Write-Host "URL: $finalUrl" -ForegroundColor Green

# Optional CDN reminder: if deploy.cdn_url is configured, source server is updated but
# CDN edge nodes still hold the previous version (Cache-Control: immutable typically
# makes .pck cached for 7 days). User must manually purge CDN cache via console.
if ($deploy.cdn_url) {
    $cdnRoot = $deploy.cdn_url.TrimEnd("/")
    $cdnUrl  = "$cdnRoot/$GameName/"
    Write-Host ""
    Write-Host "===== CDN cache reminder =====" -ForegroundColor Yellow
    Write-Host "Source server updated, but CDN edge nodes still serve the previous version." -ForegroundColor Yellow
    Write-Host "(Cache-Control: immutable on .pck => effective TTL up to 7 days)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Manually purge CDN cache for:" -ForegroundColor Yellow
    Write-Host "  $cdnUrl" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Aliyun CDN console -> Refresh & Preheat -> URL/Directory Refresh." -ForegroundColor Yellow
    Write-Host "After propagation, hard-reload browser (Ctrl+Shift+R) to verify." -ForegroundColor Yellow
}
