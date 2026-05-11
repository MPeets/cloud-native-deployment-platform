/**
 * RDS TLS: keep in sync with app/src/rdsSsl.js (duplicate for separate Docker build contexts).
 */
const fs = require('fs');

const DEFAULT_CA_PATH = '/etc/ssl/certs/rds-global-bundle.pem';

function connectionWantsSsl(connectionString) {
  if (!connectionString || typeof connectionString !== 'string') {
    return false;
  }
  return (
    /sslmode=require/i.test(connectionString) ||
    /sslmode=verify-full/i.test(connectionString) ||
    /[?&]ssl=true(?:&|$)/i.test(connectionString)
  );
}

function poolOptions(connectionString) {
  if (!connectionWantsSsl(connectionString)) {
    return { connectionString };
  }

  const caPath = process.env.RDS_CA_BUNDLE_PATH || DEFAULT_CA_PATH;
  if (fs.existsSync(caPath)) {
    return {
      connectionString,
      ssl: {
        ca: fs.readFileSync(caPath),
        rejectUnauthorized: true,
      },
    };
  }

  if (process.env.DATABASE_SSL_NO_VERIFY === 'true') {
    return {
      connectionString,
      ssl: { rejectUnauthorized: false },
    };
  }

  return { connectionString };
}

module.exports = {
  poolOptions,
};
