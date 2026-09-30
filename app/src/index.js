const { shutdownTracing } = require('./tracing');
const { setTimeout } = require('node:timers');

const { createApp } = require('./app');
const { createDeploymentsRepository } = require('./deploymentsRepository');
const { checkConnection, isDatabaseReady, pool } = require('./db');
const logger = require('./logger');

const port = process.env.PORT || 3000;

async function startServer() {
  const app = createApp({
    deploymentsRepository: createDeploymentsRepository(pool),
    isDatabaseReady,
  });

  const server = app.listen(port, () => {
    logger.info({ port }, 'server listening');
  });

  checkConnection().catch((error) => {
    logger.error({ err: error }, 'database connection check failed');
  });

  let shuttingDown = false;

  function shutdown() {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;

    const timer = setTimeout(() => {
      logger.error('shutdown timed out');
      process.exit(1);
    }, 10_000);
    timer.unref();

    server.close(async () => {
      try {
        await pool.end();
        logger.info('shutdown complete');
        await shutdownTracing();
        process.exit(0);
      } catch (error) {
        logger.error({ err: error }, 'shutdown failed');
        process.exit(1);
      }
    });
  }

  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

startServer().catch((error) => {
  logger.error({ err: error }, 'failed to start server');
  process.exit(1);
});
