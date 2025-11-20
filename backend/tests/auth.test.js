process.env.NODE_ENV = 'test';

const request = require('supertest');
const { app, db } = require('../index');

describe('AUTH API', () => {
  const testEmail = 'test-user@example.com';

  beforeAll(async () => {
    // Nettoyage d’un éventuel user de test
    await db.query('DELETE FROM users WHERE email = ?', [testEmail]);
  });

  afterAll(async () => {
    await db.end();
  });

  const testUser = {
    first_name: 'Test',
    last_name: 'User',
    email: testEmail,
    phone: '0612345678',
    address: 'Test rue',
    postal_code: '40000',
    city: 'Testville',
    permit_number: '12345678901234',
    password: 'Password123!',
  };

  it('POST /api/register crée un utilisateur', async () => {
    const res = await request(app)
      .post('/api/register')
      .send(testUser);

    expect(res.statusCode).toBe(201);
    expect(res.body).toHaveProperty('id');
  });

  it('POST /api/auth/login renvoie un token', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: testEmail, password: testUser.password });

    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('accessToken');
    expect(res.body).toHaveProperty('refreshToken');
    expect(res.body).toHaveProperty('user');
  });
});
