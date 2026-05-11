const assert = require('node:assert/strict');
const test = require('node:test');
const { processPendingDeployments, waitForRepository } = require('../src/worker');

const logger = {
  info() {},
  error() {},
};

test('worker moves pending deployments to running before completing them', async () => {
  let status = 'pending';
  let resumeWork;

  const repository = {
    async claimPending() {
      status = 'running';
      return [{ id: 1, status }];
    },
    async updateStatus(_id, nextStatus) {
      status = nextStatus;
      return { id: 1, status };
    },
  };

  const processing = processPendingDeployments({
    repository,
    sleepFn: () =>
      new Promise((resolve) => {
        resumeWork = resolve;
      }),
    random: () => 0.5,
    logger,
  });

  await Promise.resolve();
  assert.equal(status, 'running');

  resumeWork();
  const processed = await processing;

  assert.equal(processed.length, 1);
  assert.equal(status, 'succeeded');
});

test('worker can mark a processed deployment as failed', async () => {
  let status = 'pending';

  const repository = {
    async claimPending() {
      status = 'running';
      return [{ id: 1, status }];
    },
    async updateStatus(_id, nextStatus) {
      status = nextStatus;
      return { id: 1, status };
    },
  };

  await processPendingDeployments({
    repository,
    sleepFn: async () => {},
    random: () => 0.05,
    logger,
  });

  assert.equal(status, 'failed');
});

test('worker does not sleep or update when no deployments are pending', async () => {
  let updateCalls = 0;
  let sleepCalls = 0;

  const repository = {
    async claimPending() {
      return [];
    },
    async updateStatus() {
      updateCalls += 1;
    },
  };

  const processed = await processPendingDeployments({
    repository,
    sleepFn: async () => {
      sleepCalls += 1;
    },
    logger,
  });

  assert.deepEqual(processed, []);
  assert.equal(updateCalls, 0);
  assert.equal(sleepCalls, 0);
});

test('worker passes the configured processing delay to sleep', async () => {
  const sleepDurations = [];

  const repository = {
    async claimPending() {
      return [{ id: 1, status: 'running' }];
    },
    async updateStatus() {
      return { id: 1, status: 'succeeded' };
    },
  };

  await processPendingDeployments({
    repository,
    processingMs: 1234,
    sleepFn: async (ms) => {
      sleepDurations.push(ms);
    },
    random: () => 0.5,
    logger,
  });

  assert.deepEqual(sleepDurations, [1234]);
});

test('waitForRepository retries initialization until the repository is ready', async () => {
  let attempts = 0;
  const retryDelays = [];
  const loggedErrors = [];

  const repository = {
    async initialize() {
      attempts += 1;
      if (attempts < 3) {
        throw new Error('database unavailable');
      }
    },
  };

  await waitForRepository(repository, {
    retryMs: 25,
    sleepFn: async (ms) => {
      retryDelays.push(ms);
    },
    logger: {
      error(obj, message) {
        loggedErrors.push({ obj, message });
      },
    },
  });

  assert.equal(attempts, 3);
  assert.deepEqual(retryDelays, [25, 25]);
  assert.equal(loggedErrors.length, 2);
  assert.equal(loggedErrors[0].message, 'database unavailable, retrying worker initialization');
  assert.match(loggedErrors[0].obj.err.message, /database unavailable/);
});
