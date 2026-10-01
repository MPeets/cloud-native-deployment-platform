const assert = require('node:assert/strict');
const test = require('node:test');
const logger = require('../src/logger');
const { pool } = require('../src/db');

test('idle database client errors are logged and do not exit the process', async () => {
  const logged = [];
  const originalError = logger.error;
  const originalExit = process.exit;
  let exited = false;

  logger.error = (obj, message) => {
    logged.push({ obj, message });
  };
  process.exit = () => {
    exited = true;
  };

  try {
    const error = new Error('connection terminated unexpectedly');
    pool.emit('error', error);

    assert.equal(exited, false);
    assert.equal(logged.length, 1);
    assert.equal(logged[0].message, 'idle database client error');
    assert.equal(logged[0].obj.err, error);
  } finally {
    logger.error = originalError;
    process.exit = originalExit;
    await pool.end();
  }
});
