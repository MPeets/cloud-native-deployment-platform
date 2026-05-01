# Tests (`app/test/`)

Automated checks that **exercise the HTTP API** without requiring manual clicks or a deployed environment. They help CI confirm that changes to `app/` did not break expected behavior before a new container image is built.

## What lives here

- **app.test.js** — Covers the HTTP API using **supertest** against `createApp`, with a **fake in-memory repository** so tests do not need PostgreSQL. Includes health/readiness, listing and creating deployments, validation, status updates, and deletes.

## Running tests

From the `app/` directory:

```bash
npm test
```

This uses Node’s built-in test runner (see [package.json](../package.json)). Linting is separate: `npm run lint`.
