# Application (`app/`)

This folder holds the small HTTP API that the rest of the repository builds, containerizes, and deploys. In production it is the public entry point: the load balancer sends traffic here, while the worker runs as a separate background service.

## What it does

- Exposes a REST-style API for deployment records: service, version, and current status.
- Stores those records in PostgreSQL so data survives restarts.
- Offers health and readiness endpoints so automated checks can tell whether the process is up and whether the database is reachable.

A separate background worker in [`worker/`](../worker/) advances records from `pending` toward `succeeded` or `failed`. The API and worker are separate processes that share the same database.

## Running locally

- Dependencies: Node.js and npm; see [`package.json`](./package.json).
- Database: PostgreSQL. By default the app uses a connection string for a host named `db`, which matches Docker Compose. Override it with `DATABASE_URL`.
- Port: defaults to `3000`; override with `PORT`.

Typical commands from this directory:

```bash
npm install
npm test
npm run lint
node src/index.js
```
