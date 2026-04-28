const { createApp } = require('./app');
const { createDeploymentsRepository } = require('./deploymentsRepository');
const { initializeDatabase, isDatabaseReady, pool } = require('./db');

const port = process.env.PORT || 3000;

async function startServer() {
  const app = createApp({
    deploymentsRepository: createDeploymentsRepository(pool),
    isDatabaseReady,
  });

  app.listen(port, () => {
    console.log(`Server running on port ${port}`);
  });

  initializeDatabase().catch((error) => {
    console.error('Database initialization failed', error);
  });
}

startServer().catch((error) => {
  console.error('Failed to start server', error);
  process.exit(1);
});
