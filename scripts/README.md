# Load Testing & KEDA Autoscaling Validation

This folder contains a unified Python load testing script designed to simulate heavy traffic against the `devops-banking` microservices. The primary goal is to validate that **KEDA** (Kubernetes Event-driven Autoscaling) correctly scales your pods up when Prometheus detects high RPS, and scales them back down during cooldown periods.

## Prerequisites
1. Ensure your Kubernetes cluster is running and the Helm chart is deployed with `keda.enabled=true`.
2. Install Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```

## Usage

The `load_test.py` script automatically seeds temporary users into the database, extracts their access tokens, and then uses asynchronous workers to spam the endpoints.

### Basic Syntax
```bash
python load_test.py --scenario <auth|account|transfer|all> --rps <target-rps> --duration <seconds>
```

### Examples

**1. Test Auth Service Scale-Up:**
Force 50 Requests Per Second (RPS) onto the `/api/auth/me` endpoint for 2 minutes.
```bash
python load_test.py --scenario auth --rps 50 --duration 120 --base-url http://banking.local
```

**2. Test Transfer Service Scale-Up:**
Simulate 30 RPS of random fund transfers between 50 pre-generated users.
```bash
python load_test.py --scenario transfer --users 50 --rps 30 --duration 180 --base-url http://banking.local
```

**3. Chaos / Full Cluster Scale-Up:**
Hit all endpoints concurrently to trigger scaling across `auth`, `account`, and `transfer` services.
```bash
python load_test.py --scenario all --users 100 --rps 100 --duration 180 --workers 100 --base-url http://banking.local
```

## How to Verify Scaling

Open a separate terminal and watch your pods in real-time. As the load test script runs and hits the activation threshold (e.g. >5 RPS per pod), you should see KEDA spin up new replicas:
```bash
kubectl get pods -n banking -w
```

Alternatively, watch the KEDA `HorizontalPodAutoscaler` metrics:
```bash
kubectl get hpa -n banking -w
```

When the load test finishes, KEDA will observe the drop in traffic. After the `cooldownPeriod` (default 120 seconds), you will see Kubernetes automatically terminate the extra pods, returning the system to its `minReplicaCount`.