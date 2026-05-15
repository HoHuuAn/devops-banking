# Monitoring Setup for DevOps Banking

This directory contains the Helm configurations to spin up the entire observability stack (Prometheus, Grafana, Tempo, OpenTelemetry Collector) for the banking application.

## Prerequisites
- The banking application should be deployed (see the devops-banking/helm-chart folder).
- Your hosts file must contain the following entries pointing to your ingress IP (e.g. 127.0.0.1 for Minikube tunnel):
  `	ext
  127.0.0.1 banking.local
  127.0.0.1 grafana.banking.local
  127.0.0.1 prometheus.banking.local
  `

## 1. Add Helm Repositories
You need the official Helm repositories for the monitoring components:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
```

## 2. Deploy Prometheus Stack & Grafana
We deploy the kube-prometheus-stack which automatically provisions Prometheus, Grafana, and Alertmanager. We pass our custom values-kube-prometheus-stack.yaml which enables ingress for Grafana and Prometheus, sets up Tempo as a datasource, and configures scraping for our banking microservices.

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f ./devops-banking/helm-monitoring/values-kube-prometheus-stack.yaml
```

*Note: The default Grafana login is admin / admin.*

## 3. Deploy Tempo & OpenTelemetry Collector (Tracing)
We use **Grafana Tempo** as our tracing backend, removing the need for a separate Jaeger UI. Our microservices send OTLP spans to the **OpenTelemetry Collector**, which processes them and forwards them to Tempo.

First, install Tempo:
```bash
helm install tempo grafana/tempo \
  --namespace monitoring \
  -f ./devops-banking/helm-monitoring/values-tempo.yaml
```

Then, install the OpenTelemetry Collector:
```bash
helm install opentelemetry-collector open-telemetry/opentelemetry-collector \
  --namespace monitoring \
  -f ./devops-banking/helm-monitoring/values-otel-collector.yaml
```

*Note: Traces can now be explored natively inside Grafana! Just go to **Explore -> Tempo**.*

## 4. Exporters (Optional)
If you want deep database metrics, apply the Exporters for Postgres and Redis:
```bash
kubectl apply -f ./devops-banking/helm-monitoring/postgres-exporter.yaml
kubectl apply -f ./devops-banking/helm-monitoring/redis-exporter.yaml
```

## Accessing the Dashboards
Make sure minikube tunnel is running in a separate terminal. You can now access the monitoring tools via:

- **Grafana**: [http://grafana.banking.local](http://grafana.banking.local)
- **Prometheus**: [http://prometheus.banking.local](http://prometheus.banking.local)
- **Tracing**: Available natively inside Grafana under the "Explore" menu using the Tempo datasource.
