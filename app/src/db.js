const { Pool } = require('pg');
const { poolOptions } = require('./rdsSsl');
const logger = require('./logger');

const connectionString =
  process.env.DATABASE_URL ||
  'postgres://postgres:postgres@db:5432/cloud-native-deployment-platform';

const pool = new Pool(poolOptions(connectionString));

pool.on('error', (error) => {
  logger.error({ err: error }, 'idle database client error');
});

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
