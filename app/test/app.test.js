const assert = require('node:assert/strict');
const test = require('node:test');
const request = require('supertest');
const { createApp } = require('../src/app');

const baseDeployment = {
  service: 'payments-api',
  version: '1.4.2',
  status: 'pending',
  deployed_at: '2026-04-27T10:00:00.000Z',
  updated_at: '2026-04-27T10:00:00.000Z',
};

function createTestApp({ ready = true } = {}) {
  let nextId = 1;
  let deployments = [];

  const repository = {
    async list(status) {
      return deployments.filter((deployment) => !status || deployment.status === status);
    },
    async create({ service, version }) {
      const deployment = {
        id: nextId,
        ...baseDeployment,
        service,
        version,
      };
      nextId += 1;
      deployments = [deployment, ...deployments];
      return deployment;
    },
    async findById(id) {
      return deployments.find((deployment) => deployment.id === Number(id)) || null;
    },
    async updateStatus(id, status) {
      const deployment = deployments.find((item) => item.id === Number(id));

      if (!deployment) {
        return null;
      }

      deployment.status = status;
      deployment.updated_at = '2026-04-27T10:05:00.000Z';
      return deployment;
    },
    async delete(id) {
      const initialCount = deployments.length;
      deployments = deployments.filter((deployment) => deployment.id !== Number(id));
      return deployments.length !== initialCount;
    },
  };

  return createApp({
    deploymentsRepository: repository,
    isDatabaseReady: async () => {
      if (!ready) {
        throw new Error('database unavailable');
      }
    },
  });
}

test('health and readiness endpoints report process and database status', async () => {
  const healthyApp = createTestApp();
  const unhealthyApp = createTestApp({ ready: false });

  await request(healthyApp).get('/health').expect(200, { status: 'ok' });
  await request(healthyApp).get('/ready').expect(200, { status: 'ready' });
  await request(unhealthyApp).get('/ready').expect(503, { status: 'unavailable' });
});

test('POST /deployments creates a pending deployment', async () => {
  const app = createTestApp();

  const response = await request(app)
    .post('/deployments')
    .send({ service: 'payments-api', version: '1.4.2' })
    .expect(201);

  assert.equal(response.body.id, 1);
  assert.equal(response.body.service, 'payments-api');
  assert.equal(response.body.version, '1.4.2');
  assert.equal(response.body.status, 'pending');
  assert.equal(response.body.deployed_at, baseDeployment.deployed_at);
});

test('POST /deployments calls the repository with a valid request body', async () => {
  let createdDeployment;
  const repository = {
    async create(deployment) {
      createdDeployment = deployment;
      return { id: 1, ...baseDeployment, ...deployment };
    },
  };
  const app = createApp({
    deploymentsRepository: repository,
    isDatabaseReady: async () => {},
  });

  await request(app)
    .post('/deployments')
    .send({ service: ' payments-api ', version: ' 1.4.2 ' })
    .expect(201);

  assert.deepEqual(createdDeployment, {
    service: 'payments-api',
    version: '1.4.2',
  });
});

test('POST /deployments validates required fields', async () => {
  const app = createTestApp();

  await request(app)
    .post('/deployments')
    .send({ service: 'payments-api' })
    .expect(400, { error: 'service and version are required' });
});

test('GET /deployments lists deployments with an optional status filter', async () => {
  const app = createTestApp();

  await request(app).post('/deployments').send({ service: 'payments-api', version: '1.4.2' });
  await request(app).post('/deployments').send({ service: 'orders-api', version: '2.0.0' });
  await request(app).patch('/deployments/2/status').send({ status: 'running' });

  const allResponse = await request(app).get('/deployments').expect(200);
  const filteredResponse = await request(app).get('/deployments?status=pending').expect(200);

  assert.equal(allResponse.body.length, 2);
  assert.equal(filteredResponse.body.length, 1);
  assert.equal(filteredResponse.body[0].service, 'payments-api');
});

test('GET /deployments/:id returns one deployment or 404', async () => {
  const app = createTestApp();

  await request(app).post('/deployments').send({ service: 'payments-api', version: '1.4.2' });

  const response = await request(app).get('/deployments/1').expect(200);

  assert.equal(response.body.service, 'payments-api');
  await request(app).get('/deployments/999').expect(404, { error: 'deployment not found' });
});

test('PATCH /deployments/:id/status updates valid status values', async () => {
  const app = createTestApp();

  await request(app).post('/deployments').send({ service: 'payments-api', version: '1.4.2' });

  const response = await request(app)
    .patch('/deployments/1/status')
    .send({ status: 'succeeded' })
    .expect(200);

  assert.equal(response.body.status, 'succeeded');
});

test('PATCH /deployments/:id/status rejects invalid values and missing records', async () => {
  const app = createTestApp();

  await request(app)
    .patch('/deployments/1/status')
    .send({ status: 'pending' })
    .expect(400, { error: 'invalid status value' });

  await request(app)
    .patch('/deployments/1/status')
    .send({ status: 'succeeded' })
    .expect(404, { error: 'deployment not found' });
});

test('DELETE /deployments/:id removes a deployment', async () => {
  const app = createTestApp();

  await request(app).post('/deployments').send({ service: 'payments-api', version: '1.4.2' });

  await request(app).delete('/deployments/1').expect(204);
  await request(app).get('/deployments/1').expect(404, { error: 'deployment not found' });
});
