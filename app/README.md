# Application (`app/`)

This folder holds a small **HTTP API** that the rest of the repository builds, containers, and deploys. It is the public entry point in production: load balancers and orchestration forward traffic here, while the sibling worker runs as a separate background service.

## What it does (plain language)

- Exposes a REST-style API for **deployment records** (which service, which version, current status).
- Stores those records in **PostgreSQL** so data survives restarts.
- Offers **health** and **readiness** endpoints so automated checks can tell whether the process is up and whether the database is reachable.

A separate **background worker** in the repo root [`worker/`](../worker/) folder can advance those records through statuses (for example from pending toward succeeded or failed). The API and worker are separate processes that share the same database idea.


## Running locally (overview)

- **Dependencies:** Node.js and npm (see [package.json](./package.json)).
- **Database:** The app expects PostgreSQL. By default it uses a connection string aimed at a host named `db` (typical in Docker Compose); you can override everything with the `DATABASE_URL` environment variable.
- **Port:** Defaults to `3000`; override with `PORT` if needed.

Typical commands from this directory:

```bash
npm install
npm test
npm run lint
node src/index.js
```
