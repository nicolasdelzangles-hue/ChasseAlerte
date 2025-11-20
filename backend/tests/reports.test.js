process.env.NODE_ENV = 'test';

const request = require('supertest');
const { app, db } = require('../index');

describe('REPORTS API', () => {
  let reportId;

  afterAll(async () => {
    if (reportId) {
      await db.query('DELETE FROM reports WHERE id = ?', [reportId]);
    }
    await db.end();
  });

  it('POST /api/reports crée un signalement', async () => {
    const res = await request(app)
      .post('/api/reports')
      .send({
        reported_first_name: 'Chasseur',
        reported_last_name: 'Test',
        category: 'Comportement dangereux',
        description: 'Description de test suffisamment longue',
        location: 'Mont-de-Marsan',
        incident_at: '2025-11-18T10:00:00.000Z',
        is_anonymous: true,
        muted: false,
        blocked: false,
      });

    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('success', true);
    expect(res.body).toHaveProperty('id');

    reportId = res.body.id;
  });

  it('GET /api/reports renvoie la liste des signalements', async () => {
    const res = await request(app).get('/api/reports');

    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);

    const found = res.body.find(r => r.id === reportId);
    expect(found).toBeDefined();
  });
});
