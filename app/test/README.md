# Tests (`app/test/`)

Automated checks for the HTTP API, without manual clicks or a deployed environment. CI uses them to catch behavior changes before building a new container image.

## What lives here

- `app.test.js` covers the HTTP API using `supertest` against `createApp`, with a fake in-memory repository so tests do not need PostgreSQL. It includes health/readiness, listing and creating deployments, validation, status updates, and deletes.

## Running tests

From the `app/` directory:

```bash
npm test
```

This uses Node's built-in test runner; see [`package.json`](../package.json). Linting is separate: `npm run lint`.
