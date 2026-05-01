# Local Docker setup (`docker/`)

This folder holds a **Docker Compose** file so you can run the main pieces of the platform on your machine **without** provisioning cloud infrastructure. Compose ties together containers, networks, and startup order; you only need Docker Desktop (or another Compose-capable engine) installed.

## What runs here

| Piece | Purpose |
|-------|---------|
| **db** | PostgreSQL database where deployment records live. Includes a health check so other services wait until the database accepts connections. |
| **migrate** | One-off step: applies SQL migrations from the repo before the API and worker start, so the schema matches what the code expects. |
| **api** | The Node.js HTTP API built from [`../app/`](../app/README.md). Exposes port **3000** on your host (mapped from the container). |
| **worker** | Background process built from [`../worker/`](../worker/) that advances deployment statuses using the same database. |

The API’s default connection string points at the hostname **`db`** inside Compose; that matches the service name in [`docker-compose.yml`](./docker-compose.yml).

## Typical use

From the **repository root**:

```bash
docker compose -f docker/docker-compose.yml up --build
```

Then open **http://localhost:3000** (for example the root path or `/health`) to confirm the API is up.

Stopping: `Ctrl+C` in that terminal, or `docker compose -f docker/docker-compose.yml down` from another shell.

## How this relates to production

Production deploys use the same **container images** idea (see the [`app`](../app/Dockerfile) and [`worker`](../worker/Dockerfile) Dockerfiles), but orchestration, secrets, and networking are handled by your cloud setup (for example ECS and Terraform elsewhere in this repo). This Compose stack is mainly for **local development and demos**.
