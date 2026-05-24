$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Ensure-Namespace {
  param([Parameter(Mandatory = $true)][string]$Name)
  kubectl get namespace $Name --ignore-not-found | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Failed to query namespace '$Name'." }
  if (-not (kubectl get namespace $Name --ignore-not-found)) { kubectl create namespace $Name | Out-Null }
}

function Ensure-HelmRepo {
  param([Parameter(Mandatory = $true)][string]$Name,[Parameter(Mandatory = $true)][string]$Url)
  $reposRaw = helm repo list -o json 2>$null
  $repos = if ($reposRaw) { $reposRaw | ConvertFrom-Json } else { @() }
  if ($repos | Where-Object { $_.name -eq $Name }) { return $false }
  helm repo add $Name $Url | Out-Null
  return $true
}

function Invoke-HelmInstall {
  param(
    [Parameter(Mandatory = $true)][string]$Release,
    [Parameter(Mandatory = $true)][string]$Chart,
    [Parameter(Mandatory = $true)][string]$Namespace,
    [string[]]$ValuesFiles = @(),
    [string[]]$ExtraArgs = @()
  )
  $args = @("upgrade","--install",$Release,$Chart,"--namespace",$Namespace,"--create-namespace")
  foreach ($vf in $ValuesFiles) { $args += @("-f",$vf) }
  if ($ExtraArgs.Count -gt 0) { $args += $ExtraArgs }
  & helm @args
}

function Wait-DeploymentRollout {
  param([string]$Namespace,[string[]]$Names,[int]$TimeoutSeconds = 240)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $pending = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($name in $Names) { [void]$pending.Add($name) }
  while ($pending.Count -gt 0) {
    if ((Get-Date) -gt $deadline) { throw "Timed out waiting for deployments in namespace '$Namespace': $($pending -join ', ')" }
    foreach ($name in @($pending)) {
      $json = kubectl get deployment $name -n $Namespace -o json 2>$null
      if ($LASTEXITCODE -ne 0 -or -not $json) { continue }
      $obj = $json | ConvertFrom-Json
      $desired = [int]$obj.spec.replicas
      $updated = [int]$obj.status.updatedReplicas
      $available = [int]$obj.status.availableReplicas
      $observed = [int]$obj.status.observedGeneration
      $generation = [int]$obj.metadata.generation
      if ($observed -ge $generation -and $updated -ge $desired -and $available -ge $desired) {
        Write-Host "  deployment/$name is Ready ($available/$desired)."
        [void]$pending.Remove($name)
      }
    }
    if ($pending.Count -gt 0) { Start-Sleep -Seconds 3 }
  }
}

function Fix-HostpathProvisionerPermissions {
  Write-Host "  Fixing hostpath-provisioner permissions on all Minikube nodes..."
  $raw = minikube node list 2>$null
  $nodes = $raw | ForEach-Object {
    $line = $_.ToString().Trim()
    if ($line -and $line -notmatch '^NAME') { ($line -split "\s+")[0] } else { $null }
  } | Where-Object { $_ }
  if (-not ($nodes -contains "minikube")) { $nodes = @("minikube") + @($nodes) }
  foreach ($node in $nodes) {
    Write-Host "  - fixing permissions on $node"
    $null = minikube ssh -n $node -- "sudo mkdir -p /tmp/hostpath-provisioner && sudo chmod -R 777 /tmp/hostpath-provisioner" 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "    (Warning: Could not set permissions on $node)" -ForegroundColor Yellow }
  }
}

function Setup-Prerequisites {
  Write-Host "==> Using StorageClass 'standard' for local Minikube"
  try {
    $sc = kubectl get storageclass -o json | ConvertFrom-Json
    if (-not ($sc.items | Where-Object { $_.metadata.name -eq "standard" })) { Write-Warning "StorageClass 'standard' not found. Check your cluster StorageClasses." }
  } catch { Write-Warning "Could not check StorageClass. Ensure kubectl is configured." }

  Write-Host "==> Adding Helm repos"
  $repoAdded = $false
  $repoMap = @{
    "haproxytech" = "https://haproxytech.github.io/helm-charts"
    "prometheus-community" = "https://prometheus-community.github.io/helm-charts"
    "grafana" = "https://grafana.github.io/helm-charts"
    "open-telemetry" = "https://open-telemetry.github.io/opentelemetry-helm-charts"
    "kedacore" = "https://kedacore.github.io/charts"
    "bitnami" = "https://charts.bitnami.com/bitnami"
    "kong" = "https://charts.konghq.com"
  }
  foreach ($name in $repoMap.Keys) { $repoAdded = (Ensure-HelmRepo -Name $name -Url $repoMap[$name]) -or $repoAdded }
  if ($repoAdded) { Write-Host "  New repo detected, running helm repo update..."; helm repo update } else { Write-Host "  Helm repos already configured, skipping repo update." }
}

function Install-CoreInfra {
  Write-Host "==> Installing HAProxy ingress"
  Invoke-HelmInstall -Release "haproxy" -Chart "haproxytech/kubernetes-ingress" -Namespace "haproxy-controller" -ExtraArgs @("--set","controller.service.type=LoadBalancer")

  Write-Host "==> Installing KEDA"
  Invoke-HelmInstall -Release "keda" -Chart "kedacore/keda" -Namespace "keda"

  Write-Host "==> Installing Postgres HA"
  Ensure-Namespace -Name "postgres"
  Invoke-HelmInstall -Release "postgres" -Chart "bitnami/postgresql" -Namespace "postgres" -ValuesFiles @("./postgres-ha/values-postgres-ha.yaml") -ExtraArgs @("--set","primary.persistence.storageClass=standard")

  Write-Host "==> Installing Redis HA"
  Ensure-Namespace -Name "redis"
  Invoke-HelmInstall -Release "redis" -Chart "bitnami/redis" -Namespace "redis" -ValuesFiles @("./redis-ha/values-redis-ha.yaml") -ExtraArgs @("--set","master.persistence.storageClass=standard","--set","replica.persistence.storageClass=standard")

  Write-Host "==> Installing RabbitMQ"
  Ensure-Namespace -Name "rabbit"
  kubectl apply -f ./rabbitmq/rabbitmq-secret.yaml
  kubectl apply -f ./rabbitmq/k8s-rabbitmq-standalone.yaml
  kubectl rollout status statefulset/rabbitmq -n rabbit --timeout=300s
}

function Install-KongAndRoutes {
  Write-Host "==> Installing Kong HA"
  Ensure-Namespace -Name "kong"
  kubectl rollout status statefulset/postgres-postgresql-primary -n postgres --timeout=180s
  kubectl apply -f ./kong-ha/kong-db-init-job.yaml -n postgres
  kubectl wait --for=condition=complete job/kong-db-init -n postgres --timeout=120s
  Invoke-HelmInstall -Release "kong" -Chart "kong/kong" -Namespace "kong" -ValuesFiles @("./kong-ha/values-kong-ha.yaml")
  kubectl apply -f ./kong-ha/kong-manager-ingress.yaml -n kong
  kubectl rollout status deployment/kong-kong -n kong --timeout=180s
}

function Install-BankingApps {
  Write-Host "==> Installing banking app"
  Ensure-Namespace -Name "banking"
  kubectl label namespace banking app.kubernetes.io/managed-by=Helm --overwrite
  kubectl annotate namespace banking meta.helm.sh/release-name=banking --overwrite
  kubectl annotate namespace banking meta.helm.sh/release-namespace=banking --overwrite

  Invoke-HelmInstall -Release "banking" -Chart "./helm-chart" -Namespace "banking" -ValuesFiles @(
    "./helm-chart/charts/common/values.yaml",
    "./helm-chart/charts/account-service/values.yaml",
    "./helm-chart/charts/auth-service/values.yaml",
    "./helm-chart/charts/notification-service/values.yaml",
    "./helm-chart/charts/transfer-service/values.yaml",
    "./helm-chart/charts/frontend/values.yaml"
  ) -ExtraArgs @("--set","kong.enabled=false","--set","postgres.enabled=false","--set","redis.enabled=false","--timeout","3m")

  Write-Host "==> Installing api-producer"
  Invoke-HelmInstall -Release "api-producer" -Chart "./helm-api-producer" -Namespace "banking" -ValuesFiles @("./helm-api-producer/values.yaml") -ExtraArgs @("--timeout","3m")

  Wait-DeploymentRollout -Namespace "banking" -Names @("auth-service","account-service","transfer-service","notification-service","frontend","api-producer") -TimeoutSeconds 420
}

function Import-KongRoutes {
  Write-Host "==> Importing Kong routes"
  kubectl delete job kong-config-import -n kong --ignore-not-found
  kubectl apply -f ./kong-ha/kong-import-job.yaml -n kong
  kubectl wait --for=condition=complete job/kong-config-import -n kong --timeout=180s
  kubectl rollout restart deployment/kong-kong -n kong
  kubectl rollout status deployment/kong-kong -n kong --timeout=180s
}

function Install-Monitoring {
  Write-Host "==> Installing monitoring stack"
  Ensure-Namespace -Name "monitoring"
  Fix-HostpathProvisionerPermissions

  Invoke-HelmInstall -Release "loki" -Chart "grafana/loki" -Namespace "monitoring" -ValuesFiles @("./helm-monitoring/values-loki.yaml") -ExtraArgs @("--set","loki.limits_config.volume_enabled=true")

  Write-Host "==> Installing Promtail"
  Invoke-HelmInstall -Release "promtail" -Chart "grafana/promtail" -Namespace "monitoring" -ValuesFiles @("./helm-monitoring/values-promtail.yaml")
  kubectl rollout status daemonset/promtail -n monitoring --timeout=300s

  Invoke-HelmInstall -Release "kube-prometheus-stack" -Chart "prometheus-community/kube-prometheus-stack" -Namespace "monitoring" -ValuesFiles @("./helm-monitoring/values-kube-prometheus-stack.yaml") -ExtraArgs @("--set","grafana.persistence.storageClassName=standard","--wait","--timeout","10m")
  Invoke-HelmInstall -Release "tempo" -Chart "grafana/tempo" -Namespace "monitoring" -ValuesFiles @("./helm-monitoring/values-tempo.yaml") -ExtraArgs @("--set","persistence.storageClass=standard","--set","persistence.storageClassName=standard")
  Invoke-HelmInstall -Release "opentelemetry-collector" -Chart "open-telemetry/opentelemetry-collector" -Namespace "monitoring" -ValuesFiles @("./helm-monitoring/values-otel-collector.yaml")

  $monitorDir = Join-Path $RepoRoot "helm-monitoring"
  foreach ($pair in @(@("postgres-exporter.yaml","postgres"), @("redis-exporter.yaml","redis"), @("grafana-dashboard-banking-services.yaml","monitoring"), @("grafana-dashboard-kong.yaml","monitoring"), @("grafana-dashboard-rabbitmq.yaml","monitoring"))) {
    $file = $pair[0]; $ns = $pair[1]; $path = Join-Path $monitorDir $file
    if (Test-Path $path) { Write-Host "Applying $file..."; kubectl apply -f $path -n $ns } else { Write-Warning "File not found: $path" }
  }
}

$scriptStart = Get-Date
Setup-Prerequisites
Install-CoreInfra
Install-KongAndRoutes
Install-BankingApps
Import-KongRoutes
Install-Monitoring
$elapsed = (Get-Date) - $scriptStart
Write-Host "==> Done in $([math]::Round($elapsed.TotalMinutes, 2)) minutes. Keep 'minikube tunnel' running in another terminal."
