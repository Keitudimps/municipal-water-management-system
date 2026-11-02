import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import multer from 'multer';
import { pool } from './db.js';
import { HttpError } from './util.js';
import { reports } from './routes/reports.js';
import { admin } from './routes/admin.js';
import { auth } from './routes/auth.js';

const app = express();
app.set('trust proxy', 1);
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
const origins = (process.env.CORS_ORIGIN || '').split(',').map((s) => s.trim()).filter(Boolean);
app.use(cors({ origin: origins.length ? origins : true }));
app.use(express.json({ limit: '100kb' }));

app.get('/health', async (_req, res, next) => {
  try {
    const { rows } = await pool.query('SELECT postgis_version() AS postgis');
    res.json({ ok: true, postgis: rows[0].postgis });
  } catch (e) {
    next(e);
  }
});

app.use('/api/reports', reports);
app.use('/api/auth', auth);
app.use('/api/admin', admin);

app.use((_req, _res, next) => next(new HttpError(404, 'Not found.')));

// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  if (err instanceof HttpError) return res.status(err.status).json({ error: err.message });
  if (err instanceof multer.MulterError) {
    const tooBig = err.code === 'LIMIT_FILE_SIZE';
    return res.status(tooBig ? 413 : 400).json({ error: tooBig ? 'Photo is too large (max 8 MB).' : err.message });
  }
  if (err?.type === 'entity.parse.failed') return res.status(400).json({ error: 'Invalid JSON.' });
  console.error(err);
  res.status(500).json({ error: 'Something went wrong on our side.' });
});

const port = Number(process.env.PORT || 4000);
app.listen(port, () => console.log(`AquaAlert API listening on http://localhost:${port}`));
