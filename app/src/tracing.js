'use strict';

function tracingEnabled() {
  if (process.env.OTEL_SDK_DISABLED === 'true') {
    return false;
  }
  const mode = (process.env.OTEL_TRACES_EXPORTER || 'otlp').toLowerCase();
  if (mode === 'none') {
    return false;
  }
  return Boolean(
    process.env.OTEL_EXPORTER_OTLP_ENDPOINT ||
      process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT,
  );
}

function startTracing() {
  if (!tracingEnabled()) {
    return;
  }

  const { NodeSDK } = require('@opentelemetry/sdk-node');
  const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
  const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');

  const sdk = new NodeSDK({
    traceExporter: new OTLPTraceExporter(),
    instrumentations: [
      getNodeAutoInstrumentations({
        '@opentelemetry/instrumentation-fs': { enabled: false },
      }),
    ],
  });

  sdk.start();

  const shutdown = () => {
    sdk
      .shutdown()
      .catch(() => {})
      .finally(() => process.exit(0));
  };

  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
}

startTracing();
