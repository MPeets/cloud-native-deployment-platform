const express = require('express');
const { DEPLOYMENT_STATUSES } = require('./deploymentsRepository');

function isPositiveInteger(value) {
  return /^\d+$/.test(value);
}

function createApp({ deploymentsRepository, isDatabaseReady }) {
  const app = express();

  app.use(express.json());

  app.get('/', (_req, res) => {
    res.send('API is running');
  });

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });

  app.get('/ready', async (_req, res) => {
    try {
      await isDatabaseReady();
      res.json({ status: 'ready' });
    } catch {
      res.status(503).json({ status: 'unavailable' });
    }
  });

  app.get('/deployments', async (req, res, next) => {
    try {
      const { status } = req.query;

      if (status && !DEPLOYMENT_STATUSES.includes(status)) {
        return res.status(400).json({ error: 'invalid status value' });
      }

      const deployments = await deploymentsRepository.list(status);
      return res.json(deployments);
    } catch (error) {
      return next(error);
    }
  });

  app.post('/deployments', async (req, res, next) => {
    try {
      const { service, version } = req.body || {};

      if (typeof service !== 'string' || typeof version !== 'string') {
        return res.status(400).json({ error: 'service and version are required' });
      }

      const trimmedService = service.trim();
      const trimmedVersion = version.trim();

      if (!trimmedService || !trimmedVersion) {
        return res.status(400).json({ error: 'service and version are required' });
      }

      const deployment = await deploymentsRepository.create({
        service: trimmedService,
        version: trimmedVersion,
      });
      return res.status(201).json(deployment);
    } catch (error) {
      return next(error);
    }
  });

  app.get('/deployments/:id', async (req, res, next) => {
    try {
      const { id } = req.params;

      if (!isPositiveInteger(id)) {
        return res.status(400).json({ error: 'id must be a positive integer' });
      }

      const deployment = await deploymentsRepository.findById(id);

      if (!deployment) {
        return res.status(404).json({ error: 'deployment not found' });
      }

      return res.json(deployment);
    } catch (error) {
      return next(error);
    }
  });

  app.patch('/deployments/:id/status', async (req, res, next) => {
    try {
      const { id } = req.params;
      const { status } = req.body || {};

      if (!isPositiveInteger(id)) {
        return res.status(400).json({ error: 'id must be a positive integer' });
      }

      if (!DEPLOYMENT_STATUSES.includes(status) || status === 'pending') {
        return res.status(400).json({ error: 'invalid status value' });
      }

      const deployment = await deploymentsRepository.updateStatus(id, status);

      if (!deployment) {
        return res.status(404).json({ error: 'deployment not found' });
      }

      return res.json(deployment);
    } catch (error) {
      return next(error);
    }
  });

  app.delete('/deployments/:id', async (req, res, next) => {
    try {
      const { id } = req.params;

      if (!isPositiveInteger(id)) {
        return res.status(400).json({ error: 'id must be a positive integer' });
      }

      const deleted = await deploymentsRepository.delete(id);

      if (!deleted) {
        return res.status(404).json({ error: 'deployment not found' });
      }

      return res.status(204).send();
    } catch (error) {
      return next(error);
    }
  });

  app.use((error, _req, res, _next) => {
    console.error(error);
    res.status(500).json({ error: 'internal server error' });
  });

  return app;
}

module.exports = {
  createApp,
};
