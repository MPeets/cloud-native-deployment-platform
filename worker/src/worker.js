const DEFAULT_DATABASE_URL =
  process.env.DATABASE_URL ||
  'postgres://postgres:postgres@db:5432/cloud-native-deployment-platform';
const DEFAULT_POLL_INTERVAL_MS = Number(process.env.WORKER_POLL_INTERVAL_MS || 5000);
const DEFAULT_PROCESSING_MS = Number(process.env.WORKER_PROCESSING_MS || 3000);
const DEFAULT_FAILURE_RATE = Number(process.env.WORKER_FAILURE_RATE || 0.1);

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function mapDeployment(row) {
  return {
    id: row.id,
    service: row.service,
    version: row.version,
    status: row.status,
    deployed_at: row.deployed_at,
    updated_at: row.updated_at,
  };
}

function createWorkerRepository(pool) {
  return {
    async initialize() {
      await pool.query('SELECT 1');
    },

    async claimPending(limit = 1) {
      const { rows } = await pool.query(
        `WITH claimed AS (
           SELECT id
           FROM deployments
           WHERE status = 'pending'
           ORDER BY deployed_at ASC
           LIMIT $1
           FOR UPDATE SKIP LOCKED
         )
         UPDATE deployments
         SET status = 'running', updated_at = NOW()
         FROM claimed
         WHERE deployments.id = claimed.id
         RETURNING deployments.*`,
        [limit],
      );

      return rows.map(mapDeployment);
    },

    async updateStatus(id, status) {
      const { rows } = await pool.query(
        `UPDATE deployments
         SET status = $2, updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [id, status],
      );

      return rows[0] ? mapDeployment(rows[0]) : null;
    },
  };
}

async function processPendingDeployments({
  repository,
  processingMs = DEFAULT_PROCESSING_MS,
  failureRate = DEFAULT_FAILURE_RATE,
  random = Math.random,
  sleepFn = sleep,
  logger = console,
} = {}) {
  const deployments = await repository.claimPending();

  for (const deployment of deployments) {
    logger.log(`Deployment ${deployment.id} is running`);
    await sleepFn(processingMs);

    const nextStatus = random() < failureRate ? 'failed' : 'succeeded';
    await repository.updateStatus(deployment.id, nextStatus);
    logger.log(`Deployment ${deployment.id} ${nextStatus}`);
  }

  return deployments;
}

async function waitForRepository(repository, { retryMs = 1000, sleepFn = sleep, logger = console } = {}) {
  while (true) {
    try {
      await repository.initialize();
      return;
    } catch (error) {
      logger.error('Database unavailable, retrying worker initialization', error);
      await sleepFn(retryMs);
    }
  }
}

function createDeploymentWorker({
  repository,
  pollIntervalMs = DEFAULT_POLL_INTERVAL_MS,
  processingMs = DEFAULT_PROCESSING_MS,
  failureRate = DEFAULT_FAILURE_RATE,
  random = Math.random,
  sleepFn = sleep,
  logger = console,
} = {}) {
  let running = false;
  let loopPromise = null;

  async function processOnce() {
    return processPendingDeployments({
      repository,
      processingMs,
      failureRate,
      random,
      sleepFn,
      logger,
    });
  }

  async function loop() {
    while (running) {
      try {
        await processOnce();
      } catch (error) {
        logger.error('Worker failed to process deployments', error);
      }

      if (running) {
        await sleepFn(pollIntervalMs);
      }
    }
  }

  return {
    start() {
      if (!running) {
        running = true;
        loopPromise = loop();
      }

      return loopPromise;
    },

    async stop() {
      running = false;
      await loopPromise;
    },

    processOnce,
  };
}

async function main() {
  const { Pool } = require('pg');
  const pool = new Pool({ connectionString: DEFAULT_DATABASE_URL });
  const repository = createWorkerRepository(pool);
  const worker = createDeploymentWorker({ repository });

  await waitForRepository(repository);
  worker.start();

  process.on('SIGINT', async () => {
    await worker.stop();
    await pool.end();
    process.exit(0);
  });

  process.on('SIGTERM', async () => {
    await worker.stop();
    await pool.end();
    process.exit(0);
  });
}

if (require.main === module) {
  main().catch((error) => {
    console.error('Worker failed to start', error);
    process.exit(1);
  });
}

module.exports = {
  createDeploymentWorker,
  createWorkerRepository,
  processPendingDeployments,
  sleep,
  waitForRepository,
};