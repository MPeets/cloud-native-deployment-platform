# Worker (`worker/`)

A small Node.js process that runs beside the API and uses the same PostgreSQL database. It looks for deployment rows in `pending`, marks them `running`, waits a short simulated processing time, then sets them to `succeeded` or `failed`. The failure rate is configurable. That gives the platform a believable async lifecycle for demos and tests without a real deploy engine.

- Configure it with `DATABASE_URL` and optional `WORKER_POLL_INTERVAL_MS`, `WORKER_PROCESSING_MS`, and `WORKER_FAILURE_RATE`.
- Package it with [`Dockerfile`](./Dockerfile). Compose starts it after migrations; see [`docker/README.md`](../docker/README.md).
- The API creates `pending` rows; this worker advances them. See [`app/README.md`](../app/README.md).

Behavior is covered by this package's own Node test suite under [`test/`](./test/). Run it from `worker/` with:

```bash
npm test
```
