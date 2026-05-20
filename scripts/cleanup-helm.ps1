$ErrorActionPreference = "Continue"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "==> Uninstalling Helm releases"
helm uninstall banking -n banking
helm uninstall kong -n kong
helm uninstall redis -n redis
helm uninstall postgres -n postgres
helm uninstall loki -n monitoring
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall tempo -n monitoring
helm uninstall opentelemetry-collector -n monitoring
helm uninstall keda -n keda
helm uninstall haproxy -n haproxy-controller

Write-Host "==> Deleting PVCs"
foreach ($ns in @("banking", "kong", "redis", "postgres", "monitoring", "keda", "haproxy-controller")) {
    Write-Host "Deleting PVCs in namespace: $ns"
    kubectl delete pvc --all -n $ns --ignore-not-found=true --wait=false
    $wait = 0
    while ($wait -lt 120) {
        $remaining = kubectl get pvc -n $ns --no-headers 2>$null | Select-String . -Quiet
        if (-not $remaining) { break }
        Start-Sleep -Seconds 2
        $wait += 2
    }
    if ($remaining) {
        Write-Warning "Some PVCs in namespace '$ns' did not delete within timeout - attempting to remove finalizers and force-delete."
        $pvcs = kubectl get pvc -n $ns -o json | ConvertFrom-Json
        if ($pvcs.items) {
            foreach ($pvc in $pvcs.items) {
                $pvcName = $pvc.metadata.name
                Write-Host "  - Forcibly removing finalizers and deleting PVC: $pvcName"
                try {
                    $pvcJson = kubectl get pvc $pvcName -n $ns -o json 2>$null
                    if ($pvcJson) {
                        if ($pvcJson -match '"finalizers"') {
                            $patchedJson = $pvcJson -replace '"finalizers"\s*:\s*\[[^\]]*\]', '"finalizers":[]'
                            $patchedJson | kubectl replace -f - 2>$null
                            Write-Host "    - removed finalizers from PVC $pvcName"
                        } else {
                            Write-Host "    - no finalizers on PVC $pvcName"
                        }
                    }
                } catch {
                    Write-Warning "Failed to remove finalizers for PVC ${pvcName}: $($_)"
                }
                try {
                    kubectl delete pvc $pvcName -n $ns --grace-period=0 --force --ignore-not-found=true
                } catch {
                    Write-Warning "Failed to force-delete PVC ${pvcName}: $($_)"
                }
            }
        }
    }
}

Write-Host "==> Deleting KEDA ScaledObjects before namespace removal"
foreach ($ns in @("banking", "kong", "redis", "postgres", "monitoring", "keda", "haproxy-controller")) {
    Write-Host "Deleting ScaledObjects in namespace: $ns"
    try {
        $scaledObjects = kubectl get scaledobject -n $ns -o json 2>$null | ConvertFrom-Json
        if ($scaledObjects.items) {
            foreach ($scaledObject in $scaledObjects.items) {
                $scaledObjectName = $scaledObject.metadata.name
                Write-Host "  - Removing finalizers from ScaledObject: $scaledObjectName"
                try {
                    kubectl patch scaledobject $scaledObjectName -n $ns --type=merge -p '{"metadata":{"finalizers":[]}}' 2>$null | Out-Null
                } catch {
                    Write-Warning "Failed to patch finalizers for ScaledObject ${scaledObjectName}: $($_)"
                }
                try {
                    kubectl delete scaledobject $scaledObjectName -n $ns --grace-period=0 --force --ignore-not-found=true 2>$null | Out-Null
                } catch {
                    Write-Warning "Failed to force-delete ScaledObject ${scaledObjectName}: $($_)"
                }
            }
        }

        $wait = 0
        while ($wait -lt 60) {
            $remainingScaledObjects = kubectl get scaledobject -n $ns --no-headers 2>$null | Select-String . -Quiet
            if (-not $remainingScaledObjects) { break }
            Start-Sleep -Seconds 2
            $wait += 2
        }

        if ($remainingScaledObjects) {
            Write-Warning "Some ScaledObjects in namespace '$ns' still exist after force-delete; patching and retrying once more."
            $scaledObjects = kubectl get scaledobject -n $ns -o json 2>$null | ConvertFrom-Json
            if ($scaledObjects.items) {
                foreach ($scaledObject in $scaledObjects.items) {
                    $scaledObjectName = $scaledObject.metadata.name
                    try {
                        kubectl patch scaledobject $scaledObjectName -n $ns --type=merge -p '{"metadata":{"finalizers":[]}}' 2>$null | Out-Null
                        kubectl delete scaledobject $scaledObjectName -n $ns --grace-period=0 --force --ignore-not-found=true 2>$null | Out-Null
                    } catch {
                        Write-Warning "Second pass failed for ScaledObject ${scaledObjectName}: $($_)"
                    }
                }
            }
        }
    } catch {
        Write-Warning "Could not delete ScaledObjects in namespace '$ns': $($_)"
    }
}

Write-Host "==> Deleting namespaces"
foreach ($ns in @("banking", "kong", "redis", "postgres", "monitoring", "keda", "haproxy-controller")) {
    kubectl delete namespace $ns --ignore-not-found=true
}

Write-Host "==> Clearing stuck namespace finalizers"
foreach ($ns in @("banking", "kong", "redis", "postgres", "monitoring", "keda", "haproxy-controller")) {
    try {
        $phase = kubectl get namespace $ns -o jsonpath='{.status.phase}' 2>$null
        if ($phase -eq 'Terminating') {
            Write-Host "  - Patching finalizers for namespace: $ns"
            kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>$null
        }
    } catch {
        # ignore errors where namespace no longer exists
    }
}

Write-Host "==> Deleting PVs for target namespaces"
try {
    $pv = kubectl get pv -o json | ConvertFrom-Json
    $targetNamespaces = @("banking", "kong", "redis", "postgres", "monitoring", "keda", "haproxy-controller")
    $names = $pv.items | Where-Object {
        ($_.spec.claimRef -and ($targetNamespaces -contains $_.spec.claimRef.namespace)) -or
        ($_.status.phase -eq "Released" -or $_.status.phase -eq "Failed")
    } | ForEach-Object { $_.metadata.name }
    if ($names) {
        foreach ($pvName in $names) {
            Write-Host "Attempting delete PV: $pvName"
            try {
                kubectl delete pv $pvName --ignore-not-found=true --wait=false
            } catch {
                Write-Warning "Normal delete failed for PV ${pvName}: $($_)"
            }
            Start-Sleep -Seconds 2
            # If PV still exists and is in Released/Failed, remove finalizers and force-delete
            try {
                $existsJson = kubectl get pv $pvName -o json 2>$null
                $exists = if ($existsJson) { $existsJson | ConvertFrom-Json } else { $null }
            } catch { $exists = $null }
            if ($exists) {
                $phase = $exists.status.phase
                if ($phase -in @("Released", "Failed")) {
                    Write-Warning "PV $pvName in phase '$phase' - removing finalizers and force-deleting."
                    try {
                        if ($existsJson -match '"finalizers"') {
                            $patchedJson = $existsJson -replace '"finalizers"\s*:\s*\[[^\]]*\]', '"finalizers":[]'
                            $patchedJson | kubectl replace -f - 2>$null
                            Write-Host "    - removed finalizers from PV $pvName"
                        } else {
                            Write-Host "    - no finalizers on PV $pvName"
                        }
                    } catch {
                        Write-Warning "Failed to patch finalizers for PV ${pvName}: $_"
                    }
                    try {
                        kubectl delete pv $pvName --grace-period=0 --force --ignore-not-found=true
                    } catch {
                        Write-Warning "Failed to force-delete PV ${pvName}: $_"
                    }
                }
            }
        }
    } else {
        Write-Host "No PVs found for target namespaces."
    }
} catch {
    Write-Warning "Could not list PVs. Ensure kubectl is configured."
}

Write-Host "==> Deleting monitoring exporters (Postgres, Redis)"
try {
    $exportFiles = @("./helm-monitoring/postgres-exporter.yaml", "./helm-monitoring/redis-exporter.yaml")
    foreach ($ef in $exportFiles) {
        if (Test-Path $ef) {
            Write-Host "Deleting $ef..."
            kubectl delete -f $ef -n monitoring --ignore-not-found=true
        } else {
            # Try delete by name in case file isn't present
            $name = [System.IO.Path]::GetFileNameWithoutExtension($ef)
            Write-Host "Deleting resource by name: $name"
            kubectl delete deployment/$name -n monitoring --ignore-not-found=true
            kubectl delete service/$name -n monitoring --ignore-not-found=true
        }
    }
} catch {
    Write-Warning "Could not delete exporter resources. Ensure kubectl is configured."
}

Write-Host "==> Cleaning Minikube hostpath data (/tmp/hostpath-provisioner) on all nodes"
try {
    $raw = minikube node list 2>$null
    $nodes = $raw | ForEach-Object {
        $line = $_.ToString().Trim()
        if ($line -and $line -notmatch '^NAME') { ($line -split "\s+")[0] } else { $null }
    } | Where-Object { $_ }

    # Always include the primary node
    if (-not ($nodes -contains "minikube")) {
        $nodes = @("minikube") + @($nodes)
    }

    if (-not $nodes -or $nodes.Count -eq 0) {
        Write-Warning "No Minikube nodes found."
    } else {
        foreach ($node in $nodes) {
            Write-Host "  - $node"
            minikube ssh -n $node -- "sudo rm -rf /tmp/hostpath-provisioner/*" 2>$null
        }
    }
} catch {
    Write-Warning "Could not clean Minikube hostpath data. Ensure minikube is running."
}

Write-Host "==> Done."