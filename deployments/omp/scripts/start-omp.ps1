# start-omp.ps1 — Launch oh-my-pi in Docker interactively from Windows.
#
# Usage:
#   .\scripts\start-omp.ps1                        # open interactive TUI
#   .\scripts\start-omp.ps1 -p "explain this code" # non-interactive one-shot
#   .\scripts\start-omp.ps1 --help                 # omp CLI help
#
# Set $env:WORKSPACE_DIR to mount a different project directory:
#   $env:WORKSPACE_DIR = "C:\path\to\myproject"
#   .\scripts\start-omp.ps1
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$OmpArgs
)

$ErrorActionPreference = 'Stop'

$DeployDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $DeployDir

try {
    # Ensure Ollama container is running
    $ollamaStatus = docker compose ps ollama 2>&1
    if ($ollamaStatus -notmatch 'running') {
        Write-Error "Ollama is not running. Start it with: docker compose up -d ollama"
        exit 1
    }

    $workspaceArg = @()
    if ($env:WORKSPACE_DIR) {
        $workspaceArg = @('-e', "WORKSPACE_DIR=$env:WORKSPACE_DIR")
    }

    # Run omp interactively — forward all remaining args
    docker compose run --rm --profile interactive @workspaceArg omp @OmpArgs
}
finally {
    Pop-Location
}
