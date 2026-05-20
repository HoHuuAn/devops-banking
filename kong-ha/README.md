# Deploy Kong HA with Postgres

Guide to deploy Kong HA using Postgres as the datastore, config from a declarative file imported into the DB. Kong runs in its own namespace `kong`, connecting to the existing Postgres HA in ns `postgres`.

---

## Prerequisites

- **Postgres HA** is deployed in ns `postgres` (see `postgres-ha/README.md`)
- **Banking app** is running in ns `banking` (auth-service, account-service, transfer-service, notification-service)

---

## Step 1: Create Kong database on Postgres

Run the Job to create the `kong` DB and `kong` user on the existing Postgres HA.

```bash
# Edit kong-db-init-job.yaml if the Postgres release is different:
# - postgres-postgresql-primary  → postgres-ha-postgresql-primary (if release = postgres-ha)
# - Secret postgres-postgresql   → postgres-ha-postgresql

kubectl apply -f kong-ha/kong-db-init-job.yaml -n postgres
kubectl -n postgres get jobs
kubectl -n postgres logs job/kong-db-init
```

Ensure the Job completes successfully (`COMPLETIONS 1/1`).

---

## Step 2: Add Helm repo and deploy Kong

```bash
helm repo add kong https://charts.konghq.com
helm repo update

kubectl create namespace kong

# Edit values-kong-ha.yaml if needed:
# - env.pg_host: postgres-ha-postgresql-primary.postgres... (if release = postgres-ha)
# - env.pg_password: match kongpass in kong-db-init-job

helm upgrade -i kong kong/kong -n kong -f kong-ha/values-kong-ha.yaml

# Wait for Kong to be Ready
kubectl -n kong get pods -l app.kubernetes.io/name=kong -w
# Ctrl+C when all are Running, Ready 1/1
```

Kong will run migrations (create tables) for the first time. Pods `kong-kong-pre-upgrade-migrations` and `kong-kong-post-upgrade-migrations` must be Completed.

---

## Step 3: Import declarative config into Kong DB

After Kong is running and migrations are done, import routes/services/plugins from the file.

```bash
# Method 1: Use the existing ConfigMap in kong-import-job.yaml
kubectl apply -f kong-ha/kong-import-job.yaml -n kong

# Method 2: Create ConfigMap from kong-declarative.yaml file (if edited)
kubectl create configmap kong-declarative-config \
  --from-file=kong.yml=kong-ha/kong-declarative.yaml -n kong --dry-run=client -o yaml | kubectl apply -f -
# Then apply the Job (remove ConfigMap part in kong-import-job.yaml if created beforehand)

kubectl -n kong get jobs
kubectl -n kong logs job/kong-config-import -f
```

Ensure the Job completes. If you re-apply, you might encounter a duplicate error – delete the old Job and re-apply, or use `kong config db_import` with the `--no-overwrite` flag depending on the version.

---

## Step 4: Update Ingress to point to new Kong

Ingress in ns `banking` (or the ns containing Ingress) needs the backend pointing to Kong in ns `kong`:

```yaml
# backend /api and /ws
serviceName: kong-kong-proxy   # or the Service name created by the chart
servicePort: 8000
# If Ingress doesn't support cross-namespace, create an ExternalName Service:
# kind: Service
# spec:
#   type: ExternalName
#   externalName: kong-kong-proxy.kong.svc.cluster.local
```

Service name: `kong-kong-proxy` (release `kong`, chart creates suffix `-kong-proxy`). Check:

```bash
kubectl -n kong get svc
```

If using HAProxy Ingress or another Ingress requiring backends in the same namespace, create a Service in ns `banking`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kong-proxy
  namespace: banking
spec:
  type: ExternalName
  externalName: kong-kong-proxy.kong.svc.cluster.local
```

Then Ingress points to `serviceName: kong-proxy`, `servicePort: 8000`. Some Ingress controllers don't support ExternalName – you may need to use an annotation or manual endpoint.

---

## Step 5: Disable old Kong (Phase 2)

In the `banking-demo` chart (Phase 2), disable Kong:

```yaml
# values banking-demo
kong:
  enabled: false
```

Restart or upgrade the banking-demo release.

---

## Step 6: Test Kong HA

```bash
# Kong Pods
kubectl -n kong get pods -l app.kubernetes.io/name=kong

# Services
kubectl -n kong get svc

# Test proxy (from inside cluster)
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -- \
  curl -s -o /dev/null -w "%{http_code}" http://kong-kong-proxy.kong.svc.cluster.local:8000/api/auth/health

# Admin API (list services)
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -- \
  curl -s http://kong-kong-admin.kong.svc.cluster.local:8001/services | head -20
```

---

## Summary of order

1. Job `kong-db-init` – create DB `kong` + user on Postgres
2. `helm upgrade -i kong kong/kong -n kong -f values-kong-ha.yaml`
3. Job `kong-config-import` – import declarative config into DB
4. Update Ingress backend → new Kong (ns `kong`)
5. Disable old Kong in banking-demo
6. Test routes, login, transfer

---

## Kong Manager — call Admin API via ClusterIP

Kong Manager (browser) needs to call the Admin API. Instead of exposing the Admin API separately, use the **Ingress proxy** on the same host:

1. **Ingress** `kong-manager-ingress.yaml`: route `kong-manager.local/admin-api` → `kong-kong-admin:8001` (ClusterIP), path rewrite `/admin-api/services` → `/services`
2. **Kong env** `admin_gui_api_url`: `http://kong-manager.local/admin-api` (already added in values-kong-ha.yaml)

```bash
kubectl apply -f kong-manager-ingress.yaml -n kong
helm upgrade kong kong/kong -n kong -f values-kong-ha.yaml  # apply admin_gui_api_url
```

Add `kong-manager.local` to DNS/hosts pointing to Ingress IP. Access http://kong-manager.local → Kong Manager will call Admin API via path `/admin-api` (Ingress proxy to ClusterIP).

---

## Notes

- **pg_host / Secret**: If using Postgres release `postgres-ha`, modify `pg_host` and Secret name in the corresponding Job.
- **Backends FQDN**: The `kong-declarative.yaml` file uses `*.banking.svc.cluster.local` because Kong is in ns `kong`, app in ns `banking`.
- **CORS**: Adjust `origins` in declarative config if the domain is different.
- **decK** (instead of db_import): You can use `deck sync -s kong.yml --kong-addr http://kong-kong-admin.kong:8001` from image `kong/deck` if frequent syncing is needed.
