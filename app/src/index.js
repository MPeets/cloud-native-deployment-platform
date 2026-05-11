require('./tracing');

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

  app.listen(port, () => {
    logger.info({ port }, 'server listening');
  });

  checkConnection().catch((error) => {
    logger.error({ err: error }, 'database connection check failed');
  });
}

startServer().catch((error) => {
  logger.error({ err: error }, 'failed to start server');
  process.exit(1);
});
