const client = require('prom-client');

const register = new client.Registry();

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const httpRequestDurationSeconds = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request latency in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: client.exponentialBuckets(0.005, 2, 12),
  registers: [register],
});

const httpRequestsInFlight = new client.Gauge({
  name: 'http_requests_in_flight',
  help: 'HTTP requests currently being handled',
  registers: [register],
});

function routeLabel(req) {
  if (req.route && req.route.path) {
    const base = req.baseUrl || '';
    return `${base}${req.route.path}` || req.path;
  }
  return req.path || 'unknown';
}

function shouldSkip(req) {
  return req.path === '/metrics';
}

function createHttpMetricsMiddleware() {
  return function httpMetricsMiddleware(req, res, next) {
    if (shouldSkip(req)) {
      return next();
    }

    httpRequestsInFlight.inc();
    const endTimer = httpRequestDurationSeconds.startTimer({ method: req.method });

    let observed = false;
    const observe = () => {
      if (observed) {
        return;
      }
      observed = true;
      const route = routeLabel(req);
      const status = String(res.statusCode);
      httpRequestsTotal.inc({ method: req.method, route, status_code: status });
      endTimer({ route, status_code: status });
      httpRequestsInFlight.dec();
    };

    res.on('finish', observe);
    res.on('close', observe);

    next();
  };
}

async function metricsHandler(_req, res, next) {
  try {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (error) {
    next(error);
  }
}

module.exports = {
  register,
  createHttpMetricsMiddleware,
  metricsHandler,
};
