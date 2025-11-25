// index.js — ChasseAlerte (API REST + Socket.IO)

// ======================= Imports & Setup =======================
const bcrypt = require('bcryptjs');
const Joi = require('joi');

const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const bodyParser = require('body-parser');
const mysql = require('mysql2/promise');
const os = require('os');
const http = require('http');
const { Server } = require('socket.io');
const { parsePhoneNumberFromString } = require('libphonenumber-js');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const mime = require('mime-types');
const axios = require('axios'); // météo + geocode
const envFile = process.env.NODE_ENV === 'test' ? '.env.test' : '.env';
require('dotenv').config({ path: envFile });

const app = express();
// Une seule clé serveur pour toutes les routes Google
const SERVER_KEY =
  process.env.GOOGLE_MAPS_SERVER_KEY ||
  process.env.MINI_MAP_SERVER_KEY ||
  process.env.GOOGLE_MAPS_SERVER_KEY2 ||
  null;

console.log('[CFG] SERVER_KEY present:', !!SERVER_KEY);
 
// ======================= Config =======================
// Ports/host (override via env)
const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '0.0.0.0';
const SECRET_KEY = process.env.JWT_SECRET || 'chassealerte_secret';
// Secrets JWT unifiés (API + Socket.IO)
const ACCESS_SECRET  = process.env.ACCESS_SECRET  || SECRET_KEY;
const REFRESH_SECRET = process.env.REFRESH_SECRET || SECRET_KEY;

// MySQL pool
const db = mysql.createPool({
  host: process.env.DB_HOST ,
  user: process.env.DB_USER ,
  password: process.env.DB_PORT || '3306',
  database: process.env.DB_NAME ,
  password: process.env.DB_PASSWORD,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});
// ====== LOGGING UTILS ======
const startHr = () => process.hrtime.bigint();
const durMs = (t0) => Number((process.hrtime.bigint() - t0) / 1000000n);
const now = () => new Date().toISOString().replace('T', ' ').replace('Z', '');

const maskKey = (k) => (typeof k === 'string' && k.length > 8)
  ? k.slice(0, 4) + '...' + k.slice(-4)
  : k;

function logInfo(...args)  { console.log(`[${now()}][INFO]`,  ...args); }
function logWarn(...args)  { console.warn(`[${now()}][WARN]`, ...args); }
function logError(...args) { console.error(`[${now()}][ERR ]`,  ...args); }
const rateLimit = require('express-rate-limit');

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
});



function createAccessToken(user) {
  return jwt.sign(
    { id: user.id, email: user.email, role: user.role },
    ACCESS_SECRET,
    { expiresIn: '15m' }
  );
}

function createRefreshToken(user) {
  return jwt.sign(
    { id: user.id },
    REFRESH_SECRET,
    { expiresIn: '7d' }
  );
}



// Log de chaque requête entrante + durée
app.use((req, res, next) => {
  const t0 = startHr();
  logInfo(`HTTP ${req.method} ${req.originalUrl}`, { query: req.query, body: req.body });
  res.on('finish', () => {
    logInfo(`HTTP ${req.method} ${req.originalUrl} -> ${res.statusCode} (${durMs(t0)} ms)`);
  });
  next();
});
// ====== AXIOS LOGGING ======
const axiosInstance = axios.create();
axiosInstance.interceptors.request.use((config) => {
  config.metadata = { t0: Date.now() };
  const id = (config.headers['X-Req-Id'] || 'noid').toString();
  console.log(`[HTTP->G ${id}] ${config.method?.toUpperCase()} ${config.url}`, { params: config.params });
  return config;
});
axiosInstance.interceptors.response.use(
  (res) => {
    const id = (res.config.headers['X-Req-Id'] || 'noid').toString();
    const ms = Date.now() - (res.config.metadata?.t0 || Date.now());
    console.log(`[HTTP<-G ${id}] ${res.status} ${res.config.url} (${ms} ms)`);
    return res;
  },
  (err) => {
    const cfg = err.config || {};
    const id = (cfg.headers?.['X-Req-Id'] || 'noid').toString();
    const ms = Date.now() - (cfg.metadata?.t0 || Date.now());
    console.log(`[HTTP!!G ${id}] ${cfg.method?.toUpperCase()} ${cfg.url} (${ms} ms) ERR:`, err.response?.status, err.response?.data || err.message);
    return Promise.reject(err);
  }
);

// ======================= CORS + JSON =======================
// CORS robuste (pré-vol DELETE + Authorization)
const corsOptions = {
  origin: (origin, cb) => cb(null, true),
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Accept', 'Origin', 'X-Requested-With'],
};
if (process.env.NODE_ENV === 'production') {
  app.set('trust proxy', true);
} else {
  app.set('trust proxy', false); // tests + dev
}

app.use(cors(corsOptions));
app.options('*', cors(corsOptions));
app.use(bodyParser.json({ limit: '5mb' }));
app.use(express.json()); // indispensable pour req.body

// ======================= Static uploads =======================
const UPLOAD_ROOT = path.join(__dirname, 'uploads');
const UPLOAD_CHAT_DIR = path.join(UPLOAD_ROOT, 'chat');
fs.mkdirSync(UPLOAD_CHAT_DIR, { recursive: true });
app.use('/uploads', express.static(UPLOAD_ROOT, { fallthrough: true }));

// ======================= Multer (uploads chat) =======================
function fileFilter(req, file, cb) {
  const ok = /^image\//.test(file.mimetype) || /^video\//.test(file.mimetype);
  cb(ok ? null : new Error('Type de fichier non autorisé'), ok);
}
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOAD_CHAT_DIR),
  filename: (_req, file, cb) => {
    const ext = mime.extension(file.mimetype) || path.extname(file.originalname).slice(1) || 'bin';
    const base = path.parse(file.originalname).name.replace(/\s+/g, '_').slice(0, 50);
    cb(null, `${base}_${Date.now()}.${ext}`);
  },
});
const upload = multer({
  storage,
  fileFilter,
  limits: { fileSize: 200 * 1024 * 1024, files: 10 }, // 200 Mo / 10 fichiers
});

// ======================= Helpers généraux =======================
function normPhone(phone, defaultCountry = 'FR') {
  try {
    const p = parsePhoneNumberFromString(String(phone || ''), defaultCountry);
    return p && p.isValid() ? p.number : null; // E.164 ex: +33612345678
  } catch {
    return null;
  }
}
function safeEmailRaw(v) {
  return String(v || '').trim().toLowerCase();
}
function buildDisplayName(first, last, fallback) {
  const n = `${String(first || '').trim()} ${String(last || '').trim()}`.trim();
  return n || String(fallback || '').trim();
}// ======================= Validation (Joi) =======================

function validate(schema, options = {}) {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.body, {
      abortEarly: false,      // remonte toutes les erreurs
      stripUnknown: true,     // enlève les champs non prévus
    });

    if (error) {
      // Mode "array" pour /api/register (pour rester compatible avec ton front)
      if (options.mode === 'array') {
        return res.status(400).json({
          errors: error.details.map(d => d.message),
        });
      }

      // Mode simple: un seul message
      return res.status(400).json({
        message: error.details[0].message,
      });
    }

    // On remplace le body par la version validée/nettoyée
    req.body = value;
    next();
  };
}

// ===== Schémas Joi =====

// Login
const loginSchema = Joi.object({
  email: Joi.string().email().required().messages({
    'string.email': 'Email invalide',
    'any.required': 'Email requis',
  }),
  password: Joi.string().min(6).max(100).required().messages({
    'string.min': 'Mot de passe trop court (min 6)',
    'any.required': 'Mot de passe requis',
  }),
});

// Register
const registerSchema = Joi.object({
  first_name: Joi.string().min(1).max(100).required().messages({
    'any.required': 'Prénom requis',
  }),
  last_name: Joi.string().min(1).max(100).required().messages({
    'any.required': 'Nom requis',
  }),
  email: Joi.string().email().required().messages({
    'string.email': 'Email invalide',
    'any.required': 'Email requis',
  }),
  phone: Joi.string().min(6).max(30).required().messages({
    'any.required': 'Téléphone requis',
  }),
  address: Joi.string().allow(null, '').max(255),
  postal_code: Joi.string().allow(null, '').max(10),
  city: Joi.string().allow(null, '').max(100),
  permit_number: Joi.string()
    .pattern(/^[0-9]{14}$/)
    .required()
    .messages({
      'string.pattern.base': 'Numéro de permis invalide (14 chiffres)',
      'any.required': 'Numéro de permis requis',
    }),
  password: Joi.string().min(8).max(100).required().messages({
    'string.min': 'Mot de passe trop court (min 8)',
    'any.required': 'Mot de passe requis',
  }),
});

// Battue (création)
const battueSchema = Joi.object({
  title: Joi.string().min(3).max(150).required().messages({
    'any.required': 'Titre requis',
  }),
  location: Joi.string().allow(null, '').max(255),
  date: Joi.alternatives().try(
    Joi.date().iso(),
    Joi.string().min(4) // au cas où tu envoies un simple "2025-11-18"
  ).required().messages({
    'any.required': 'Date requise',
  }),
  imageUrl: Joi.string().allow(null, '').optional(),

  description: Joi.string().allow(null, '').max(2000),
  latitude: Joi.number().min(-90).max(90).required().messages({
    'any.required': 'Latitude requise',
  }),
  longitude: Joi.number().min(-180).max(180).required().messages({
    'any.required': 'Longitude requise',
  }),
  type: Joi.string().allow(null, '').max(100),
  isPrivate: Joi.boolean().truthy(1, 0, '1', '0').default(false),
});

// Signalement (reports)
const reportSchema = Joi.object({
  reported_first_name: Joi.string().allow('', null).max(100),
  reported_last_name: Joi.string().allow('', null).max(100),
  category: Joi.string().min(3).max(255).required().messages({
    'any.required': 'Catégorie requise',
  }),
  description: Joi.string().min(10).max(2000).required().messages({
    'string.min': 'Description trop courte',
    'any.required': 'Description requise',
  }),
  location: Joi.string().allow('', null).max(255),
  incident_at: Joi.alternatives().try(
    Joi.date().iso(),
    Joi.string().min(4)
  ).required().messages({
    'any.required': 'Date de l\'incident requise',
  }),
  is_anonymous: Joi.boolean().truthy(1, 0, '1', '0').required(),
  muted: Joi.boolean().truthy(1, 0, '1', '0').required(),
  blocked: Joi.boolean().truthy(1, 0, '1', '0').required(),
});


// ======================= Auth Middlewares =======================
function authMiddleware(req, res, next) {
  const header = req.headers["authorization"];
  if (!header) return res.status(401).json({ error: "Token manquant" });

  const [type, token] = header.split(" ");
  if (type !== "Bearer" || !token)
    return res.status(401).json({ error: "Authorization invalide" });

jwt.verify(token, ACCESS_SECRET, (err, payload) => {
    if (err) return res.status(401).json({ error: "Token expiré ou invalide" });
    req.user = payload;  
    next();
  });
}

function adminMiddleware(req, res, next) {
  if (req.user?.role !== 'admin') {
    return res.status(403).json({ message: 'Accès réservé aux admins' });
  }
  next();
}

// ======================= AUTH =======================
// ======================= AUTH =======================
app.post('/api/auth/login', loginLimiter, validate(loginSchema), async (req, res) => {
  // après Joi, on est sûr que ces champs existent et sont des strings correctes
  const email = safeEmailRaw(req.body.email);
  const password = String(req.body.password || '');

  try {
    const [rows] = await db.query('SELECT * FROM users WHERE email = ?', [email]);
    if (!rows.length) return res.status(401).json({ message: 'Identifiants incorrects' });

    const user = rows[0];

    const correct = await bcrypt.compare(password, user.password);
    if (!correct) return res.status(401).json({ message: 'Mot de passe incorrect' });

    const accessToken = createAccessToken(user);
    const refreshToken = createRefreshToken(user);

    await db.query(
      "INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES (?, ?, DATE_ADD(NOW(), INTERVAL 7 DAY))",
      [user.id, refreshToken]
    );

    res.json({ accessToken, refreshToken, user: { id: user.id, email: user.email, role: user.role } });
  } catch (e) {
    console.error('POST /api/auth/login', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

app.post('/api/auth/refresh', async (req, res) => {
  const { refreshToken } = req.body;
  if (!refreshToken) return res.status(400).json({ error: 'refreshToken manquant' });

  try {
    const [rows] = await db.query(
      "SELECT * FROM refresh_tokens WHERE token = ? AND revoked = 0 LIMIT 1",
      [refreshToken]
    );
    if (!rows.length) return res.status(401).json({ error: 'Refresh Token invalide' });

const data = jwt.verify(refreshToken, REFRESH_SECRET);

    const [u] = await db.query("SELECT * FROM users WHERE id = ?", [data.id]);
    if (!u.length) return res.status(404).json({ error: 'User not found' });

    const user = u[0];
    const newAccessToken = createAccessToken(user);

    res.json({ accessToken: newAccessToken });
  } catch (err) {
    console.error(err);
    res.status(401).json({ error: 'Refresh Token expiré ou invalide' });
  }
});



// ======================= REGISTER =======================
// ======================= REGISTER =======================
app.post('/api/register', validate(registerSchema, { mode: 'array' }), async (req, res) => {
  const {
    first_name,
    last_name,
    phone,
    address,
    postal_code,
    city,
    permit_number,
    password,
  } = req.body || {};
  const email = safeEmailRaw(req.body?.email);

  const errors = [];

  // Validation métier supplémentaire : téléphone normalisé FR
  const normalizedPhone = normPhone(phone);
  if (!normalizedPhone) errors.push('Téléphone invalide');

  if (errors.length) {
    return res.status(400).json({ errors });
  }

  try {
    const [existing] = await db.query('SELECT id FROM users WHERE email = ?', [email]);
    if (existing.length) {
      return res.status(409).json({ message: 'Un compte existe déjà avec cet e-mail' });
    }

    const fullName = `${String(first_name).trim()} ${String(last_name).trim()}`.trim();
    const passwordHash = await bcrypt.hash(String(password), 12);

    const [ins] = await db.query(
      `INSERT INTO users
       (first_name, last_name, name, email, password, phone, permit_number, permitNumber, address, postal_code, city, role)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        String(first_name).trim(),
        String(last_name).trim(),
        fullName,
        email,
        passwordHash,
        normalizedPhone,
        String(permit_number),
        String(permit_number), // compat legacy
        address || null,
        postal_code || null,
        city || null,
        'user',
      ]
    );

    res.status(201).json({ message: 'Inscription réussie', id: ins.insertId });
  } catch (e) {
    if (e && e.code === 'ER_DUP_ENTRY') {
      const msg = /uq_users_permit_number|uq_users_permitNumber/i.test(e.message || '')
        ? 'Un compte existe déjà avec ce numéro de permis'
        : /uq_users_email/i.test(e.message || '')
        ? 'Un compte existe déjà avec cet e-mail'
        : 'Doublon détecté';
      return res.status(409).json({ message: msg });
    }
    console.error('POST /api/register', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});


// ======================= USERS =======================
app.get('/api/users/me', authMiddleware, async (req, res) => {
  try {
    const [rows] = await db.query(
      `SELECT id, first_name, last_name, name, email, phone,
              address, postal_code, city,
              permit_number, created_at, role      -- ⬅️ AJOUT ICI
       FROM users WHERE id = ?`,
      [req.user.id]
    );
    if (!rows.length) return res.status(401).json({ message: 'Session invalide' });
    res.json(rows[0]);
  } catch (e) {
    console.error('GET /api/users/me', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

// GET /api/users — liste “safe”
app.get('/api/users', authMiddleware, async (_req, res) => {
  try {
    const [rows] = await db.query(
      `SELECT id, first_name, last_name, name, email, phone,
              address, postal_code, city,
              permit_number, created_at, role      -- ⬅️ AJOUT ICI
       FROM users
       ORDER BY id ASC`
    );
    res.json(rows);
  } catch (e) {
    console.error('GET /api/users', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

// PUT /api/users/me — mise à jour profil
app.put('/api/users/me', authMiddleware, async (req, res) => {
  const uid = req.user && req.user.id;
  if (!uid) return res.status(401).json({ error: 'unauthorized' });

  const {
    first_name,
    last_name,
    name,
    phone,
    address,
    postal_code,
    city,
    permit_number,
  } = req.body || {};

  const nn = (v) =>
    v === undefined || v === null || String(v).trim() === ''
      ? null
      : String(v).trim();

  const phoneNormalized = nn(phone) ? normPhone(phone) : null;

  try {
    const [result] = await db.execute(
      `UPDATE users SET
         first_name    = ?,
         last_name     = ?,
         name          = ?,
         phone         = ?,
         address       = ?,
         postal_code   = ?,
         city          = ?,
         permit_number = ?
       WHERE id = ?`,
      [
        nn(first_name),
        nn(last_name),
        nn(name),
        phoneNormalized,
        nn(address),
        nn(postal_code),
        nn(city),
        nn(permit_number),
        uid,
      ]
    );

    if (!result.affectedRows) {
      return res.status(404).json({ error: 'user_not_updated' });
    }

    const [rows] = await db.execute(
      `SELECT id, first_name, last_name, name, email, phone, address,
              postal_code, city, permit_number, created_at, role   -- ⬅️ AJOUT ICI
       FROM users WHERE id = ? LIMIT 1`,
      [uid]
    );
    return res.json(rows[0] || {});
  } catch (e) {
    console.error('PUT /api/users/me error:', e);
    return res.status(500).json({ error: 'update_failed' });
  }
});

app.get('/api/users/by-phone', authMiddleware, async (req, res) => {
  const phone = normPhone(req.query.phone || '');
  if (!phone) return res.status(400).json({ message: 'Téléphone invalide' });

  try {
    const [rows] = await db.query(
      'SELECT id, first_name, last_name, name, phone, photoUrl FROM users WHERE phone = ?',
      [phone]
    );
    if (!rows.length) return res.status(404).json({ message: 'Utilisateur introuvable' });
    res.json(rows[0]);
  } catch (e) {
    console.error('GET /api/users/by-phone', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});


// ======================= BATTUES =======================
app.get('/api/battues', authMiddleware, async (_req, res) => {
  try {
    const [rows] = await db.query('SELECT * FROM battues');
    res.json(rows);
  } catch (e) {
    console.error('GET /api/battues', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

app.post(
  '/api/battues',
  authMiddleware,
  adminMiddleware,
  validate(battueSchema),
  async (req, res) => {
    const {
      title,
      location,
      date,
      imageUrl,
      zoneGeoJSON,
      description,
      latitude,
      longitude,
      type,
      isPrivate,
    } = req.body || {};

    try {
      await db.query(
        'INSERT INTO battues (title, location, date, imageUrl, zoneGeoJSON, description,latitude, longitude, type, isPrivate) VALUES (?,?,?,?,?,?,?,?,?,?)',
        [title, location, date, imageUrl,zoneGeoJSON, description, latitude, longitude, type, isPrivate]
      );
      res.status(201).json({ message: 'Battue ajoutée avec succès' });
    } catch (e) {
      console.error('POST /api/battues', e);
      res.status(500).json({ message: 'Erreur serveur' });
    }
  }
);


app.delete('/api/battues/:id', authMiddleware, adminMiddleware, async (req, res) => {
  try {
    const [r] = await db.query('DELETE FROM battues WHERE id = ?', [req.params.id]);
    if (!r.affectedRows) return res.status(404).json({ message: 'Battue non trouvée' });
    res.json({ message: 'Battue supprimée avec succès' });
  } catch (e) {
    console.error('DELETE /api/battues/:id', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

// ======================= FAVORIS (Battues) =======================
app.post('/api/favorites', authMiddleware, async (req, res) => {
  const { battue_id } = req.body || {};
  if (!battue_id) return res.status(400).json({ message: 'ID battue requis' });
  try {
    await db.query('INSERT INTO favorites (user_id, battue_id) VALUES (?, ?)', [req.user.id, battue_id]);
    res.status(201).json({ message: 'Ajouté aux favoris' });
  } catch (e) {
    if (e.code === 'ER_DUP_ENTRY') return res.status(409).json({ message: 'Déjà en favoris' });
    console.error('POST /api/favorites', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

app.get('/api/favorites', authMiddleware, async (req, res) => {
  try {
    const [rows] = await db.query(
      `SELECT b.* FROM favorites f
       JOIN battues b ON f.battue_id = b.id
       WHERE f.user_id = ?`,
      [req.user.id]
    );
    res.json(rows);
  } catch (e) {
    console.error('GET /api/favorites', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

app.delete('/api/favorites/:battue_id', authMiddleware, async (req, res) => {
  try {
    await db.query('DELETE FROM favorites WHERE user_id = ? AND battue_id = ?', [req.user.id, req.params.battue_id]);
    res.json({ message: 'Retiré des favoris' });
  } catch (e) {
    console.error('DELETE /api/favorites/:battue_id', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

// ======================= CONVERSATIONS / MESSAGES =======================

// Liste des conversations
app.get('/api/conversations', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;

    const sql = `
      SELECT
        c.id, c.is_group, c.title,

        u.id         AS peer_id,
        u.first_name AS peer_first_name,
        u.last_name  AS peer_last_name,
        u.phone      AS peer_phone,
        u.photoUrl   AS peer_photoUrl,

        lm.id        AS lm_id,
        lm.sender_id AS lm_sender_id,
        lm.body      AS lm_body,
        lm.created_at AS lm_created_at,

        c.created_at AS conv_created_at,

        CASE WHEN cf.user_id IS NULL THEN 0 ELSE 1 END AS is_favorite
      FROM conversations c
      JOIN conversation_participants cp_me
        ON cp_me.conversation_id = c.id AND cp_me.user_id = ?
      LEFT JOIN (
        SELECT m.*
        FROM messages m
        JOIN (
          SELECT conversation_id, MAX(id) AS max_id
          FROM messages
          GROUP BY conversation_id
        ) t ON t.conversation_id = m.conversation_id AND t.max_id = m.id
      ) lm ON lm.conversation_id = c.id
      LEFT JOIN conversation_participants cp_peer
        ON cp_peer.conversation_id = c.id AND cp_peer.user_id <> ? AND c.is_group = 0
      LEFT JOIN users u ON u.id = cp_peer.user_id
      LEFT JOIN conversation_favorites cf
        ON cf.user_id = ? AND cf.conversation_id = c.id
      WHERE cp_me.user_id = ?
      ORDER BY
        is_favorite DESC,
        (lm.id IS NULL) ASC,
        lm.created_at DESC,
        c.created_at DESC
    `;

    const [rows] = await db.query(sql, [userId, userId, userId, userId]);

    const out = rows.map(r => {
      const peer = r.peer_id ? {
        id: r.peer_id,
        first_name: r.peer_first_name,
        last_name: r.peer_last_name,
        phone: r.peer_phone,
        photoUrl: r.peer_photoUrl,
      } : null;

      const display_name = r.is_group
        ? (r.title || `Groupe #${r.id}`)
        : (peer ? buildDisplayName(peer.first_name, peer.last_name, peer.phone) : `Conversation #${r.id}`);

      return {
        id: r.id,
        is_group: !!r.is_group,
        title: r.title,
        peer,
        display_name,
        is_favorite: !!r.is_favorite,
        last_message: r.lm_id
          ? { id: r.lm_id, sender_id: r.lm_sender_id, body: r.lm_body, created_at: r.lm_created_at }
          : null,
      };
    });

    res.json(out);
  } catch (e) {
    console.error('GET /api/conversations', e);
    res.status(500).json({ message: 'Erreur serveur (conversations)' });
  }
});

// Search users (by name/phone)
app.get('/api/users/search', authMiddleware, async (req, res) => {
  const qRaw = String(req.query.q || '').trim();
  if (!qRaw) return res.json([]);

  const qLike = `%${qRaw}%`;
  const qPhone = normPhone(qRaw) || null;

  try {
    const [rows] = await db.query(
      `
      SELECT id, first_name, last_name, phone, photoUrl
      FROM users
      WHERE
        first_name LIKE ? OR
        last_name  LIKE ? OR
        CONCAT(first_name, ' ', last_name) LIKE ? OR
        phone LIKE ?
      ORDER BY first_name, last_name
      LIMIT 20
      `,
      [qLike, qLike, qLike, qPhone ? `%${qPhone}%` : qLike]
    );
    res.json(rows);
  } catch (e) {
    console.error('GET /api/users/search', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

// Créer/obtenir une 1:1 via numéro de téléphone
app.post('/api/conversations/by-phone', authMiddleware, async (req, res) => {
  const me = req.user.id;
  const phone = normPhone(req.body.phone || '');
  if (!phone) return res.status(400).json({ message: 'Téléphone invalide' });

  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [usr] = await conn.query(
      'SELECT id, first_name, last_name, phone, photoUrl FROM users WHERE phone = ? LIMIT 1',
      [phone]
    );
    if (!usr.length) { await conn.rollback(); return res.status(404).json({ message: 'Utilisateur introuvable' }); }
    const peer = usr[0];
    if (peer.id === me) { await conn.rollback(); return res.status(400).json({ message: 'Impossible de discuter avec vous-même' }); }

    const [exist] = await conn.query(
      `SELECT c.id FROM conversations c
       JOIN conversation_participants a ON a.conversation_id = c.id AND a.user_id = ?
       JOIN conversation_participants b ON b.conversation_id = c.id AND b.user_id = ?
       WHERE c.is_group = 0 LIMIT 1`,
      [me, peer.id]
    );

    let convId;
    let created = false;
    if (exist.length) {
      convId = exist[0].id;
    } else {
      const [ins] = await conn.query('INSERT INTO conversations (is_group) VALUES (0)');
      convId = ins.insertId;
      await conn.query(
        'INSERT INTO conversation_participants (conversation_id, user_id) VALUES (?, ?), (?, ?)',
        [convId, me, convId, peer.id]
      );
      created = true;
    }

    await conn.commit();

    const display_name = buildDisplayName(peer.first_name, peer.last_name, peer.phone);
    res.status(created ? 201 : 200).json({ id: convId, created, peer, display_name });
  } catch (e) {
    await conn.rollback();
    console.error('POST /api/conversations/by-phone', e);
    res.status(500).json({ message: 'Erreur serveur' });
  } finally {
    conn.release();
  }
});

// Créer une conversation (groupe ou 1:1 par peerId)
app.post('/api/conversations', authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { peerId, title, memberIds } = req.body || {};
  try {
    let conversationId;

    if (peerId) {
      const [exist] = await db.query(
        `SELECT c.id FROM conversations c
         JOIN conversation_participants a ON a.conversation_id = c.id AND a.user_id = ?
         JOIN conversation_participants b ON b.conversation_id = c.id AND b.user_id = ?
         WHERE c.is_group = 0 LIMIT 1`,
        [userId, peerId]
      );
      if (exist.length) return res.json({ id: exist[0].id });

      const [ins] = await db.query('INSERT INTO conversations (is_group) VALUES (0)');
      conversationId = ins.insertId;
      await db.query(
        'INSERT INTO conversation_participants (conversation_id, user_id) VALUES (?, ?), (?, ?)',
        [conversationId, userId, conversationId, peerId]
      );
    } else {
      const [ins] = await db.query('INSERT INTO conversations (is_group, title) VALUES (1, ?)', [title || null]);
      conversationId = ins.insertId;
      const participants = Array.from(new Set([userId, ...(memberIds || [])]));
      if (participants.length) {
        const placeholders = participants.map(() => '(?, ?, ?)').join(',');
        const values = participants.flatMap(uid => [conversationId, uid, uid === userId ? 'admin' : 'member']);
        await db.query(
          `INSERT INTO conversation_participants (conversation_id, user_id, role) VALUES ${placeholders}`,
          values
        );
      }
    }

    res.status(201).json({ id: conversationId });
  } catch (e) {
    console.error('POST /api/conversations', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

// Supprimer une conversation (et ses messages)
app.delete('/api/conversations/:id', authMiddleware, async (req, res) => {
  const me = req.user.id;
  const id = Number(req.params.id || 0);
  if (!id) return res.status(400).json({ message: 'id invalide' });

  try {
    const [part] = await db.query(
      'SELECT 1 FROM conversation_participants WHERE conversation_id = ? AND user_id = ?',
      [id, me]
    );
    if (!part.length) return res.status(403).json({ message: 'Accès interdit' });

    await db.query('DELETE FROM messages WHERE conversation_id = ?', [id]);
    await db.query('DELETE FROM conversation_participants WHERE conversation_id = ?', [id]);
    const [r] = await db.query('DELETE FROM conversations WHERE id = ?', [id]);
    if (!r.affectedRows) return res.status(404).json({ message: 'Conversation introuvable' });

    res.status(204).end();
  } catch (e) {
    console.error('DELETE /api/conversations/:id', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

// Messages d’une conversation
app.get('/api/messages/:conversationId', authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { conversationId } = req.params;
  const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);
  const before = req.query.before ? Number(req.query.before) : null;
  try {
    const [part] = await db.query(
      'SELECT 1 FROM conversation_participants WHERE conversation_id = ? AND user_id = ?',
      [conversationId, userId]
    );
    if (!part.length) return res.status(403).json({ message: 'Accès interdit' });

    const sql = `
      SELECT id, sender_id, body, attachments, created_at
      FROM messages
      WHERE conversation_id = ?
      ${before ? 'AND id < ?' : ''}
      ORDER BY id DESC
      LIMIT ?`;
    const params = before ? [conversationId, before, limit] : [conversationId, limit];
    const [rows] = await db.query(sql, params);
    res.json(rows.reverse());
  } catch (e) {
    console.error('GET /api/messages/:conversationId', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

// Envoi d’un message par REST
app.post('/api/messages', authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { conversationId, body, attachments } = req.body || {};
  if (!conversationId || (!body && !attachments)) {
    return res.status(400).json({ message: 'conversationId et body/attachments requis' });
  }
  try {
    const [part] = await db.query(
      'SELECT 1 FROM conversation_participants WHERE conversation_id = ? AND user_id = ?',
      [conversationId, userId]
    );
    if (!part.length) return res.status(403).json({ message: 'Accès interdit' });

    const [ins] = await db.query(
      'INSERT INTO messages (conversation_id, sender_id, body, attachments) VALUES (?, ?, ?, ?)',
      [conversationId, userId, body || null, attachments ? JSON.stringify(attachments) : null]
    );
    const [row] = await db.query('SELECT * FROM messages WHERE id = ?', [ins.insertId]);
    const message = row[0];

    const io = req.app.get('io');

    // Compat Flutter: event plat
    io.to(`conv:${conversationId}`).emit('message_created', {
      id: message.id,
      sender_id: userId,
      conversationId: Number(conversationId),
      text: message.body || '',
      type: message.body ? 'text' : 'file',
      createdAt: new Date(message.created_at || Date.now()).toISOString(),
    });

    // Event existant
    io.to(`conv:${conversationId}`).emit('message:new', { conversationId, message });

    const [members] = await db.query(
      'SELECT user_id FROM conversation_participants WHERE conversation_id = ?',
      [conversationId]
    );
    members.forEach(({ user_id }) =>
      io.to(`user:${user_id}`).emit('message:new', { conversationId, message })
    );

    res.status(201).json(message);
  } catch (e) {
    console.error('POST /api/messages', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

// Upload médias de chat (images/vidéos)
app.post('/api/uploads/chat', authMiddleware, upload.array('files'), async (req, res) => {
  try {
    const userId = req.user.id;
    const { conversationId } = req.body || {};
    if (!conversationId) return res.status(400).json({ message: 'conversationId requis' });

    const [part] = await db.query(
      'SELECT 1 FROM conversation_participants WHERE conversation_id = ? AND user_id = ? LIMIT 1',
      [conversationId, userId]
    );
    if (!part.length) return res.status(403).json({ message: 'Accès interdit' });

    const files = req.files || [];
    if (!files.length) return res.status(400).json({ message: 'Aucun fichier' });

    const baseUrl = `${req.protocol}://${req.get('host')}`;
    const attachments = files.map((f) => {
      const url = `${baseUrl}/uploads/chat/${path.basename(f.path)}`;
      const type = /^image\//.test(f.mimetype) ? 'image' : (/^video\//.test(f.mimetype) ? 'video' : 'file');
      return { type, url, name: f.originalname, size: f.size, mime: f.mimetype };
    });

    const [ins] = await db.query(
      'INSERT INTO messages (conversation_id, sender_id, body, attachments) VALUES (?, ?, ?, ?)',
      [conversationId, userId, null, JSON.stringify(attachments)]
    );
    const [row] = await db.query('SELECT * FROM messages WHERE id = ?', [ins.insertId]);
    const message = row[0];
    const createdAtIso = new Date(message.created_at || Date.now()).toISOString();

    const io = req.app.get('io');

    // 1) Emit compat "écran Flutter" : un event PLAT par fichier
    attachments.forEach((att) => {
      io.to(`conv:${conversationId}`).emit('message_created', {
        id: message.id,
        sender_id: userId,
        conversationId: Number(conversationId),
        type: att.type, // 'image' | 'video'
        url: att.url,
        name: att.name,
        mime: att.mime,
        createdAt: createdAtIso,
      });
    });

    // 2) Emit existant "message:new" : message complet
    io.to(`conv:${conversationId}`).emit('message:new', { conversationId: Number(conversationId), message });

    // 3) Notif par user
    const [members] = await db.query(
      'SELECT user_id FROM conversation_participants WHERE conversation_id = ?',
      [conversationId]
    );
    members.forEach(({ user_id }) =>
      io.to(`user:${user_id}`).emit('message:new', { conversationId: Number(conversationId), message })
    );

    res.json({ ok: true, files: attachments, message });
  } catch (e) {
    console.error('POST /api/uploads/chat', e);
    res.status(500).json({ message: 'Upload échoué' });
  }
});

// ======================= FAVORIS DE CONVERSATIONS =======================
app.get('/api/conv-favorites', authMiddleware, async (req, res) => {
  try {
    try {
      const [rows] = await db.query(
        'SELECT conversation_id FROM conversation_favorites WHERE user_id = ? ORDER BY created_at DESC',
        [req.user.id]
      );
      return res.json(rows.map(r => r.conversation_id));
    } catch (e) {
      if (e && e.code === 'ER_BAD_FIELD_ERROR') {
        const [rows] = await db.query(
          'SELECT conversation_id FROM conversation_favorites WHERE user_id = ?',
          [req.user.id]
        );
        return res.json(rows.map(r => r.conversation_id));
      }
      throw e;
    }
  } catch (e) {
    console.error('GET /api/conv-favorites', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

app.post('/api/conv-favorites/:conversationId/toggle', authMiddleware, async (req, res) => {
  const me = req.user.id;
  const convId = Number(req.params.conversationId || 0);
  if (!convId) return res.status(400).json({ message: 'id invalide' });

  try {
    const [part] = await db.query(
      'SELECT 1 FROM conversation_participants WHERE conversation_id = ? AND user_id = ? LIMIT 1',
      [convId, me]
    );
    if (!part.length) return res.status(403).json({ message: 'Accès interdit' });

    const [exist] = await db.query(
      'SELECT 1 FROM conversation_favorites WHERE user_id = ? AND conversation_id = ? LIMIT 1',
      [me, convId]
    );

    if (exist.length) {
      await db.query(
        'DELETE FROM conversation_favorites WHERE user_id = ? AND conversation_id = ?',
        [me, convId]
      );
      return res.json({ favorited: false });
    } else {
      await db.query(
        'INSERT INTO conversation_favorites (user_id, conversation_id) VALUES (?, ?)',
        [me, convId]
      );
      return res.json({ favorited: true });
    }
  } catch (e) {
    if (e.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({ message: 'Table conversation_favorites manquante' });
    }
    if (e.code === 'ER_DUP_ENTRY') {
      return res.json({ favorited: true });
    }
    console.error('POST /api/conv-favorites/:conversationId/toggle', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

// Compat: ajout direct
app.post('/api/conv-favorites', authMiddleware, async (req, res) => {
  const { conversation_id } = req.body || {};
  if (!conversation_id) return res.status(400).json({ message: 'conversation_id requis' });

  try {
    await db.query(
      'INSERT INTO conversation_favorites (user_id, conversation_id) VALUES (?, ?)',
      [req.user.id, conversation_id]
    );
    res.status(201).json({ message: 'Ajouté aux favoris' });
  } catch (e) {
    if (e.code === 'ER_DUP_ENTRY') return res.status(409).json({ message: 'Déjà en favoris' });
    console.error('POST /api/conv-favorites', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

// Compat: suppression directe
app.delete('/api/conv-favorites/:conversation_id', authMiddleware, async (req, res) => {
  try {
    await db.query(
      'DELETE FROM conversation_favorites WHERE user_id = ? AND conversation_id = ?',
      [req.user.id, req.params.conversation_id]
    );
    res.status(204).end();
  } catch (e) {
    console.error('DELETE /api/conv-favorites/:conversation_id', e);
    res.status(500).json({ message: 'Erreur serveur' });
  }
});

// ======================= GEOCODING (proxy serveur) =======================
// index.js — Google Places/Directions proxy (clean)

//const axios = require('axios');

// --- 0) Clé serveur unique (PAS de KEY2) ---
//const SERVER_KEY = process.env.GOOGLE_MAPS_SERVER_KEY2;
if (!SERVER_KEY) {
  console.error('[BOOT][ERROR] SERVER_KEY manquante (.env backend)');
  // Tu peux process.exit(1) si tu veux bloquer le boot
}

// --- 1) Autocomplete (Places) ---
app.get('/api/places', authMiddleware, async (req, res) => {
  try {
    const input = String(req.query.input || '').trim();
    if (!input) return res.json({ status: 'ZERO_RESULTS', predictions: [] });

    const { data } = await axios.get(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json',
      {
        params: {
          input,
          key: SERVER_KEY,            // <--- UNE SEULE CLÉ
          language: 'fr',
          components: 'country:fr',
        },
        timeout: 10000,
      }
    );

    // Si Google renvoie une erreur, propage-la telle quelle (plus lisible côté client)
    if (data.status && data.status !== 'OK') {
      return res.status(400).json(data);
    }
    res.json(data);
  } catch (e) {
    console.error('[PLACES][ERR]', e?.response?.data || e.message);
    res.status(500).json({ status: 'ERROR', error_message: 'proxy_failed' });
  }
});
app.get('/api/geocode', async (req, res) => {
  const id = req.reqId;
  const q = ((req.query.q ?? req.query.address) || '').toString().trim(); // tolère 'address'
  console.log(`[GEO ${id}] input=`, q);

  if (!q) {
    console.log(`[GEO ${id}] 400: Paramètre q manquant`);
    return res.status(400).json({ error: 'Paramètre q manquant' });
  }
  if (!SERVER_KEY) {
    console.log(`[GEO ${id}] 500: Clé serveur manquante`);
    return res.status(500).json({ error: 'Clé serveur manquante' });
  }

  try {
    const r = await axiosInstance.get('https://maps.googleapis.com/maps/api/geocode/json', {
      params: { address: q, key: SERVER_KEY, language: 'fr' },
      headers: { 'X-Req-Id': id },
      timeout: 10000,
    });

    console.log(`[GEO ${id}] status=${r.data?.status} results=${r.data?.results?.length || 0}`);

    if (r.data.status !== 'OK' || !r.data.results?.length) {
      return res.status(404).json({ error: r.data.status || 'Adresse introuvable', raw: r.data });
    }
    const best = r.data.results[0];
    const { lat, lng } = best.geometry.location;
    return res.json({ lat, lon: lng, displayName: best.formatted_address });
  } catch (e) {
    console.log(`[GEO ${id}] 500 ERROR:`, e.response?.status, e.response?.data || e.message);
    return res.status(500).json({ error: 'Erreur géocodage Google', details: e.message });
  }
});



// --- 2) Place Details ---
app.get('/api/place-details', authMiddleware, async (req, res) => {
  try {
    const place_id = String(req.query.place_id || '').trim();
    if (!place_id) return res.status(400).json({ status: 'INVALID_REQUEST' });

    const { data } = await axios.get(
      'https://maps.googleapis.com/maps/api/place/details/json',
      {
        params: {
          place_id,
          key: SERVER_KEY,
          language: 'fr',
        },
        timeout: 10000,
      }
    );

    if (data.status && data.status !== 'OK') {
      return res.status(400).json(data);
    }
    res.json(data);
  } catch (e) {
    console.error('[DETAILS][ERR]', e?.response?.data || e.message);
    res.status(500).json({ status: 'ERROR', error_message: 'proxy_failed' });
  }
});

// --- 3) Directions ---
app.get('/api/directions', authMiddleware, async (req, res) => {
  try {
    const { origin, destination, mode = 'driving' } = req.query;
    if (!origin || !destination) {
      return res.status(400).json({ status: 'INVALID_REQUEST' });
    }

    const { data } = await axios.get(
      'https://maps.googleapis.com/maps/api/directions/json',
      {
        params: {
          origin,
          destination,
          mode,
          language: 'fr',
          key: SERVER_KEY,
        },
        timeout: 10000,
      }
    );

    if (data.status && data.status !== 'OK') {
      return res.status(400).json(data);
    }
    res.json(data);
  } catch (e) {
    console.error('[DIRECTIONS][ERR]', e?.response?.data || e.message);
    res.status(500).json({ status: 'ERROR', error_message: 'proxy_failed' });
  }
});

// ======================= Static Map proxy =======================
app.get('/api/static-map', async (req, res) => {
  try {
    const { lat, lng, zoom = 13, size = '160x160' } = req.query;

    if (!lat || !lng) {
      return res.status(400).json({ error: 'lat and lng are required' });
    }

    const params = {
      center: `${lat},${lng}`,
      zoom: String(zoom),
      size: String(size),
      maptype: 'roadmap',
      markers: `color:red|${lat},${lng}`,
      key: SERVER_KEY,
    };

    const url = 'https://maps.googleapis.com/maps/api/staticmap';

    const googleResp = await axios.get(url, {
      params,
      responseType: 'arraybuffer',
    });

    res.set('Content-Type', 'image/png');
    return res.send(googleResp.data);
  } catch (err) {
    const status = err.response?.status || 500;
    const data = err.response?.data?.toString() || err.message;

    console.error('[STATIC MAP ERROR]', status, data);
    return res.status(status).json({ error: data });
  }
});


// ======================= Météo (Météo-Concept via Météo-France) =======================
const METEO_TOKEN = process.env.METEO_FRANCE_TOKEN;

// ---- mini cache mémoire (2 min)
const weatherCache = new Map(); // key: `${lat},${lon}`, value: { ts, data }

/** Reverse geocoding simple (facultatif, pour un nom de ville affichable) */
async function reverseGeocode(lat, lon) {
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lon}`;
    const r = await axios.get(url, { headers: { 'User-Agent': 'ChasseAlerte/1.0' }, timeout: 10000 });
    return (
      r?.data?.address?.city ||
      r?.data?.address?.town ||
      r?.data?.address?.village ||
      (r?.data?.display_name ? r.data.display_name.split(',')[0] : '') ||
      ''
    );
  } catch {
    return '';
  }
}
app.get('/api/battues/:id/stats/series', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const gran = req.query.granularity === 'month' ? 'month' : 'day';
    const bucketExpr = gran === 'month'
      ? "DATE_FORMAT(created_at,'%Y-%m-01')"
      : "DATE(created_at)";

    const [shots] = await db.execute(
      `SELECT ${bucketExpr} AS bucket, SUM(shots) AS shots
       FROM battue_stats
       WHERE battue_id=?
       GROUP BY bucket ORDER BY bucket`, [id]);

    const [seenHits] = await db.execute(
      `SELECT ${bucketExpr} AS bucket, SUM(animals_seen) AS seen, SUM(hits) AS hits
       FROM battue_stats
       WHERE battue_id=?
       GROUP BY bucket ORDER BY bucket`, [id]);

    res.json({ granularity: gran, shots, seenHits });
  } catch (e) {
    console.error('stats error:', e);
    res.status(500).json({ error: 'stats_failed', detail: e.message });
  }
});
app.post('/api/battues/:id/stats', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const {
      date, shots = 0, animals_seen = 0, hits = 0,
      participants = 0, duration_hours = 0
    } = req.body || {};

    // bucket = jour (tu peux aussi faire par mois si besoin)
    const [rows] = await db.execute(
      `INSERT INTO battue_stats (battue_id, created_at, shots, animals_seen, hits, participants, duration_hours)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         shots = VALUES(shots),
         animals_seen = VALUES(animals_seen),
         hits = VALUES(hits),
         participants = VALUES(participants),
         duration_hours = VALUES(duration_hours)`,
      [id, date, shots, animals_seen, hits, participants, duration_hours]
    );

    res.json({ ok: true, affected: rows.affectedRows });
  } catch (e) {
    console.error('save stats error:', e);
    res.status(500).json({ error: 'save_stats_failed', detail: e.message });
  }
});

app.post('/api/reports', validate(reportSchema), async (req, res) => {
  const {
    reported_first_name,
    reported_last_name,
    category,
    description,
    location,
    incident_at,
    is_anonymous,
    muted,
    blocked,
  } = req.body;

  try {
    const [result] = await db.query(
      `INSERT INTO reports (reported_first_name, reported_last_name, category, description, location, incident_at, is_anonymous, muted, blocked)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        reported_first_name,
        reported_last_name,
        category,
        description,
        location,
        incident_at,
        is_anonymous,
        muted,
        blocked,
      ]
    );
    res.json({ success: true, id: result.insertId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

app.get('/api/reports', async (req, res) => {
  try {
    const [rows] = await db.query('SELECT * FROM reports ORDER BY created_at DESC');
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

// ======================= ROUTE GEOENCODAGE GOOGLE =======================



/* ==================== Helpers d’interprétation ==================== */

// 1) Libellé “de base” stable à partir du code
function baseLabelFromCode(code) {
  const c = Number(code);
  if (!Number.isFinite(c)) return 'Variable';
  if (c === 0) return 'Ensoleillé';
  if ([1, 2].includes(c)) return 'Peu nuageux';
  if ([3, 4].includes(c)) return 'Nuageux';
  if ([5, 6, 7].includes(c)) return 'Très nuageux';
  if ([10, 11, 12].includes(c)) return 'Pluie faible';
  if ([13, 14, 15].includes(c)) return 'Pluie';
  if ([16, 17].includes(c)) return 'Averses';
  if ([20, 30, 31].includes(c)) return 'Brouillard / Brume';
  if (c >= 40 && c <= 49) return 'Pluie';     // ✅ important : 40–49 = pluie/averses
  if (c >= 60 && c <= 79) return 'Neige';
  if (c >= 80 && c <= 84) return 'Averses';
  if (c >= 90 && c <= 99) return 'Orage';
  if (c === 46) return 'Ciel variable';
  return 'Variable';
}

// 2) Règles d’affinage (anti-faux positifs, cohérence jour)
function refineLabelCategory({ code, rr = 0, probarain = 0, sunHours = null }) {
  let outCode = Number(code);
  let outLabel = baseLabelFromCode(outCode);

  // Déclasse pluie si totalement sec et proba très faible
  if (outCode >= 40 && outCode <= 49 && rr <= 0 && probarain < 20) {
    outCode = 3; // Nuageux
    outLabel = baseLabelFromCode(outCode);
  }

  // Corrige les cas trop optimistes : plein soleil mais soleil anémique + humidité
  if ((outCode === 0 || outCode === 1 || outCode === 2) && sunHours !== null) {
    if (sunHours < 1 && probarain >= 20) {
      outCode = 3; // Nuageux
      outLabel = baseLabelFromCode(outCode);
    } else if (sunHours < 2 && rr > 0) {
      outCode = 46; // Ciel variable
      outLabel = baseLabelFromCode(outCode);
    }
  }

  return { code: outCode, label: outLabel };
}

// 3) Libellé “riche” pour l’UI (non obligatoire)
function detailedLabel({ labelBase, rr = 0, probarain = 0, sunHours = null, wind10m = 0, gust = null, thunder = false }) {
  const wind = Number(wind10m || 0);
  const raf = gust != null ? Number(gust) : wind * 1.3;

  // Averses + éclaircies si journée changeante
  if (/Pluie|Averses/.test(labelBase) && sunHours !== null && sunHours >= 2 && probarain >= 30) {
    return 'Averses et éclaircies';
  }

  // Vent fort en surcouche
  if (raf >= 70 || wind >= 60) {
    if (/Orage/.test(labelBase)) return 'Orage et vent fort';
    if (/Pluie|Averses/.test(labelBase)) return 'Pluie et vent fort';
    if (/Neige/.test(labelBase)) return 'Neige et vent fort';
    if (/Brouillard/.test(labelBase)) return 'Brouillard, vent fort';
    return 'Vent fort';
  }

  if (thunder && !/Orage/.test(labelBase)) {
    return `${labelBase} (risque d'orage)`;
  }

  return labelBase;
}

// 4) Indice d’icône pour le front (jour/nuit + mix simple)
function iconHint({ code, hourLocal = null, sunHours = null }) {
  const c = Number(code);
  const isNight = hourLocal != null ? (hourLocal < 7 || hourLocal > 20) : false;

  if (c === 0) return { key: isNight ? 'clear_night' : 'sunny' };
  if ([1, 2].includes(c)) return { key: isNight ? 'few_clouds_night' : 'few_clouds' };
  if ([3, 4].includes(c)) return { key: 'cloudy' };
  if (c >= 40 && c <= 49) {
    if (sunHours != null && sunHours >= 2) return { key: 'shower_sunny' };
    return { key: isNight ? 'rain_night' : 'rain' };
  }
  if ([16, 17].includes(c) || (c >= 80 && c <= 84)) return { key: 'shower' };
  if (c >= 90 && c <= 99) return { key: 'thunder' };
  if (c >= 60 && c <= 79) return { key: 'snow' };
  if ([20, 30, 31].includes(c)) return { key: 'fog' };
  if (c === 46) return { key: 'variable' };
  return { key: 'variable' };
}

/** Choisit la prévision horaire la plus proche de "maintenant" */
function pickCurrentHour(nextHours) {
  const list = Array.isArray(nextHours?.forecast) ? nextHours.forecast : [];
  if (!list.length) return null;
  const now = Date.now();
  let best = null;
  let bestDiff = Infinity;
  for (const h of list) {
    const t = h?.datetime ? Date.parse(h.datetime) : NaN;
    if (!Number.isFinite(t)) continue;
    const diff = Math.abs(t - now);
    if (diff < bestDiff) {
      best = h;
      bestDiff = diff;
    }
  }
  return best;
}

/* ==================== Construction du bundle ==================== */
function toBundle(lat, lon, nextHoursData, dailyData, cityName = '') {
  // --- CURRENT (heure la plus proche) ---
  const h = pickCurrentHour(nextHoursData);
  const hourLocal = new Date().getHours();

  let current = null;
  if (h) {
    const refined = refineLabelCategory({
      code: h.weather,
      rr: Number(h.rr ?? h.rr1 ?? 0),
      probarain: null,
      sunHours: null
    });

    const labelRich = detailedLabel({
      labelBase: refined.label,
      rr: Number(h.rr ?? h.rr1 ?? 0),
      wind10m: Number(h.wind10m ?? 0),
      gust: Number(h.gust10m ?? h.gust ?? 0),
      thunder: Number(h.thunderstorm ?? 0) > 0
    });

    const hint = iconHint({ code: refined.code, hourLocal });

    current = {
      temp: Number(h.temp2m),
      code: refined.code,
      wind_kmh: Number(h.wind10m),
      label: refined.label,        // “propre”
      label_detailed: labelRich,   // enrichi pour l’UI
      icon_hint: hint.key,
      datetime: h.datetime || null,
    };
  }

  // --- DAILY (7 jours) ---
  const rawDays = Array.isArray(dailyData?.forecast) ? dailyData.forecast : [];
  const daily = rawDays.slice(0, 7).map((d) => {
    const refined = refineLabelCategory({
      code: d.weather,
      rr: Number(d.rr ?? 0),
      probarain: Number(d.probarain ?? d.probarain_day ?? 0),
      sunHours: d.sun_hours != null ? Number(d.sun_hours) : null
    });

    const labelRich = detailedLabel({
      labelBase: refined.label,
      rr: Number(d.rr ?? 0),
      probarain: Number(d.probarain ?? d.probarain_day ?? 0),
      sunHours: d.sun_hours != null ? Number(d.sun_hours) : null,
      wind10m: Number(d.wind10m ?? 0),
      gust: Number(d.gust10m ?? d.gust ?? 0),
      thunder: Number(d.thunderstorm ?? 0) > 0
    });

    const hint = iconHint({
      code: refined.code,
      hourLocal: 12, // icône “midi” pour la journée
      sunHours: d.sun_hours != null ? Number(d.sun_hours) : null
    });

    return {
      date: d.datetime || d.time || null,
      tmin: d.tmin != null ? Number(d.tmin) : null,
      tmax: d.tmax != null ? Number(d.tmax) : null,
      code: refined.code,
      wind_kmh: d.wind10m != null ? Number(d.wind10m) : null,
      probarain: d.probarain != null ? Number(d.probarain) : null,
      rr: d.rr != null ? Number(d.rr) : null,
      sun_hours: d.sun_hours != null ? Number(d.sun_hours) : null,
      label: refined.label,
      label_detailed: labelRich,
      icon_hint: hint.key,
    };
  });

  return {
    city: cityName || '',
    lat: Number(lat),
    lon: Number(lon),
    current,
    daily,
    raw: { nextHours: nextHoursData, daily: dailyData },
  };
}

/* ==================== Routes ==================== */

// -------- Route météo normalisée (pour l’app) --------
app.get('/api/meteo', async (req, res) => {
  try {
    const lat = Number(req.query.lat);
    const lon = Number(req.query.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
      return res.status(400).json({ error: 'Paramètres lat/lon invalides' });
    }
    if (!METEO_TOKEN) {
      return res.status(500).json({ error: 'Token Météo-France manquant (METEO_FRANCE_TOKEN)' });
    }

    // cache 2 minutes par tuile ~km
    const key = `${lat.toFixed(3)},${lon.toFixed(3)}`;
    const cached = weatherCache.get(key);
    if (cached && Date.now() - cached.ts < 120000) {
      return res.json(cached.data);
    }

    const nextHoursUrl = `https://api.meteo-concept.com/api/forecast/nextHours?token=${METEO_TOKEN}&latlng=${lat},${lon}`;
    const dailyUrl     = `https://api.meteo-concept.com/api/forecast/daily?token=${METEO_TOKEN}&latlng=${lat},${lon}`;

    const [hoursRes, dailyRes] = await Promise.all([
      axios.get(nextHoursUrl, { timeout: 10000 }),
      axios.get(dailyUrl, { timeout: 10000 }),
    ]);

    const city = await reverseGeocode(lat, lon).catch(() => '');
    const bundle = toBundle(lat, lon, hoursRes.data, dailyRes.data, city);

    weatherCache.set(key, { ts: Date.now(), data: bundle });
    return res.json(bundle);
  } catch (err) {
    console.error('METEO ERROR:', err?.response?.data || err.message);
    const status = err?.response?.status || 500;
    return res.status(status).json({ error: 'Service météo indisponible', detail: err?.message });
  }
});

// -------- Route brute (debug/validation) --------
app.get('/api/meteo/raw', async (req, res) => {
  try {
    const lat = Number(req.query.lat);
    const lon = Number(req.query.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
      return res.status(400).json({ error: 'Paramètres lat/lon invalides' });
    }
    if (!METEO_TOKEN) {
      return res.status(500).json({ error: 'Token Météo-France manquant (METEO_FRANCE_TOKEN)' });
    }

    const nextHoursUrl = `https://api.meteo-concept.com/api/forecast/nextHours?token=${METEO_TOKEN}&latlng=${lat},${lon}`;
    const dailyUrl     = `https://api.meteo-concept.com/api/forecast/daily?token=${METEO_TOKEN}&latlng=${lat},${lon}`;

    const [hoursRes, dailyRes] = await Promise.all([
      axios.get(nextHoursUrl, { timeout: 10000 }),
      axios.get(dailyUrl, { timeout: 10000 }),
    ]);

    const city = await reverseGeocode(lat, lon).catch(() => '');

    return res.json({
      city,
      lat,
      lon,
      nextHours: hoursRes.data,
      daily: dailyRes.data,
    });
  } catch (err) {
    console.error('METEO RAW ERROR:', err?.response?.data || err.message);
    const status = err?.response?.status || 500;
    return res.status(status).json({ error: 'Service météo indisponible', detail: err?.message });
  }
});


// ======================= Socket.IO =======================
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: (origin, cb) => cb(null, true),
    credentials: true,
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  },
});

// Auth handshake
io.use((socket, next) => {
  const token = socket.handshake.auth?.token || null;
  if (!token) return next(new Error('no_token'));
  jwt.verify(token, ACCESS_SECRET, (err, user) => {
    if (err) return next(new Error('invalid_token'));
    socket.user = user; // { id, role }
    next();
  });
});


io.on('connection', (socket) => {
  const userId = socket.user.id;

  socket.join(`user:${userId}`);

  // Rejoindre une conversation (nom standard)
  socket.on('conversation:join', (conversationId) => {
    socket.join(`conv:${conversationId}`);
  });

  // ✅ Alias pour compatibilité Flutter existante
  socket.on('join_conversation', (conversationId) => {
    socket.join(`conv:${conversationId}`);
  });

  // Indicateur de saisie
  socket.on('typing', ({ conversationId, isTyping }) => {
    socket.to(`conv:${conversationId}`).emit('typing', { userId, isTyping });
  });

  // Marquage lus
  socket.on('messages:read', async ({ conversationId, lastMessageId }) => {
    try {
      await db.query(
        `UPDATE conversation_participants
         SET last_read_message_id = GREATEST(COALESCE(last_read_message_id,0), ?)
         WHERE conversation_id = ? AND user_id = ?`,
        [lastMessageId, conversationId, userId]
      );
      io.to(`conv:${conversationId}`).emit('messages:read', { userId, lastMessageId });
    } catch (e) {
      console.error('socket messages:read', e);
    }
  });

  // ✅ Envoi d’un message texte via Socket.IO (compat ChatScreen)
  socket.on('send_message', async ({ conversationId, text, clientMsgId }) => {
    try {
      if (!conversationId || !String(text || '').trim()) return;

      const [part] = await db.query(
        'SELECT 1 FROM conversation_participants WHERE conversation_id = ? AND user_id = ? LIMIT 1',
        [conversationId, userId]
      );
      if (!part.length) return;

      const [ins] = await db.query(
        'INSERT INTO messages (conversation_id, sender_id, body, attachments) VALUES (?, ?, ?, ?)',
        [conversationId, userId, String(text).trim(), null]
      );
      const [row] = await db.query('SELECT * FROM messages WHERE id = ?', [ins.insertId]);
      const message = row[0];

      const createdAtIso = new Date(message.created_at || Date.now()).toISOString();

      io.to(`conv:${conversationId}`).emit('message_created', {
        id: message.id,
        sender_id: userId,
        conversationId: Number(conversationId),
        text: message.body || '',
        type: 'text',
        createdAt: createdAtIso,
        clientMsgId: clientMsgId || null,
      });

      io.to(`conv:${conversationId}`).emit('message:new', { conversationId: Number(conversationId), message });

      const [members] = await db.query(
        'SELECT user_id FROM conversation_participants WHERE conversation_id = ?',
        [conversationId]
      );
      members.forEach(({ user_id }) =>
        io.to(`user:${user_id}`).emit('message:new', { conversationId: Number(conversationId), message })
      );
    } catch (e) {
      console.error('socket send_message', e);
    }
  });
});

app.set('io', io);

// ======================= START =======================
function pickBestLanIp() {
  const bad = /virtual|vmware|hyper|loopback|vEthernet|docker|bridge|bluetooth|tunnel|local/i;
  const ifaces = os.networkInterfaces();
  const all = Object.entries(ifaces).flatMap(([name, list]) =>
    (list || []).map((i) => ({ name, ...i }))
  );
  const cand = all.filter(
    (i) =>
      i.family === 'IPv4' &&
      !i.internal &&
      !bad.test(i.name) &&
      i.address !== '127.0.0.1'
  );
  const score = (n) =>
    /wifi|wlan|wireless/i.test(n) ? 3 : /eth|ethernet/i.test(n) ? 2 : 1;
  cand.sort((a, b) => score(b.name) - score(a.name));
  return (cand[0] && cand[0].address) || 'localhost';
}

// ======================= START =======================

// On ne démarre le serveur que si on n'est pas en mode test
let serverInstance = null;
if (process.env.NODE_ENV !== 'test') {
  serverInstance = server.listen(PORT, HOST, () => {
    const lan = pickBestLanIp();
    console.log(
      'API ChasseAlerte (HTTP + Socket.IO) démarrée :\n' +
        ` - http://localhost:${PORT}\n` +
        ` - http://${lan}:${PORT}  (LAN)\n` +
        ` - http://10.0.2.2:${PORT}  (Android émulateur)`
    );
  });
}

// On exporte pour les tests
module.exports = {
  app,
  db,
  server,
  serverInstance,
};


// Export facult
