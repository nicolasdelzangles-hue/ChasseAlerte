const request = require('supertest');
const { app, db } = require('../index');

async function createTestAdminAndToken() {
  const email = 'admin-test@example.com';
  const password = 'AdminTest123!';

  // On nettoie avant
  await db.query('DELETE FROM users WHERE email = ?', [email]);

  // 1) Register
  await request(app)
    .post('/api/register')
    .send({
      first_name: 'Admin',
      last_name: 'Test',
      email,
      phone: '0612345678',
      address: 'Rue des tests',
      postal_code: '40000',
      city: 'Testville',
      permit_number: '99999999999999',
      password,
    });

  // 2) Forcer le rôle admin dans la DB
  await db.query('UPDATE users SET role = "admin" WHERE email = ?', [email]);

  // 3) Login pour récupérer le token
  const res = await request(app)
    .post('/api/auth/login')
    .send({ email, password });

  const token = res.body.accessToken;
  if (!token) {
    throw new Error('Token non reçu pour l’admin de test');
  }

  return { token, email };
}

module.exports = {
  createTestAdminAndToken,
};
