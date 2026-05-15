# DevOps Banking - Helm Chart

This is the Helm chart for deploying the `devops-banking` microservices architecture (including Postgres, Redis, Kong Gateway, Frontend, and multiple backend microservices).

## Project Structure

This Helm chart is structured with all templates in `templates/` and configuration values grouped by service under `charts/<service-name>/values.yaml`. 

*Note: While a standard Helm chart usually places all default values inside a single `values.yaml` at the root, this chart was designed for GitOps tools like ArgoCD which merge multiple `values.yaml` files. To use it with standard Helm CLI, you must pass these files individually, or you can merge them into the root `values.yaml`.*

## Prerequisites
- [Minikube](https://minikube.sigs.k8s.io/docs/start/) or a running Kubernetes cluster.
- [Helm 3](https://helm.sh/docs/intro/install/) installed.

## Step-by-Step Installation

### 1. Create a Namespace
Create a dedicated namespace for the application to isolate resources:
```bash
kubectl create namespace banking
```

### 2. Install HAProxy Ingress Controller
Because this chart uses HAProxy for Ingress, you need to install the HAProxy Ingress Controller in your cluster before deploying the app:
```bash
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo update
helm install haproxy haproxytech/kubernetes-ingress \
  --namespace haproxy-controller \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

### 3. Install the Helm Chart
Run the following Helm command from the `devops-banking` root directory. Because the configurations are split into different files inside the `charts/` directory, you must pass them to `helm install` using multiple `-f` flags.

```bash
helm install banking ./helm-chart
  --namespace banking
  -f ./helm-chart/charts/common/values.yaml
  -f ./helm-chart/charts/postgres/values.yaml
  -f ./helm-chart/charts/redis/values.yaml
  -f ./helm-chart/charts/kong/values.yaml
  -f ./helm-chart/charts/account-service/values.yaml
  -f ./helm-chart/charts/auth-service/values.yaml
  -f ./helm-chart/charts/notification-service/values.yaml
  -f ./helm-chart/charts/transfer-service/values.yaml
  -f ./helm-chart/charts/frontend/values.yaml
```

### 4. Verify Deployment
Check the status of your pods to ensure everything is running:
```bash
kubectl get pods -n banking
```

### 5. Expose and Access the Application
Since we are using HAProxy as a `LoadBalancer` inside Minikube, you must run the following command to expose it:
```bash
minikube tunnel
```
*(Leave this terminal running!)*

Next, map the local domain by adding this line to your `C:\Windows\System32\drivers\etc\hosts` (Windows) or `/etc/hosts` (Linux/Mac) file:
```
127.0.0.1 banking.local
```

Now, you can access your application at `http://banking.local/` and the API at `http://banking.local/api/`.

## Upgrading the Chart
If you make changes to the configurations or templates, you can apply them by running:
```bash
helm upgrade banking ./helm-chart \
  --namespace banking \
  -f ./helm-chart/charts/common/values.yaml \
  -f ./helm-chart/charts/postgres/values.yaml \
  ... (include all value files again)
```

## Uninstalling the Chart
To remove the application and all associated resources:
```bash
helm uninstall banking --namespace banking
kubectl delete pvc --all -n banking
```
