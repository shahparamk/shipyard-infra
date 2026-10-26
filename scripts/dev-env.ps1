<#
.SYNOPSIS
  Turn the ShipYard dev environment (EKS + NAT + RDS) up or down through a reviewed PR.
.DESCRIPTION
  "down" first removes the Argo CD apps so the AWS Load Balancer Controller deletes the ALB
  and ExternalDNS deletes the DNS record. Those resources live outside Terraform; destroying
  the cluster first would orphan a billing load balancer.
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
$ClusterName = "shipyard-dev"

function Invoke-Native {
    param([scriptblock]$Command, [string]$ErrorMessage)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw $ErrorMessage }
}

# Load balancers the controller created for THIS cluster (it tags them elbv2.k8s.aws/cluster)
function Get-ClusterLoadBalancers {
    $arns = aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerArn" --output text 2>$null
    $ours = @()
    foreach ($arn in ($arns -split "\s+" | Where-Object { $_ })) {
        $owner = aws elbv2 describe-tags --resource-arns $arn --query "TagDescriptions[0].Tags[?Key=='elbv2.k8s.aws/cluster'].Value" --output text
        if ($owner -eq $ClusterName) { $ours += $arn }
    }
    return ,$ours
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

# 3. Before teardown: let the controllers delete what they created outside Terraform
if ($State -eq "down") {
    kubectl get namespaces 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Removing Argo CD apps so the ALB and DNS record get cleaned up..." -ForegroundColor Cyan
        # Delete root first (no finalizer), so Argo stops recreating the child apps
        kubectl delete application root -n argocd --ignore-not-found --wait=true | Out-Null
        # The orders app has a cascade finalizer: deleting it deletes the Ingress -> ALB + DNS record
        kubectl delete application orders -n argocd --ignore-not-found --wait=true --timeout=5m | Out-Null

        $deadline = (Get-Date).AddMinutes(8)
        while ((kubectl get ingress -A -o name 2>$null) -and (Get-Date) -lt $deadline) {
            Write-Host "  waiting for Ingresses to be removed..."
            Start-Sleep -Seconds 10
        }

        do {
            $lbs = Get-ClusterLoadBalancers
            if ($lbs.Count -gt 0) {
                Write-Host "  waiting for $($lbs.Count) load balancer(s) to be deleted by the controller..."
                Start-Sleep -Seconds 15
            }
        } while ($lbs.Count -gt 0 -and (Get-Date) -lt $deadline)

        if ($lbs.Count -gt 0) {
            throw "Load balancer(s) still exist: $($lbs -join ', '). Check 'kubectl logs -n kube-system deploy/aws-load-balancer-controller' before tearing down."
        }

        Write-Host "  giving ExternalDNS a minute to remove the DNS record..."
        Start-Sleep -Seconds 70

        # Anything else Kubernetes created in AWS that Terraform can't see
        $svcJson = kubectl get svc -A -o json 2>$null
        $lbSvcs = ($svcJson | ConvertFrom-Json).items | Where-Object { $_.spec.type -eq "LoadBalancer" }
        $pvcs   = (kubectl get pvc -A -o json 2>$null | ConvertFrom-Json).items
        if ($lbSvcs -or $pvcs) {
            Write-Host "Found Kubernetes-managed AWS resources that Terraform won't delete:" -ForegroundColor Red
            $lbSvcs | ForEach-Object { Write-Host "  LoadBalancer Service: $($_.metadata.namespace)/$($_.metadata.name)" }
            $pvcs   | ForEach-Object { Write-Host "  PersistentVolumeClaim: $($_.metadata.namespace)/$($_.metadata.name)" }
            throw "Delete these first (kubectl delete ...), then re-run."
        }
        Write-Host "Cluster is clean of external AWS resources." -ForegroundColor Green
    } else {
        Write-Host "Could not reach the cluster with kubectl; checking AWS directly for leftover load balancers..." -ForegroundColor Yellow
        $lbs = Get-ClusterLoadBalancers
        if ($lbs.Count -gt 0) { throw "Load balancer(s) for $ClusterName still exist: $($lbs -join ', '). Delete them before tearing down." }
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
Invoke-Native { gh pr create --title "Dev environment $State" --body "Sets cluster_enabled = $target in envs/dev (EKS + NAT gateway + RDS). Opened by scripts/dev-env.ps1." } "Could not open PR"

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
if ($State -eq "down") { Write-Host "Expect only destroys (EKS + NAT + RDS + associations). If the VPC is listed, answer n." -ForegroundColor Yellow }
$answer = Read-Host "Merge this PR? (y/n)"
if ($answer -ne "y") { Write-Host "Not merged. PR left open." ; exit 0 }

Invoke-Native { gh pr merge --squash --delete-branch } "Merge failed"

# 8. Hand off to the approval gate
Write-Host ""
Write-Host "Merged. Now APPROVE the 'apply (dev)' job:" -ForegroundColor Cyan
Write-Host "  https://github.com/shahparamk/shipyard-infra/actions"
if ($State -eq "up") {
    Write-Host "After apply finishes (about 25 min), bootstrap the cluster:"
    Write-Host "  aws eks update-kubeconfig --name $ClusterName --region us-east-1 --profile shipyard"
    Write-Host "  helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --version 2.12.0 --wait"
    Write-Host "  helm install argocd argo/argo-cd -n argocd --create-namespace --version 10.10.1 --wait"
    Write-Host "  kubectl apply -f ..\shipyard-gitops\argocd\root.yaml"
} else {
    Write-Host "After apply finishes (about 10-15 min), billing for EKS + NAT + RDS stops."
}