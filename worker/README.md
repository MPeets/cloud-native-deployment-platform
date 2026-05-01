# Worker (`worker/`)

A small **Node.js** process that runs **beside** the API and uses the **same PostgreSQL database**. It looks for deployment rows in **`pending`**, marks them **`running`**, waits a short simulated “processing” time, then sets them to **`succeeded`** or **`failed`** (configurable randomness). That gives the platform a believable **async lifecycle** for demos and tests without a real deploy engine.

- **Configured with env:** `DATABASE_URL`, optional `WORKER_POLL_INTERVAL_MS`, `WORKER_PROCESSING_MS`, `WORKER_FAILURE_RATE`.
- **Packaged** with [`Dockerfile`](./Dockerfile); Compose starts it after migrations—see [`docker/README.md`](../docker/README.md).
- **API** creates `pending` rows; this worker advances them—see [`app/README.md`](../app/README.md).

Behavior is covered from the app repo by tests that import this module (under [`app/test/`](../app/test/README.md)).
