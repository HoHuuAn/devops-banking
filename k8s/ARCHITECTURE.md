# Architecture

This document describes the traffic flow and components within the `banking` namespace.

---

## Overview Diagram

```mermaid
flowchart TB
    subgraph external[" "]
        User[User / Browser]
    end

    subgraph ingress["Ingress (cluster)"]
        HAProxy[HAProxy Ingress]
    end

    subgraph banking["Namespace: banking"]
        subgraph front["Frontend"]
            FE[frontend:80]
        end

        subgraph gateway["API Gateway"]
            Kong[Kong :8000 proxy, :8001 admin]
            KongConfig[kong-config<br/>ConfigMap]
            Kong --> KongConfig
        end

        subgraph services["Microservices"]
            Auth[auth-service:8001]
            Acc[account-service:8002]
            Trans[transfer-service:8003]
            Notif[notification-service:8004]
        end

        subgraph data["Data (Deployment / StatefulSet)"]
            PG[(postgres:5432)]
            Redis[(redis:6379)]
        end

        subgraph storage["Storage"]
            PVC[(Persistent Volume Claim)]
        end

        Secret[banking-db-secret<br/>DATABASE_URL, REDIS_URL]
    end

    User -->|"/"| HAProxy
    User -->|"/api, /ws"| HAProxy
    HAProxy -->|path /| FE
    HAProxy -->|path /api, /ws| Kong

    Kong -->|/api/auth| Auth
    Kong -->|/api/account| Acc
    Kong -->|/api/transfer| Trans
    Kong -->|/api/notifications, /ws| Notif

    Auth --> Secret
    Acc --> Secret
    Trans --> Secret
    Notif --> Secret
    Secret --> PG
    Secret --> Redis

    PG --> PVC
    Redis --> PVC
```

---

## Traffic Flow

| Source           | Ingress path | Backend           | Notes                            |
|------------------|-------------|-------------------|----------------------------------|
| User             | `/`         | **frontend:80**   | Web UI (React/SPA)               |
| User / Frontend  | `/api/*`    | **Kong:8000**     | Kong routes to microservices     |
| User / Frontend  | `/ws`       | **Kong:8000**     | WebSocket → notification-service |

**Kong routing (configured in ConfigMap `kong-config`):**

| Path / route         | Upstream service        | Port |
|----------------------|-------------------------|------|
| `/api/auth`          | auth-service            | 8001 |
| `/api/account`       | account-service         | 8002 |
| `/api/transfer`      | transfer-service        | 8003 |
| `/api/notifications` | notification-service    | 8004 |
| `/ws`                | notification-service    | 8004 |

---

## Kubernetes Components

| Component            | Type          | Notes |
|----------------------|---------------|--------|
| **postgres**         | Deployment    | 1 replica, Headless Service, PVC for storage |
| **redis**            | Deployment    | 1 replica, Headless Service, PVC for storage |
| **kong**             | Deployment    | 1 replica, reads config from `kong-config` ConfigMap |
| **auth-service**     | Deployment    | 1 replica, reads DB/Redis URL from Secret |
| **account-service**  | Deployment    | 1 replica |
| **transfer-service** | Deployment    | 1 replica |
| **notification-service**| Deployment | 1 replica |
| **frontend**         | Deployment    | 1 replica, serves static files on port 80 |
| **Ingress**          | Ingress       | `ingressClassName: haproxy`, path-based routing |

---

## Dependencies

- **Postgres, Redis** → Must be running before application services start (services read DATABASE_URL, REDIS_URL from Secret).
- **Kong** → Requires ConfigMap `kong-config`; all upstream services (auth, account, transfer, notification) must have Services in the same namespace.
- **Ingress** → Cluster must have HAProxy Ingress Controller installed via Helm; backend Services must exist.

---

## Storage

- **Postgres**: Uses a Persistent Volume Claim (`postgres-pvc`) mounted at `/var/lib/postgresql/data`.
- **Redis**: Uses a Persistent Volume Claim (`redis-pvc`) mounted at `/data`.
- In a local environment (like Minikube), standard host-path provisioner is used automatically.

This diagram can be rendered using Mermaid-supported tools (GitHub, GitLab, VS Code with Mermaid extension, or https://mermaid.live).
