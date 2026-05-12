# setup.ps1 — One-time setup for the local-cpu deployment on Windows.
# Run from the deployments/local-cpu directory in PowerShell.
#
# Requires: Docker Desktop for Windows (WSL2 backend recommended)
param()

$ErrorActionPreference = 'Stop'

$DeployDir = Split-Path -Parent $PSScriptRoot
Push-Location $DeployDir

function Log  { param($msg) Write-Host "[setup] $msg" -ForegroundColor Green }
function Warn { param($msg) Write-Host "[setup] $msg" -ForegroundColor Yellow }
function Die  { param($msg) Write-Error "[setup] ERROR: $msg"; exit 1 }

try {
    # ── Prerequisites ─────────────────────────────────────────────────────────
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Die "Docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    }
    docker compose version | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "Docker Compose v2 not found. Update Docker Desktop." }
    Log "Docker OK"

    # ── Memory check ──────────────────────────────────────────────────────────
    $totalRamGB = [math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB)
    Log "Host RAM: ${totalRamGB} GB"
    if ($totalRamGB -lt 28) {
        Warn "Less than 28 GB RAM detected. gemma4:26b Q4 requires ~20-22 GB for the model + KV cache."
        Warn "Performance may be severely limited."
    }

    # ── WSL2 memory config reminder ────────────────────────────────────────────
    $wslConfig = "$env:USERPROFILE\.wslconfig"
    if (-not (Test-Path $wslConfig)) {
        Warn ".wslconfig not found. Docker Desktop (WSL2) may cap RAM at 50% of host."
        Warn "To allow more RAM, create $wslConfig with:"
        Warn "  [wsl2]"
        Warn "  memory=28GB"
        Warn "Then restart WSL: wsl --shutdown"
    }

    # ── Create workspace ──────────────────────────────────────────────────────
    if (-not (Test-Path "workspace")) { New-Item -ItemType Directory -Path "workspace" | Out-Null }
    Log "Workspace directory ready at .\workspace"

    # ── Build omp image ───────────────────────────────────────────────────────
    Log "Building oh-my-pi image..."
    docker compose build omp
    if ($LASTEXITCODE -ne 0) { Die "Image build failed." }

    # ── Start Ollama ──────────────────────────────────────────────────────────
    Log "Starting Ollama (CPU-only)..."
    docker compose up -d ollama
    if ($LASTEXITCODE -ne 0) { Die "Failed to start Ollama." }

    Log "Waiting for Ollama health check..."
    $attempts = 0
    do {
        Start-Sleep -Seconds 3
        $result = docker compose exec ollama curl -sf http://localhost:11434/api/tags 2>&1
        $attempts++
        if ($attempts -gt 20) { Die "Ollama did not become healthy in time." }
    } while ($LASTEXITCODE -ne 0)
    Log "Ollama is ready."

    # ── Pull and register model ────────────────────────────────────────────────
    Log "Pulling gemma4:26b (~18 GB Q4 — this will take a while on first run)..."
    docker compose exec ollama ollama pull gemma4:26b
    if ($LASTEXITCODE -ne 0) { Die "Model pull failed." }

    Log "Registering gemma4-local from Modelfile..."
    docker compose exec ollama ollama create gemma4-local -f /tmp/Modelfile
    if ($LASTEXITCODE -ne 0) { Die "Model registration failed." }

    Log ""
    Log "Setup complete!"
    Log "Start oh-my-pi with:  .\scripts\start-omp.ps1"
}
finally {
    Pop-Location
}
