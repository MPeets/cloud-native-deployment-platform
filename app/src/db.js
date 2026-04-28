const { Pool } = require('pg');

const connectionString =
  process.env.DATABASE_URL ||
  'postgres://postgres:postgres@db:5432/cloud-native-deployment-platform';

const pool = new Pool({ connectionString });

async function initializeDatabase() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS deployments (
      id SERIAL PRIMARY KEY,
      service VARCHAR(100) NOT NULL,
      version VARCHAR(50) NOT NULL,
      status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'running', 'succeeded', 'failed')),
      deployed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
}

async function isDatabaseReady() {
  await initializeDatabase();
  await pool.query('SELECT 1');
}

module.exports = {
  initializeDatabase,
  isDatabaseReady,
  pool,
};
