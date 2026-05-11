# Local Docker setup (`docker/`)

This folder holds the Docker Compose file for running the main pieces of the platform on your machine without provisioning cloud infrastructure. Compose handles containers, networks, and startup order. You need Docker Desktop or another Compose-capable engine.

## What runs here

| Piece | Purpose |
|-------|---------|
| `db` | PostgreSQL database where deployment records live. Includes a health check so other services wait until the database accepts connections. |
| `migrate` | One-off step that applies SQL migrations before the API and worker start, so the schema matches the code. |
| `api` | Node.js HTTP API built from [`../app/`](../app/README.md). Exposes port `3000` on your host. |
| `worker` | Background process built from [`../worker/`](../worker/) that advances deployment statuses using the same database. |

The API's default connection string points at the hostname `db` inside Compose. That matches the service name in [`docker-compose.yml`](./docker-compose.yml).

## Typical use

From the repository root:

```bash
docker compose -f docker/docker-compose.yml up --build
```

Then open `http://localhost:3000`, either the root path or `/health`, to confirm the API is up.

Stopping: `Ctrl+C` in that terminal, or `docker compose -f docker/docker-compose.yml down` from another shell.

## How this relates to production

Production deploys use the same container image idea; see the [`app`](../app/Dockerfile) and [`worker`](../worker/Dockerfile) Dockerfiles. Orchestration, secrets, and networking move to the cloud setup, mainly ECS and Terraform in this repo. This Compose stack is for local development and demos.
