const assert = require('node:assert/strict');
const test = require('node:test');
const { processPendingDeployments } = require('../src/worker');

const logger = {
  log() {},
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
