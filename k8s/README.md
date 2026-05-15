# DevOps Banking - Local Kubernetes Setup with Minikube

This guide explains how to set up the `devops-banking` application locally using Minikube and HAProxy as the Ingress Controller.

## Prerequisites
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running.
- [Minikube](https://minikube.sigs.k8s.io/docs/start/) installed.
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed.
- [Helm](https://helm.sh/docs/intro/install/) installed (to install HAProxy).

## Step 1: Start a Multi-Node Minikube Cluster
Start your local Kubernetes cluster with 3 nodes (1 control-plane, 2 worker nodes):
```bash
minikube start --driver=docker --nodes=3
```
To verify the nodes are running:
```bash
kubectl get nodes
```

## Step 2: Install HAProxy Ingress via Helm
Instead of Minikube's built-in Nginx, we will install the HAProxy Ingress Controller using Helm.

```bash
# Add the HAProxy Helm repository
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo update

# Install the HAProxy Ingress Controller
helm install haproxy haproxytech/kubernetes-ingress \
  --namespace haproxy-controller \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

## Step 3: Deploy the Banking Application

Navigate to the `devops-banking/k8s` directory and apply the manifests in order.

### 1. Namespace & Secrets
```bash
kubectl apply -f namespace.yaml
kubectl apply -f secret.yaml
```

### 2. Databases & Dependencies
```bash
kubectl apply -f postgres.yaml
kubectl apply -f redis.yaml
kubectl apply -f kong-configmap.yaml
kubectl apply -f kong.yaml
```
*Wait a moment for PostgreSQL, Redis, and Kong to be in the `Running` state.*
```bash
kubectl get pods -n banking
```

### 3. Application Microservices
Deploy the backend and frontend microservices:
```bash
kubectl apply -f account-service.yaml
kubectl apply -f auth-service.yaml
kubectl apply -f notification-service.yaml
kubectl apply -f transfer-service.yaml
kubectl apply -f frontend.yaml
```

### 4. Apply Ingress
Apply the Ingress configuration:
```bash
kubectl apply -f ingress.yaml
```

## Step 4: Access the Application
Since we are using Minikube's built-in Ingress, we can use the `minikube tunnel` command to expose the ingress to your localhost.

Open a **new terminal** and run:
```bash
minikube tunnel
```
*Leave this terminal running!*

### Configure Local DNS (Windows)
To access the application via the custom domain `banking.local` specified in the Ingress, you need to map it to `127.0.0.1` in your Windows `hosts` file.

**Step 1: Open Notepad as Administrator**
- Press the Windows key and type `Notepad`.
- Right-click **Notepad** and select **Run as administrator**.

**Step 2: Open the hosts file**
- In Notepad, go to **File > Open...** (or press `Ctrl + O`).
- Paste the following path into the File name box and press Enter:
  `C:\Windows\System32\drivers\etc\hosts`
- *Note:* If you don't see any files, change the file filter dropdown in the bottom right from **Text Documents (*.txt)** to **All Files (*.*)**.

**Step 3: Add configuration**
- Scroll to the very bottom of the file and add this line:
  ```plaintext
  127.0.0.1       banking.local
  ```

**Step 4: Save and Verify**
- Press `Ctrl + S` to save the file.
- Open Command Prompt (`cmd`) and test the configuration by running:
  ```cmd
  ping banking.local
  ```
- If it returns `Reply from 127.0.0.1`, you are successfully configured!

Now, open your web browser and navigate to:
- **Frontend:** [http://banking.local/](http://banking.local/)
- **API (via Kong):** [http://banking.local/api/](http://banking.local/api/)

## Cleanup
To remove all deployments from your cluster:
```bash
kubectl delete namespace banking
minikube stop
```
