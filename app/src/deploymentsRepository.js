const DEPLOYMENT_STATUSES = ['pending', 'running', 'succeeded', 'failed'];

function mapDeployment(row) {
  return {
    id: row.id,
    service: row.service,
    version: row.version,
    status: row.status,
    deployed_at: row.deployed_at,
    updated_at: row.updated_at,
  };
}

function createDeploymentsRepository(pool) {
  return {
    async list(status) {
      const query = status
        ? {
            text: 'SELECT * FROM deployments WHERE status = $1 ORDER BY deployed_at DESC',
            values: [status],
          }
        : 'SELECT * FROM deployments ORDER BY deployed_at DESC';
      const { rows } = await pool.query(query);
      return rows.map(mapDeployment);
    },

    async create({ service, version }) {
      const { rows } = await pool.query(
        `INSERT INTO deployments (service, version)
         VALUES ($1, $2)
         RETURNING *`,
        [service, version],
      );
      return mapDeployment(rows[0]);
    },

    async findById(id) {
      const { rows } = await pool.query('SELECT * FROM deployments WHERE id = $1', [id]);
      return rows[0] ? mapDeployment(rows[0]) : null;
    },

    async updateStatus(id, status) {
      const { rows } = await pool.query(
        `UPDATE deployments
         SET status = $2, updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [id, status],
      );
      return rows[0] ? mapDeployment(rows[0]) : null;
    },

    async delete(id) {
      const { rowCount } = await pool.query('DELETE FROM deployments WHERE id = $1', [id]);
      return rowCount > 0;
    },
  };
}

module.exports = {
  DEPLOYMENT_STATUSES,
  createDeploymentsRepository,
};
