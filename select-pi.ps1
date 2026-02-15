# select-pi.ps1
# Select a Pi from the inventory and set environment variables for the current session
# Usage: . .\select-pi.ps1  (dot-source to persist environment variables)

$ErrorActionPreference = "Stop"

# Locate pi-list.json relative to this script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$piListPath = Join-Path $scriptDir "pi-list.json"

if (-not (Test-Path $piListPath)) {
    Write-Host "Error: pi-list.json not found at $piListPath" -ForegroundColor Red
    return
}

# Load the Pi list
try {
    $piList = Get-Content $piListPath -Raw | ConvertFrom-Json
} catch {
    Write-Host "Error: Failed to parse pi-list.json: $_" -ForegroundColor Red
    return
}

if ($piList.Count -eq 0) {
    Write-Host "Error: pi-list.json is empty" -ForegroundColor Red
    return
}

# Display menu
Write-Host "`nAvailable Pis:" -ForegroundColor Cyan
for ($i = 0; $i -lt $piList.Count; $i++) {
    $pi = $piList[$i]
    Write-Host "  [$($i + 1)] $($pi.name) ($($pi.user)@$($pi.host))"
}

# Prompt for selection
Write-Host ""
$selection = Read-Host "Enter number"
$index = [int]$selection - 1

if ($index -lt 0 -or $index -ge $piList.Count) {
    Write-Host "Error: Invalid selection" -ForegroundColor Red
    return
}

$selectedPi = $piList[$index]

# Set environment variables
$env:PI_HOST = $selectedPi.host
$env:PI_USER = $selectedPi.user

# Default REPO_DIR if not specified (null or empty)
if ([string]::IsNullOrWhiteSpace($selectedPi.repo_dir)) {
    # Auto-detect current repo name from git or directory name
    $repoName = $null
    try {
        $gitTopLevel = git rev-parse --show-toplevel 2>$null
        if ($gitTopLevel) {
            $repoName = Split-Path -Leaf $gitTopLevel
        }
    } catch {
        # Fallback to current directory name
        $repoName = Split-Path -Leaf (Get-Location)
    }
    $env:REPO_DIR = "/home/$($env:PI_USER)/$repoName"
} else {
    $env:REPO_DIR = $selectedPi.repo_dir
}

Write-Host "`nSelected: $($selectedPi.name)" -ForegroundColor Green
Write-Host "  PI_HOST=$env:PI_HOST"
Write-Host "  PI_USER=$env:PI_USER"
Write-Host "  REPO_DIR=$env:REPO_DIR"
Write-Host "`nEnvironment variables set for current session." -ForegroundColor Green
