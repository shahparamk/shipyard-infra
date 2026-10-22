<#
.SYNOPSIS
  Turn the ShipYard dev environment (EKS + NAT) up or down through a reviewed PR.
.EXAMPLE
  .\scripts\dev-env.ps1 up
  .\scripts\dev-env.ps1 down
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("up", "down")]
    [string]$State
)

$ErrorActionPreference = "Stop"

function Invoke-Native {
    param([scriptblock]$Command, [string]$ErrorMessage)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw $ErrorMessage }
}

$repoRoot = (git rev-parse --show-toplevel).Trim()
Set-Location $repoRoot

$file   = Join-Path $repoRoot "envs/dev/main.tf"
$target = if ($State -eq "up") { "true" } else { "false" }

# 1. Safety: clean working tree, up-to-date main
if (git status --porcelain) {
    throw "You have uncommitted changes. Commit or stash them first."
}
Invoke-Native { git checkout main } "Could not switch to main"
Invoke-Native { git pull --ff-only } "Could not pull main"

# 2. Check current state
$content = [System.IO.File]::ReadAllText($file)
$pattern = '(cluster_enabled\s*=\s*)(true|false)'
$match   = [regex]::Match($content, $pattern)
if (-not $match.Success) { throw "Could not find 'cluster_enabled = true/false' in envs/dev/main.tf" }
if ($match.Groups[2].Value -eq $target) {
    Write-Host "Dev environment is already '$State' (cluster_enabled = $target). Nothing to do." -ForegroundColor Yellow
    exit 0
}

# 3. Before teardown: block if Kubernetes created AWS resources Terraform can't see
if ($State -eq "down") {
    $svcJson = kubectl get svc -A -o json 2>$null
    if ($LASTEXITCODE -eq 0 -and $svcJson) {
        $lbs  = ($svcJson | ConvertFrom-Json).items | Where-Object { $_.spec.type -eq "LoadBalancer" }
        $pvcs = (kubectl get pvc -A -o json 2>$null | ConvertFrom-Json).items
        if ($lbs -or $pvcs) {
            Write-Host "Found Kubernetes-managed AWS resources that Terraform won't delete:" -ForegroundColor Red
            $lbs  | ForEach-Object { Write-Host "  LoadBalancer Service: $($_.metadata.namespace)/$($_.metadata.name)" }
            $pvcs | ForEach-Object { Write-Host "  PersistentVolumeClaim: $($_.metadata.namespace)/$($_.metadata.name)" }
            throw "Delete these first (kubectl delete ...), then re-run."
        }
    } else {
        Write-Host "Could not reach the cluster with kubectl; skipping the load balancer/volume check." -ForegroundColor Yellow
    }
}

# 4. Flip the switch (UTF-8 without BOM, keeps line endings)
$updated = ([regex]$pattern).Replace($content, "`${1}$target", 1)
[System.IO.File]::WriteAllText($file, $updated, (New-Object System.Text.UTF8Encoding $false))

# 5. Branch, commit, push, PR
$branch = "chore/dev-$State-$(Get-Date -Format 'yyyyMMdd-HHmm')"
Invoke-Native { git checkout -b $branch } "Could not create branch"
Invoke-Native { git add envs/dev/main.tf } "git add failed"
Invoke-Native { git commit -m "Dev environment $State (cluster_enabled = $target)" } "git commit failed"
Invoke-Native { git push -u origin $branch } "git push failed"
Invoke-Native { gh pr create --title "Dev environment $State" --body "Sets cluster_enabled = $target in envs/dev (EKS + NAT gateway). Opened by scripts/dev-env.ps1." } "Could not open PR"

# 6. Wait for checks
Write-Host "Waiting for CI checks to start..." -ForegroundColor Cyan
Start-Sleep -Seconds 20
gh pr checks --watch
if ($LASTEXITCODE -ne 0) { throw "Checks failed. PR left open for you to inspect." }

# 7. Show the plan and confirm
$comments = gh pr view --json comments --jq '.comments[].body'
$summary  = [regex]::Matches(($comments -join "`n"), 'Plan: .*|No changes\.') | Select-Object -Last 1
Write-Host ""
Write-Host "Terraform plan: $($summary.Value)" -ForegroundColor Green
if ($State -eq "down") { Write-Host "Expect only destroys (EKS + NAT, about 19). If the VPC is listed, answer n." -ForegroundColor Yellow }
$answer = Read-Host "Merge this PR? (y/n)"
if ($answer -ne "y") { Write-Host "Not merged. PR left open." ; exit 0 }

Invoke-Native { gh pr merge --squash --delete-branch } "Merge failed"

# 8. Hand off to the approval gate
Write-Host ""
Write-Host "Merged. Now APPROVE the 'apply (dev)' job:" -ForegroundColor Cyan
Write-Host "  https://github.com/shahparamk/shipyard-infra/actions"
if ($State -eq "up") {
    Write-Host "After apply finishes (about 15-20 min):"
    Write-Host "  aws eks update-kubeconfig --name shipyard-dev --region us-east-1 --profile shipyard"
    Write-Host "  kubectl get nodes"
} else {
    Write-Host "After apply finishes (about 10-15 min), billing for EKS + NAT stops."
}