# Kubernetes Local Deployment Troubleshooting Guide

This document captures common issues encountered when setting up the `devops-banking` application locally via Minikube and how to resolve them.

---

## 1. Localhost/Ingress Not Accessible (minikube tunnel)

**Symptom:**
You run `minikube tunnel` and see "Tunnel successfully started", but navigating to `http://127.0.0.1/` hangs or returns an empty response.

**Cause:**
By default, the Helm chart for HAProxy might install the ingress controller as a `NodePort` service. However, `minikube tunnel` is specifically designed to route traffic from your host's localhost to Kubernetes Services of type `LoadBalancer`. If the ingress controller isn't a LoadBalancer, the tunnel won't pick it up.

**Solution:**
Ensure that HAProxy is installed or upgraded with `controller.service.type=LoadBalancer`.

```bash
helm upgrade haproxy haproxytech/kubernetes-ingress \
  --namespace haproxy-controller \
  --set controller.service.type=LoadBalancer
```

---

## 2. Pods Crashing with "Operation not permitted" (chown/chmod)

**Symptom:**
Pods like `postgres`, `redis`, or `frontend` (Nginx) enter a `CrashLoopBackOff` state. When inspecting their logs, you see errors like:
- `chmod: changing permissions of '/var/run/postgresql': Operation not permitted`
- `chown: changing ownership of '/var/lib/postgresql/data': Operation not permitted`
- `nginx: [emerg] chown("/var/cache/nginx/client_temp", 101) failed (1: Operation not permitted)`

**Cause:**
This occurs when the pod's `securityContext` is configured to drop all privileges (`drop: ["ALL"]`). While excellent for security, the official Docker entrypoint scripts for these databases and web servers often start as `root` to initialize directories, fix file ownership, and then step down to a non-root user (e.g., using `su` or `gosu`). Dropping all capabilities prevents these setup scripts from executing properly.

**Solution:**
Add back the specific Linux capabilities required for these initializations in the deployment manifests (`postgres.yaml`, `redis.yaml`, `frontend.yaml`):

```yaml
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
              add: ["CHOWN", "SETUID", "SETGID", "FOWNER", "DAC_OVERRIDE"]
```
*   **`CHOWN` / `FOWNER` / `DAC_OVERRIDE`**: Allows the script to alter directory/file ownership and permissions.
*   **`SETUID` / `SETGID`**: Allows the container to securely switch from the root user to the `postgres`, `redis`, or `nginx` user before starting the main application.

---

## 3. Kong Pods Failing Readiness Probes / OOMKilled / 502 Bad Gateway

**Symptom:**
- Multiple Kong pods get stuck in a rolling update.
- `kubectl describe pod` shows the readiness probe timing out: `Readiness probe failed: command timed out: "kong health" timed out`.
- `kubectl logs` show worker processes exiting unexpectedly: `worker process exited on signal 9` (Signal 9 means OOMKilled).
- Making API requests through the ingress returns `502 Bad Gateway`.

**Cause:**
Kong (which runs on LuaJIT and NGINX) automatically spawns one worker process for every CPU core available on the host machine. On multi-core developer machines, this causes a massive spike in memory usage upon startup. If the memory `limits` defined in the Kubernetes manifest (e.g., `256Mi` or `512Mi`) are too low, Kubernetes kills the container for exceeding its memory bounds. Because it crashes, the readiness probes timeout, causing rollouts to stall.

**Solution:**
1. **Constrain Kong's internal resource usage:** Explicitly set environment variables to limit the number of worker processes and cache size.
2. **Increase the Kubernetes resource limits:** Give the pod more memory overhead.
3. **Optimize the Readiness Probe:** Use a lightweight HTTP check instead of the heavy `kong health` CLI command.

Update your `kong.yaml` to include:

```yaml
          env:
            - name: KONG_DATABASE
              value: "off"
            - name: KONG_NGINX_WORKER_PROCESSES
              value: "1"        # Forces Kong to use only 1 worker process
            - name: KONG_MEM_CACHE_SIZE
              value: "128m"     # Caps the internal memory cache
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "1Gi"     # Give ample overhead for LuaJIT
              cpu: "1000m"
          readinessProbe:
            httpGet:            # Use HTTP probe instead of CLI 'exec'
              path: /status
              port: 8001
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 5
```