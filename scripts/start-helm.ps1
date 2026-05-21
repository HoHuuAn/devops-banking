$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Ensure-Namespace {
  param([Parameter(Mandatory = $true)][string]$Name)
  kubectl get namespace $Name --ignore-not-found | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to query namespace '$Name'."
  }
  if (-not (kubectl get namespace $Name --ignore-not-found)) {
    kubectl create namespace $Name | Out-Null
  }
}

function Ensure-HelmRepo {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Url
  )

  $repoListRaw = helm repo list -o json 2>$null
  $repoList = @()
  if ($repoListRaw) {
    $repoList = $repoListRaw | ConvertFrom-Json
  }

  $existing = $repoList | Where-Object { $_.name -eq $Name }
  if (-not $existing) {
    helm repo add $Name $Url | Out-Null
    return $true
  }
  return $false
}

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
$repoAdded = $false
$repoAdded = (Ensure-HelmRepo -Name "haproxytech" -Url "https://haproxytech.github.io/helm-charts") -or $repoAdded
$repoAdded = (Ensure-HelmRepo -Name "prometheus-community" -Url "https://prometheus-community.github.io/helm-charts") -or $repoAdded
$repoAdded = (Ensure-HelmRepo -Name "grafana" -Url "https://grafana.github.io/helm-charts") -or $repoAdded
$repoAdded = (Ensure-HelmRepo -Name "open-telemetry" -Url "https://open-telemetry.github.io/opentelemetry-helm-charts") -or $repoAdded
$repoAdded = (Ensure-HelmRepo -Name "kedacore" -Url "https://kedacore.github.io/charts") -or $repoAdded
$repoAdded = (Ensure-HelmRepo -Name "bitnami" -Url "https://charts.bitnami.com/bitnami") -or $repoAdded
$repoAdded = (Ensure-HelmRepo -Name "kong" -Url "https://charts.konghq.com") -or $repoAdded
if ($repoAdded) {
  Write-Host "  New repo detected, running helm repo update..."
  helm repo update
} else {
  Write-Host "  Helm repos already configured, skipping repo update."
}

Write-Host "==> Installing HAProxy ingress"
helm upgrade --install haproxy haproxytech/kubernetes-ingress `
  --namespace haproxy-controller `
  --create-namespace `
  --set controller.service.type=LoadBalancer

Write-Host "==> Installing KEDA"
helm upgrade --install keda kedacore/keda `
  --namespace keda `
  --create-namespace

Write-Host "==> Installing Postgres HA"
Ensure-Namespace -Name "postgres"
helm upgrade --install postgres bitnami/postgresql `
  --namespace postgres `
  -f ./postgres-ha/values-postgres-ha.yaml `
  --set primary.persistence.storageClass=standard

Write-Host "==> Installing Redis HA"
Ensure-Namespace -Name "redis"
helm upgrade --install redis bitnami/redis `
  --namespace redis `
  -f ./redis-ha/values-redis-ha.yaml `
  --set master.persistence.storageClass=standard `
  --set replica.persistence.storageClass=standard

Write-Host "==> Installing Kong HA"
Ensure-Namespace -Name "kong"

# Wait for Postgres primary to be ready before running kong-db-init
Write-Host "  Waiting for Postgres primary to be Ready..."
kubectl rollout status statefulset/postgres-postgresql-primary -n postgres --timeout=180s

kubectl apply -f ./kong-ha/kong-db-init-job.yaml -n postgres

# Wait for kong-db-init job to complete before installing Kong
Write-Host "  Waiting for kong-db-init job to complete..."
kubectl wait --for=condition=complete job/kong-db-init -n postgres --timeout=120s

helm upgrade --install kong kong/kong `
  --namespace kong `
  -f ./kong-ha/values-kong-ha.yaml
kubectl apply -f ./kong-ha/kong-manager-ingress.yaml -n kong

# Wait for Kong proxy to be ready before importing config
Write-Host "  Waiting for Kong proxy to be Ready..."
kubectl rollout status deployment/kong-kong -n kong --timeout=180s

Write-Host "==> Installing monitoring stack"
Write-Host "==> Ensure 'monitoring' namespace and deploy Loki before Grafana"
Ensure-Namespace -Name "monitoring"

# Fix hostpath-provisioner permissions on all nodes so Loki/Tempo can write to PVCs
Write-Host "  Fixing hostpath-provisioner permissions on all Minikube nodes..."
$raw = minikube node list 2>$null
$nodes = $raw | ForEach-Object {
    $line = $_.ToString().Trim()
    if ($line -and $line -notmatch '^NAME') { ($line -split "\s+")[0] } else { $null }
} | Where-Object { $_ }
if (-not ($nodes -contains "minikube")) { $nodes = @("minikube") + @($nodes) }
foreach ($node in $nodes) {
    Write-Host "  - fixing permissions on $node"
    # Suppress errors if node doesn't exist to gracefully handle minikube's output
    $out = minikube ssh -n $node -- "sudo mkdir -p /tmp/hostpath-provisioner && sudo chmod -R 777 /tmp/hostpath-provisioner" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    (Warning: Could not set permissions on $node)" -ForegroundColor Yellow
    }
}

Write-Host "==> Installing Loki (so Grafana finds the datasource at startup)"
helm upgrade --install loki grafana/loki `
  --namespace monitoring `
  --create-namespace `
  -f ./helm-monitoring/values-loki.yaml `
  --set loki.limits_config.volume_enabled=true

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --create-namespace `
  -f ./helm-monitoring/values-kube-prometheus-stack.yaml `
  --set grafana.persistence.storageClassName=standard `
  --wait --timeout 10m

helm upgrade --install tempo grafana/tempo `
  --namespace monitoring `
  -f ./helm-monitoring/values-tempo.yaml `
  --set persistence.storageClass=standard `
  --set persistence.storageClassName=standard

helm upgrade --install opentelemetry-collector open-telemetry/opentelemetry-collector `
  --namespace monitoring `
  -f ./helm-monitoring/values-otel-collector.yaml

# Deploy optional exporters (Postgres, Redis) if present
$exportDir = Join-Path $RepoRoot "helm-monitoring"
$exportFiles = @(
  "postgres-exporter.yaml",
  "redis-exporter.yaml"
)

Write-Host "==> Applying optional exporters (Postgres, Redis)"
foreach ($file in $exportFiles) {
  $filePath = Join-Path $exportDir $file
  if (Test-Path $filePath) {
    Write-Host "Applying $file..."
    $targetNamespace = "monitoring"
    if ($file -eq "redis-exporter.yaml") { $targetNamespace = "redis" }
    if ($file -eq "postgres-exporter.yaml") { $targetNamespace = "postgres" }
    kubectl apply -f $filePath -n $targetNamespace
  } else {
    Write-Warning "File not found: $filePath"
  }
}

Write-Host "==> Applying Grafana dashboards from YAML files"
$monitorDir = Join-Path $RepoRoot "helm-monitoring"

if (Test-Path $monitorDir) {
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

kubectl apply -f ./kong-ha/kong-import-job.yaml -n kong

Write-Host "  Waiting for kong-config-import job to complete..."
kubectl wait --for=condition=complete job/kong-config-import -n kong --timeout=120s

Write-Host "  Restarting Kong proxy to load imported routes..."
kubectl rollout restart deployment/kong-kong -n kong
kubectl rollout status deployment/kong-kong -n kong --timeout=180s

Write-Host "==> Installing banking app"
Ensure-Namespace -Name "banking"

kubectl label namespace banking app.kubernetes.io/managed-by=Helm --overwrite
kubectl annotate namespace banking meta.helm.sh/release-name=banking --overwrite
kubectl annotate namespace banking meta.helm.sh/release-namespace=banking --overwrite

# - helm-chart/templates/secret.yaml
# - helm-chart/charts/common/values.yaml (secret.*)
# Keep block below commented as fallback only.
# if (kubectl get secret banking-db-secret -n banking --ignore-not-found) {
#   Write-Host "  Adopting existing banking-db-secret into Helm release"
# } else {
#   Write-Host "  Creating banking-db-secret in namespace 'banking'"
#   kubectl create secret generic banking-db-secret `
#     --from-literal=postgresUser=banking `
#     --from-literal=postgresPassword=bankingpass `
#     --from-literal=postgresDb=banking `
#     -n banking --dry-run=client -o yaml | kubectl apply -f -
# }
#
# kubectl label secret banking-db-secret app.kubernetes.io/managed-by=Helm --overwrite -n banking
# kubectl annotate secret banking-db-secret meta.helm.sh/release-name=banking --overwrite -n banking
# kubectl annotate secret banking-db-secret meta.helm.sh/release-namespace=banking --overwrite -n banking

helm upgrade --install banking ./helm-chart `
  --namespace banking `
  --create-namespace `
  -f ./helm-chart/charts/common/values.yaml `
  -f ./helm-chart/charts/account-service/values.yaml `
  -f ./helm-chart/charts/auth-service/values.yaml `
  -f ./helm-chart/charts/notification-service/values.yaml `
  -f ./helm-chart/charts/transfer-service/values.yaml `
  -f ./helm-chart/charts/frontend/values.yaml `
  --set kong.enabled=false --wait --timeout 10m
 

Write-Host "==> Done. Keep 'minikube tunnel' running in another terminal."
