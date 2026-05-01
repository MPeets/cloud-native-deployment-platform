const { Pool } = require('pg');

const connectionString =
  process.env.DATABASE_URL ||
  'postgres://postgres:postgres@db:5432/cloud-native-deployment-platform';

const pool = new Pool({ connectionString });

async function checkConnection() {
  await pool.query('SELECT 1');
}

async function isDatabaseReady() {
  await checkConnection();
}

module.exports = {
  checkConnection,
  isDatabaseReady,
  pool,
};
