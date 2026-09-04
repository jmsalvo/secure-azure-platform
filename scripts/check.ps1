<#
.SYNOPSIS
    Runs the credential-free CI checks locally on Windows, no bash required.

.DESCRIPTION
    Mirrors the credential-free jobs in .github/workflows/ci.yml: terraform
    fmt, terraform validate (bootstrap + every stack, backend disabled), tflint,
    and the trivy config scan. Run it before pushing a branch. Does not run
    terraform plan/apply — those need Azure OIDC credentials CI provides.

    Every tool is a native Windows binary (install with:
      scoop install terraform tflint trivy
    ).

.PARAMETER Fix
    Auto-fix formatting with `terraform fmt` instead of only checking.

.EXAMPLE
    .\scripts\check.ps1

.EXAMPLE
    .\scripts\check.ps1 -Fix
#>
[CmdletBinding()]
param(
    [switch]$Fix
)

$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    $failures = New-Object System.Collections.Generic.List[string]

    function Test-Tool {
        param([string]$Name)
        return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
    }

    function Invoke-Step {
        param(
            [string]$Name,
            [scriptblock]$Body
        )
        Write-Host ''
        Write-Host "==> $Name" -ForegroundColor Cyan
        & $Body
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    FAILED: $Name" -ForegroundColor Red
            $failures.Add($Name)
        }
        else {
            Write-Host '    ok' -ForegroundColor Green
        }
    }

    # --- tool presence ---------------------------------------------------------
    $missing = @('terraform', 'tflint', 'trivy') | Where-Object { -not (Test-Tool $_) }
    if ($missing) {
        Write-Host "Missing tools: $($missing -join ', ')" -ForegroundColor Red
        Write-Host "Install with: scoop install $($missing -join ' ')" -ForegroundColor Yellow
        exit 1
    }

    # --- directories ---------------------------------------------------------
    $tfDirs = @('bootstrap') + (Get-ChildItem -Path 'environments' -Recurse -Filter '*.tf' -File |
        Where-Object { $_.FullName -notmatch '\\\.terraform\\' } |
        ForEach-Object { $_.DirectoryName } |
        Select-Object -Unique) | Sort-Object -Unique

    # --- fmt ---------------------------------------------------------
    if ($Fix) {
        Invoke-Step 'terraform fmt (rewrite)' { terraform fmt -recursive | Out-Host }
    }
    else {
        Invoke-Step 'terraform fmt -check' { terraform fmt -check -recursive -diff | Out-Host }
    }

    # --- validate ---------------------------------------------------------
    foreach ($dir in $tfDirs) {
        $rel = Resolve-Path -Relative $dir
        Invoke-Step "terraform validate $rel" {
            terraform "-chdir=$dir" init -backend=false -input=false -no-color | Out-Host
            if ($LASTEXITCODE -eq 0) {
                terraform "-chdir=$dir" validate -no-color | Out-Host
            }
        }
    }

    # --- tflint ---------------------------------------------------------
    Invoke-Step 'tflint --init' { tflint --init | Out-Host }
    Invoke-Step 'tflint --recursive' { tflint --recursive --no-color | Out-Host }

    # --- trivy ---------------------------------------------------------
    Invoke-Step 'trivy config' { trivy config --config trivy.yaml . | Out-Host }

    # --- summary ---------------------------------------------------------
    Write-Host ''
    if ($failures.Count -gt 0) {
        Write-Host "FAILED ($($failures.Count)):" -ForegroundColor Red
        $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host 'All checks passed.' -ForegroundColor Green
    exit 0
}
finally {
    Pop-Location
}
