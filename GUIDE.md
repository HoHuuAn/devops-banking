# DevOps Banking - K8s and Helm Guide

This guide covers a clean install, monitoring, KEDA autoscaling, load testing, and cleanup.

## Prerequisites
- Minikube (or any Kubernetes cluster)
- kubectl and Helm 3
- Python 3.10+
- Hosts file entries (Windows: C:\Windows\System32\drivers\etc\hosts):
  - 127.0.0.1 banking.local
  - 127.0.0.1 grafana.banking.local
  - 127.0.0.1 prometheus.banking.local

Keep `minikube tunnel` running in a separate terminal.

## Storage Class (Standard vs NFS)
The repo values are now set to use `nfs` for persistence:
- helm-chart/charts/postgres/values.yaml
- helm-chart/charts/redis/values.yaml
- helm-monitoring/values-kube-prometheus-stack.yaml
- helm-monitoring/values-tempo.yaml
- helm-monitoring/values-loki.yaml

Before deploying, verify a StorageClass named `nfs` exists:
```bash
kubectl get storageclass
```

If you do not have `nfs`, either:
- Create it (recommended for scale-out), or
- Switch the values back to `standard`.

Example NFS provisioner install (replace placeholders):
```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner
helm repo update
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace nfs-provisioner \
  --create-namespace \
  --set nfs.server=<NFS_SERVER_IP> \
  --set nfs.path=<NFS_EXPORT_PATH> \
  --set storageClass.name=nfs \
  --set storageClass.defaultClass=false
```

## Install the Banking App
```bash
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo update
helm install haproxy haproxytech/kubernetes-ingress \
  --namespace haproxy-controller \
  --create-namespace \
  --set controller.service.type=LoadBalancer

helm install banking ./helm-chart \
  --namespace banking \
  --create-namespace \
  -f ./helm-chart/charts/common/values.yaml \
  -f ./helm-chart/charts/postgres/values.yaml \
  -f ./helm-chart/charts/redis/values.yaml \
  -f ./helm-chart/charts/kong/values.yaml \
  -f ./helm-chart/charts/account-service/values.yaml \
  -f ./helm-chart/charts/auth-service/values.yaml \
  -f ./helm-chart/charts/notification-service/values.yaml \
  -f ./helm-chart/charts/transfer-service/values.yaml \
  -f ./helm-chart/charts/frontend/values.yaml
```

## Install Monitoring
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f ./helm-monitoring/values-kube-prometheus-stack.yaml

helm install tempo grafana/tempo \
  --namespace monitoring \
  -f ./helm-monitoring/values-tempo.yaml

helm install opentelemetry-collector open-telemetry/opentelemetry-collector \
  --namespace monitoring \
  -f ./helm-monitoring/values-otel-collector.yaml
```

Optional exporters:
```bash
kubectl apply -f ./helm-monitoring/postgres-exporter.yaml
kubectl apply -f ./helm-monitoring/redis-exporter.yaml
```

## Install and Verify KEDA
```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace
```

If ScaledObject CRD is missing:
```bash
kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.19.0/keda-2.19.0-crds.yaml
```

ScaledObjects are rendered by the Helm chart when `keda.enabled=true` in
helm-chart/charts/common/values.yaml. If KEDA was installed after the app,
re-run Helm to create ScaledObjects:
```bash
helm upgrade banking ./helm-chart \
  --namespace banking \
  -f ./helm-chart/charts/common/values.yaml \
  -f ./helm-chart/charts/postgres/values.yaml \
  -f ./helm-chart/charts/redis/values.yaml \
  -f ./helm-chart/charts/kong/values.yaml \
  -f ./helm-chart/charts/account-service/values.yaml \
  -f ./helm-chart/charts/auth-service/values.yaml \
  -f ./helm-chart/charts/notification-service/values.yaml \
  -f ./helm-chart/charts/transfer-service/values.yaml \
  -f ./helm-chart/charts/frontend/values.yaml

kubectl get scaledobjects -n banking
kubectl get hpa -n banking
```

## Load Test (Validate KEDA)
Install Python deps:
```bash
pip install -r ./scripts/requirements.txt
```

Run load test:
```bash
python ./scripts/load_test.py --scenario all --users 20 --rps 50 --duration 60 --base-url http://banking.local
```

Watch scaling:
```bash
kubectl get hpa -n banking -w
kubectl get pods -n banking -w
```

## Cleanup and Full Reset
```bash
helm uninstall banking -n banking
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall tempo -n monitoring
helm uninstall opentelemetry-collector -n monitoring
helm uninstall keda -n keda
kubectl delete namespace banking --ignore-not-found=true
kubectl delete namespace monitoring --ignore-not-found=true
kubectl delete namespace keda --ignore-not-found=true
```

Delete PVCs and PVs if data persists:
```bash
kubectl delete pvc --all -n banking
kubectl delete pvc --all -n monitoring

$pv = kubectl get pv -o json | ConvertFrom-Json
$names = $pv.items | Where-Object { $_.spec.claimRef -and ($_.spec.claimRef.namespace -in @('banking','monitoring','keda')) } | ForEach-Object { $_.metadata.name }
if ($names) { kubectl delete pv $names }
```

On Minikube hostpath, data can remain even after PV deletion. If needed:
```bash
minikube ssh
sudo rm -rf /tmp/hostpath-provisioner/*
```

## Troubleshooting Notes
- Data persists after namespace delete because PVCs/PVs are not removed automatically, finalizers can delay deletion, and hostpath data can remain on disk.
- With NFS, data is stored on the NFS server, so deleting PVCs/PVs only removes Kubernetes objects, not the files on the server.
- If Tempo or Grafana crash with permission errors on hostpath, use NFS or run as root (already set in monitoring values for local dev).
- KEDA needs the ScaledObject CRD before Helm renders ScaledObjects; otherwise HPAs will not appear.
