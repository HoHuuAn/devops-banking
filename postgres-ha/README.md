# Deploy Postgres HA and migrate data from old DB (Phase 5)

Guide: pull Bitnami PostgreSQL chart (HA/replication), add values file, deploy into a separate namespace, then migrate data from the old Postgres to the new Postgres.

---

## Step 1: Pull chart and create values file

```bash
# Add Bitnami repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Pull chart (optional – to see structure)
helm pull bitnami/postgresql --untar -d postgres-ha/
# Or install directly without pulling (use -f values)
```

Create file `values-postgres-ha.yaml` in the `postgres-ha/` folder (see content below).

---

## Step 2: Deploy Postgres HA (new, empty)

```bash
# Create postgres namespace (if not exists)
kubectl create namespace postgres

# Install Postgres HA (primary + 1 read replica)
helm upgrade -i postgres-ha bitnami/postgresql \
  -n postgres \
  -f postgres-ha/values-postgres-ha.yaml

# Wait for primary to be Ready
kubectl -n postgres get pods -l app.kubernetes.io/name=postgresql -w
# Ctrl+C when postgres-postgresql-primary-0 is Running, Ready 1/1
```

**Note**: The new Postgres is empty (no schema/data). DB `banking` and user `banking` are created via values.

---

## Step 3: Migrate data from old DB to new DB

### 3.1. Identify old DB and new DB addresses

- **Old DB (Phase 2)**: Usually in ns `banking`, Service `postgres`, port 5432. Pod: `postgres-0` (StatefulSet).
- **New DB (Phase 5)**: ns `postgres`, Service `postgres-postgresql-primary.postgres.svc.cluster.local` (Bitnami), port 5432.

### 3.2. Method 1: Manual dump and restore (kubectl exec + port-forward)

```bash
# Port-forward old DB to local (terminal 1)
kubectl -n banking port-forward svc/postgres 5432:5432

# Dump from old DB (terminal 2, use local psql/pg_dump or pod)
kubectl -n banking exec -it postgres-0 -- env PGPASSWORD=bankingpass \
  pg_dump -U banking -d banking -F c -f /tmp/banking.dump

# Copy dump to local (if using local pg_restore)
kubectl -n banking cp postgres-0:/tmp/banking.dump ./banking.dump

# Port-forward new DB
kubectl -n postgres port-forward svc/postgres-postgresql-primary 5433:5432

# Restore into new DB (local)
PGPASSWORD=bankingpass pg_restore -h localhost -p 5433 -U banking -d banking --clean --if-exists ./banking.dump
```

### 3.3. Method 2: Migrate Job in cluster (recommended)

Job runs in the cluster, connects directly to both DBs (no port-forward needed).

```bash
# Apply migrate Job
kubectl apply -f postgres-ha/migrate-db-job.yaml -n postgres
kubectl -n postgres get jobs
kubectl -n postgres logs -f job/postgres-migrate-from-banking
```

The Job will:
1. `pg_dump` from old DB (`postgres.banking.svc.cluster.local`)
2. `pg_restore` into new DB (`postgres-postgresql-primary.postgres.svc.cluster.local`)

**Note**: Need to modify `migrate-db-job.yaml` if old DB Service name/namespace is different (e.g. different release name).

### 3.4. Verify DB after migrating

After the migrate Job completes, verify the data was restored correctly:

```bash
# Get password
export POSTGRES_PASSWORD=$(kubectl get secret --namespace postgres postgres-postgresql -o jsonpath="{.data.password}" | base64 -d)

# Check list of tables in banking DB
kubectl run postgres-check --rm -it --restart=Never -n postgres \
  --image=bitnami/postgresql:latest \
  --env="PGPASSWORD=$POSTGRES_PASSWORD" \
  -- psql -h postgres-postgresql-primary -U banking -d banking -c "\dt"

# Check number of records (e.g., accounts, transfers tables)
kubectl run postgres-check --rm -it --restart=Never -n postgres \
  --image=bitnami/postgresql:latest \
  --env="PGPASSWORD=$POSTGRES_PASSWORD" \
  -- psql -h postgres-postgresql-primary -U banking -d banking -c "SELECT 'accounts' AS tbl, count(*) FROM accounts UNION ALL SELECT 'transfers', count(*) FROM transfers;"

# (Optional) Check replica is streaming from primary
kubectl run postgres-check --rm -it --restart=Never -n postgres \
  --image=bitnami/postgresql:latest \
  --env="PGPASSWORD=$POSTGRES_PASSWORD" \
  -- psql -h postgres-postgresql-primary -U postgres -d postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
```

- `\dt` lists tables – ensure schema exists.
- Compare `count(*)` with old DB to confirm record counts.
- `pg_stat_replication` shows replica with `state = streaming` is syncing.

---

## Step 4: Update Banking app to point to new DB

1. Create or update Secret `banking-db-secret` in ns `banking`:

```yaml
# DATABASE_URL points to new Postgres (primary)
DATABASE_URL=postgresql://banking:bankingpass@postgres-postgresql-primary.postgres.svc.cluster.local:5432/banking
```

2. Restart app deployments (auth-service, account-service, transfer-service, notification-service) to read new Secret:

```bash
kubectl -n banking rollout restart deployment auth-service account-service transfer-service notification-service
```

3. Disable old Postgres in banking-demo chart: set `postgres.enabled: false` in values.

---

## Step 5: Test and cutover

1. Login, transfer money, create notification – confirm app works with new DB.
2. When stable: delete or scale down old Postgres in ns `banking` (if it still exists).
3. (Optional) Run Phase 4 v2 migration (phone, account_number) if not run yet – Phase 4 DB migration Job can point to the new DB via `externalPostgres` or env.

---

## Summary of order

1. `helm repo add bitnami ...` + `helm repo update`
2. Create `values-postgres-ha.yaml`
3. `helm upgrade -i postgres-ha bitnami/postgresql -n postgres -f values-postgres-ha.yaml`
4. Migrate: Job `migrate-db-job.yaml` or manual pg_dump/pg_restore
5. **Verify DB**: `\dt`, `count(*)` of tables, `pg_stat_replication`
6. Update Secret + restart app, disable old Postgres
