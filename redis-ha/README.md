# Deploy Redis HA and migrate data (Phase 5)

Deploy Bitnami Redis HA (master + replica), migrate session/presence from the old Redis to the new Redis

---

## Step 1: Deploy Redis HA

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

kubectl create namespace redis

helm upgrade -i redis bitnami/redis -n redis -f redis-ha/values-redis-ha.yaml
kubectl -n redis get pods -w
```

---

## Step 2: Migrate data from old Redis

Run this when Redis HA is Ready and the old Redis (ns banking) is still running:

```bash
kubectl apply -f redis-ha/migrate-redis-job.yaml -n redis
kubectl -n redis logs -f job/redis-migrate-from-banking
```

Modify `OLD_HOST` in the Job if Phase 2 used a different name (e.g. `redis` when in the same ns).

---

## Step 3: Update app

Secret `banking-db-secret` requires `REDIS_URL`:

```
redis://redis.redis.svc.cluster.local:6379/0
```