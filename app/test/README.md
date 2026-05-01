# Tests (`app/test/`)

Automated checks that **exercise the HTTP API** without requiring manual clicks or a deployed environment. They help CI confirm that changes to `app/` did not break expected behavior before a new container image is built.

## What lives here

- **app.test.js** — Covers the HTTP API using **supertest** against `createApp`, with a **fake in-memory repository** so tests do not need PostgreSQL. Includes health/readiness, listing and creating deployments, validation, status updates, and deletes.
- **worker.test.js** — Exercises the **background worker** logic from the sibling [`worker/`](../../worker/) package (`processPendingDeployments`): claiming pending work, moving statuses toward completion or failure, using stubbed repositories and timers. Keeps worker behavior aligned with how the API models deployment states.

## Running tests

From the `app/` directory:

```bash
npm test
```

This uses Node’s built-in test runner (see [package.json](../package.json)). Linting is separate: `npm run lint`.
