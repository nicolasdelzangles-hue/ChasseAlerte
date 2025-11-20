process.env.NODE_ENV = 'test';
require('dotenv').config({ path: '.env.test' });

const request = require('supertest');
const jwt = require('jsonwebtoken');
const { app, db } = require('../index');

describe('FAVORITES API', () => {
  let userId;
  let token;
  let battueId;

  beforeAll(async () => {
    // 1) Créer un utilisateur simple en base
    const [userIns] = await db.query(
      `INSERT INTO users (first_name, last_name, name, email, password, phone, permit_number, permitNumber, role)
       VALUES ('Fav', 'User', 'Fav User', 'fav-user@example.com', 'dummy', '+33600000000', '11111111111111', '11111111111111', 'user')`
    );
    userId = userIns.insertId;

    // 2) Générer un token pour cet utilisateur
    token = jwt.sign(
      { id: userId, email: 'fav-user@example.com', role: 'user' },
      process.env.ACCESS_SECRET
    );

    // 3) Créer une battue pour les tests de favoris
    const [battueIns] = await db.query(
      `INSERT INTO battues (title, location, date, imageUrl, description, latitude, longitude, type, isPrivate)
       VALUES ('TEST_BATTUE_FAV', 'FavVille', '2025-11-18', NULL, 'Battue pour tests favoris', 43.7, -0.06, 'Battue', 0)`
    );
    battueId = battueIns.insertId;
  });

  afterAll(async () => {
    await db.query('DELETE FROM favorites WHERE user_id = ?', [userId]);
    await db.query('DELETE FROM battues WHERE id = ?', [battueId]);
    await db.query('DELETE FROM users WHERE id = ?', [userId]);
    await db.end();
  });

  it('POST /api/favorites ajoute une battue aux favoris', async () => {
    const res = await request(app)
      .post('/api/favorites')
      .set('Authorization', `Bearer ${token}`)
      .send({ battue_id: battueId });

    expect(res.statusCode).toBe(201);
  });

  it('GET /api/favorites renvoie la battue en favoris', async () => {
    const res = await request(app)
      .get('/api/favorites')
      .set('Authorization', `Bearer ${token}`);

    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);

    const found = res.body.find(b => b.id === battueId);
    expect(found).toBeDefined();
  });

  it('DELETE /api/favorites/:battue_id retire la battue', async () => {
    const res = await request(app)
      .delete(`/api/favorites/${battueId}`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.statusCode).toBe(200);

    const res2 = await request(app)
      .get('/api/favorites')
      .set('Authorization', `Bearer ${token}`);

    const still = res2.body.find(b => b.id === battueId);
    expect(still).toBeUndefined();
  });
});
