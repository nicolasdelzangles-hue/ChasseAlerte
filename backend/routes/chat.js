// routes/chat.js
const express = require('express');
const jwt = require('jsonwebtoken');

module.exports = function chatRoutesFactory({ db, SECRET_KEY }) {
  const router = express.Router();

  // --- Auth middleware local au routeur ---
  function auth(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    if (!token) return res.status(401).json({ message: 'Token manquant' });
    jwt.verify(token, SECRET_KEY, (err, user) => {
      if (err) return res.status(403).json({ message: 'Token invalide' });
      req.user = user;
      next();
    });
  }

  // ---- Conversations de l'utilisateur ----
  router.get('/conversations', auth, async (req, res) => {
    try {
      const userId = req.user.id;
      const [rows] = await db.query(
        `
        SELECT c.id, c.is_group, c.title,
               MAX(m.created_at) AS last_message_at,
               JSON_OBJECT(
                 'id', MAX(m.id),
                 'sender_id', (SELECT sender_id FROM messages WHERE id = MAX(m.id)),
                 'body', (SELECT body FROM messages WHERE id = MAX(m.id)),
                 'created_at', MAX(m.created_at)
               ) AS last_message
        FROM conversations c
        JOIN conversation_participants cp ON cp.conversation_id = c.id AND cp.user_id = ?
        LEFT JOIN messages m ON m.conversation_id = c.id
        GROUP BY c.id
        ORDER BY last_message_at DESC NULLS LAST, c.created_at DESC
        `,
        [userId]
      );
      res.json(rows.map(r => ({
        id: r.id,
        is_group: !!r.is_group,
        title: r.title,
        last_message: r.last_message ? JSON.parse(r.last_message) : null
      })));
    } catch (e) {
      console.error(e);
      res.status(500).json({ message: 'Erreur serveur' });
    }
  });

  // ---- Créer une conversation ----
  router.post('/conversations', auth, async (req, res) => {
    const userId = req.user.id;
    const { peerId, title, memberIds } = req.body;

    try {
      let conversationId;

      if (peerId) {
        // DM : vérifier si elle existe déjà
        const [exist] = await db.query(
          `
          SELECT c.id
          FROM conversations c
          JOIN conversation_participants a ON a.conversation_id = c.id AND a.user_id = ?
          JOIN conversation_participants b ON b.conversation_id = c.id AND b.user_id = ?
          WHERE c.is_group = 0
          LIMIT 1
          `,
          [userId, peerId]
        );
        if (exist.length) {
          return res.status(200).json({ id: exist[0].id });
        }

        const [ins] = await db.query('INSERT INTO conversations (is_group) VALUES (0)');
        conversationId = ins.insertId;
        await db.query('INSERT INTO conversation_participants (conversation_id, user_id) VALUES (?, ?), (?, ?)', [conversationId, userId, conversationId, peerId]);
      } else {
        // Groupe
        const [ins] = await db.query('INSERT INTO conversations (is_group, title) VALUES (1, ?)', [title || null]);
        conversationId = ins.insertId;
        const participants = Array.from(new Set([userId, ...(memberIds || [])]));
        const values = participants.flatMap(uid => [conversationId, uid, uid === userId ? 'admin' : 'member']);
        const placeholders = participants.map(() => '(?, ?, ?)').join(',');
        await db.query(
          `INSERT INTO conversation_participants (conversation_id, user_id, role) VALUES ${placeholders}`,
          values
        );
      }

      res.status(201).json({ id: conversationId });
    } catch (e) {
      console.error(e);
      res.status(500).json({ message: 'Erreur serveur' });
    }
  });

  // ---- Récupérer messages (pagination) ----
  // ?before=<messageId> & limit=20
  router.get('/messages/:conversationId', auth, async (req, res) => {
    const userId = req.user.id;
    const { conversationId } = req.params;
    const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);
    const before = req.query.before ? Number(req.query.before) : null;

    try {
      // sécurité : l'utilisateur doit être participant
      const [part] = await db.query('SELECT 1 FROM conversation_participants WHERE conversation_id = ? AND user_id = ?', [conversationId, userId]);
      if (!part.length) return res.status(403).json({ message: 'Accès interdit' });

      const sql = `
        SELECT id, sender_id, body, attachments, created_at
        FROM messages
        WHERE conversation_id = ?
        ${before ? 'AND id < ?' : ''}
        ORDER BY id DESC
        LIMIT ?
      `;
      const params = before ? [conversationId, before, limit] : [conversationId, limit];
      const [rows] = await db.query(sql, params);

      // on renvoie en ordre chronologique (asc) côté client c'est plus simple
      res.json(rows.reverse());
    } catch (e) {
      console.error(e);
      res.status(500).json({ message: 'Erreur serveur' });
    }
  });

  // ---- Envoyer un message ----
  router.post('/messages', auth, async (req, res) => {
    const userId = req.user.id;
    const { conversationId, body, attachments } = req.body;

    if (!conversationId || (!body && !attachments)) {
      return res.status(400).json({ message: 'conversationId et body/attachments requis' });
    }

    try {
      const [part] = await db.query('SELECT 1 FROM conversation_participants WHERE conversation_id = ? AND user_id = ?', [conversationId, userId]);
      if (!part.length) return res.status(403).json({ message: 'Accès interdit' });

      const [ins] = await db.query(
        'INSERT INTO messages (conversation_id, sender_id, body, attachments) VALUES (?, ?, ?, ?)',
        [conversationId, userId, body || null, attachments ? JSON.stringify(attachments) : null]
      );

      const [row] = await db.query('SELECT * FROM messages WHERE id = ?', [ins.insertId]);
      const message = row[0];

      // Émettre aux membres de la conversation + à la salle conv
      const io = req.app.get('io');
      io.to(`conv:${conversationId}`).emit('message:new', { conversationId, message });
      // Émettre aussi à chaque participant via leur salle "user:<id>" (utile si pas dans la conv active)
      const [members] = await db.query('SELECT user_id FROM conversation_participants WHERE conversation_id = ?', [conversationId]);
      members.forEach(({ user_id }) => {
        io.to(`user:${user_id}`).emit('message:new', { conversationId, message });
      });

      res.status(201).json(message);
    } catch (e) {
      console.error(e);
      res.status(500).json({ message: 'Erreur serveur' });
    }
  });

  return router;
};
