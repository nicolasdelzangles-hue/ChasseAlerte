process.env.NODE_ENV = 'test';
require('dotenv').config({ path: '.env.test' });

const request = require('supertest');
const jwt = require('jsonwebtoken');
const { app, db } = require('../index');

describe('BATTUES API', () => {
  // On fabrique un token admin "fake" pour les tests
  const adminToken = jwt.sign(
    { id: 9999, email: 'admin@test.local', role: 'admin' },
    process.env.ACCESS_SECRET
  );

  afterAll(async () => {
    // On nettoie les battues de test
    await db.query('DELETE FROM battues WHERE title LIKE "TEST_BATTUE_%"');
    await db.end();
  });

  it('POST /api/battues crée une battue (admin)', async () => {
    const res = await request(app)
      .post('/api/battues')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({
        title: 'TEST_BATTUE_JEST',
        location: 'Testville',
        date: '2025-11-18',
        imageUrl: null,
        description: 'Battue de test automatisée',
        latitude: 43.6,
        longitude: -0.05,
        type: 'Battue',
        isPrivate: false,
      });

    expect(res.statusCode).toBe(201);
  });

  it('GET /api/battues renvoie la liste des battues', async () => {
    const res = await request(app)
      .get('/api/battues')
      .set('Authorization', `Bearer ${adminToken}`);

    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);

    const found = res.body.find(b => b.title === 'TEST_BATTUE_JEST');
    expect(found).toBeDefined();
  });
});
