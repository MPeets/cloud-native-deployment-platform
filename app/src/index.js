const { createApp } = require('./app');
const { createDeploymentsRepository } = require('./deploymentsRepository');
const { checkConnection, isDatabaseReady, pool } = require('./db');

const port = process.env.PORT || 3000;

async function startServer() {
  const app = createApp({
    deploymentsRepository: createDeploymentsRepository(pool),
    isDatabaseReady,
  });

  app.listen(port, () => {
    console.log(`Server running on port ${port}`);
  });

  checkConnection().catch((error) => {
    console.error('Database connection check failed', error);
  });
}

startServer().catch((error) => {
  console.error('Failed to start server', error);
  process.exit(1);
});
