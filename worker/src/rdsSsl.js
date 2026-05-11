/**
 * RDS TLS helpers (keep in sync with app/src/rdsSsl.js — separate Docker contexts).
 */
const fs = require('fs');

const DEFAULT_CA_PATH = '/etc/ssl/certs/rds-global-bundle.pem';

function connectionHost(connectionString) {
  const at = connectionString.lastIndexOf('@');
  if (at === -1) {
    return '';
  }
  const rest = connectionString.slice(at + 1);
  const hostPort = rest.split('/')[0];
  return hostPort.split(':')[0];
}

function connectionWantsSsl(connectionString) {
  if (!connectionString || typeof connectionString !== 'string') {
    return false;
  }
  if (
    /sslmode=require/i.test(connectionString) ||
    /sslmode=verify-full/i.test(connectionString) ||
    /[?&]ssl=true(?:&|$)/i.test(connectionString)
  ) {
    return true;
  }
  const host = connectionHost(connectionString);
  return Boolean(host && /\.rds\.amazonaws\.com$/i.test(host));
}

/**
 * node-postgres may apply sslmode from the URL with the default CA and ignore ssl.ca;
 * use explicit ssl.* and drop ssl-related query params.
 */
function stripSslQueryParams(connectionString) {
  const q = connectionString.indexOf('?');
  if (q === -1) {
    return connectionString;
  }
  const base = connectionString.slice(0, q);
  const search = connectionString.slice(q + 1);
  try {
    const params = new URLSearchParams(search);
    params.delete('sslmode');
    params.delete('ssl');
    const next = params.toString();
    return next ? `${base}?${next}` : base;
  } catch {
    return connectionString;
  }
}

function poolOptions(connectionString) {
  if (!connectionWantsSsl(connectionString)) {
    return { connectionString };
  }

  const connectionStringClean = stripSslQueryParams(connectionString);
  const caPath = process.env.RDS_CA_BUNDLE_PATH || DEFAULT_CA_PATH;

  if (fs.existsSync(caPath)) {
    return {
      connectionString: connectionStringClean,
      ssl: {
        ca: fs.readFileSync(caPath),
        rejectUnauthorized: true,
      },
    };
  }

  if (process.env.DATABASE_SSL_NO_VERIFY === 'true') {
    return {
      connectionString: connectionStringClean,
      ssl: { rejectUnauthorized: false },
    };
  }

  return { connectionString };
}

module.exports = {
  poolOptions,
};
