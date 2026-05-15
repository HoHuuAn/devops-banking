$ErrorActionPreference = "Continue"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "==> Uninstalling Helm releases"
helm uninstall banking -n banking
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall tempo -n monitoring
helm uninstall opentelemetry-collector -n monitoring
helm uninstall keda -n keda
helm uninstall haproxy -n haproxy-controller

Write-Host "==> Deleting PVCs"
foreach ($ns in @("banking", "monitoring", "keda", "haproxy-controller")) {
    kubectl delete pvc --all -n $ns --ignore-not-found=true
}

Write-Host "==> Deleting namespaces"
foreach ($ns in @("banking", "monitoring", "keda", "haproxy-controller")) {
    kubectl delete namespace $ns --ignore-not-found=true
}

Write-Host "==> Deleting PVs for banking/monitoring/keda/haproxy-controller"
try {
    $pv = kubectl get pv -o json | ConvertFrom-Json
    $names = $pv.items | Where-Object {
        ($_.spec.claimRef -and ($_.spec.claimRef.namespace -in @("banking", "monitoring", "keda", "haproxy-controller"))) -or
        ($_.status.phase -in @("Released", "Failed"))
    } | ForEach-Object { $_.metadata.name }
    if ($names) {
        kubectl delete pv $names
    } else {
        Write-Host "No PVs found for target namespaces."
    }
} catch {
    Write-Warning "Could not list PVs. Ensure kubectl is configured."
}

Write-Host "==> Cleaning Minikube hostpath data (/tmp/hostpath-provisioner) on all nodes"
try {
    $nodes = @()
    try {
        $nodeJson = minikube node list -o json | ConvertFrom-Json
        if ($nodeJson.nodes) {
            $nodes = $nodeJson.nodes | ForEach-Object { $_.name }
        }
    } catch {
        $nodes = @()
    }

    if (-not $nodes -or $nodes.Count -eq 0) {
        $raw = minikube node list | Select-Object -Skip 1
        $nodes = $raw | ForEach-Object {
            $line = $_.ToString().Trim()
            if ($line) { ($line -split "\s+")[0] } else { $null }
        } | Where-Object { $_ }
    }

    if (-not $nodes -or $nodes.Count -eq 0) {
        Write-Warning "No Minikube nodes found."
    } else {
        foreach ($node in $nodes) {
            Write-Host "  - $node"
            minikube ssh -n $node -- "sudo rm -rf /tmp/hostpath-provisioner/*"
        }
    }
} catch {
    Write-Warning "Could not clean Minikube hostpath data. Ensure minikube is running."
}

Write-Host "==> Done."