$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "==> Using StorageClass 'standard' for local Minikube"
try {
  $sc = kubectl get storageclass -o json | ConvertFrom-Json
  $hasStandard = $sc.items | Where-Object { $_.metadata.name -eq "standard" }
  if (-not $hasStandard) {
    Write-Warning "StorageClass 'standard' not found. Check your cluster StorageClasses."
  }
} catch {
  Write-Warning "Could not check StorageClass. Ensure kubectl is configured."
}

Write-Host "==> Adding Helm repos"
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

Write-Host "==> Installing HAProxy ingress"
helm upgrade --install haproxy haproxytech/kubernetes-ingress `
  --namespace haproxy-controller `
  --create-namespace `
  --set controller.service.type=LoadBalancer

Write-Host "==> Installing KEDA"
helm upgrade --install keda kedacore/keda `
  --namespace keda `
  --create-namespace

Write-Host "==> Installing banking app"
helm upgrade --install banking ./helm-chart `
  --namespace banking `
  --create-namespace `
  -f ./helm-chart/charts/common/values.yaml `
  -f ./helm-chart/charts/postgres/values.yaml `
  -f ./helm-chart/charts/redis/values.yaml `
  -f ./helm-chart/charts/kong/values.yaml `
  -f ./helm-chart/charts/account-service/values.yaml `
  -f ./helm-chart/charts/auth-service/values.yaml `
  -f ./helm-chart/charts/notification-service/values.yaml `
  -f ./helm-chart/charts/transfer-service/values.yaml `
  -f ./helm-chart/charts/frontend/values.yaml `
  --set postgres.storage.storageClassName=standard `
  --set redis.storage.storageClassName=standard

Write-Host "==> Installing monitoring stack"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --create-namespace `
  -f ./helm-monitoring/values-kube-prometheus-stack.yaml `
  --set grafana.persistence.storageClassName=standard

helm upgrade --install tempo grafana/tempo `
  --namespace monitoring `
  -f ./helm-monitoring/values-tempo.yaml `
  --set persistence.storageClass=standard `
  --set persistence.storageClassName=standard

helm upgrade --install opentelemetry-collector open-telemetry/opentelemetry-collector `
  --namespace monitoring `
  -f ./helm-monitoring/values-otel-collector.yaml

# Write-Host "==> Loading Grafana dashboards"
# $dashDir = Join-Path $RepoRoot "helm-monitoring\dashboards"
# if (Test-Path $dashDir) {
#     kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
#     Get-ChildItem -Path $dashDir -File -Filter "*.json" | ForEach-Object {
#         $cmName = "grafana-dashboard-" + $_.BaseName.ToLower()
#         Write-Host "Creating ConfigMap for dashboard: $($_.Name)"
        
#         kubectl create configmap $cmName --from-file=$($_.FullName) -n monitoring --dry-run=client -o yaml | kubectl apply -f -
#         kubectl label configmap $cmName grafana_dashboard="1" -n monitoring --overwrite    
#     }
# } else {
#     Write-Warning "Dashboards folder not found: $dashDir"
# }

Write-Host "==> Applying Grafana dashboards from YAML files"
$monitorDir = Join-Path $RepoRoot "helm-monitoring"

if (Test-Path $monitorDir) {
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

    $dashboardFiles = @(
        "grafana-dashboard-banking-services.yaml",
        "grafana-dashboard-kong.yaml"
    )

    foreach ($file in $dashboardFiles) {
        $filePath = Join-Path $monitorDir $file
        if (Test-Path $filePath) {
            Write-Host "Applying $file..."
            kubectl apply -f $filePath -n monitoring
        } else {
            Write-Warning "File not found: $filePath"
        }
    }
} else {
    Write-Warning "Monitoring directory not found: $monitorDir"
}

Write-Host "==> Done. Keep 'minikube tunnel' running in another terminal."