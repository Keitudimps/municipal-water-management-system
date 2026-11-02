import { Router } from 'express';
import multer from 'multer';
import { pool, query } from '../db.js';
import {
  HttpError, wrap, parseReport, phoneKey, toReport, toCityReport,
  reverseGeocode, REPORT_COLS, CITY_REPORT_COLS,
} from '../util.js';

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 8 * 1024 * 1024, files: 1 } });

/** Accept only real JPEG / PNG / WebP / GIF files (checks the file header, not the name). */
function imageContentType(buf) {
  if (buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.subarray(0, 4).toString() === 'RIFF' && buf.subarray(8, 12).toString() === 'WEBP') return 'image/webp';
  if (buf.subarray(0, 3).toString() === 'GIF') return 'image/gif';
  return null;
}

// Tiny in-memory rate limiter (per hour) for the public endpoints.
const hits = new Map();
function limited(key, max = 10) {
  const now = Date.now();
  const list = (hits.get(key) || []).filter((t) => now - t < 3600_000);
  list.push(now);
  hits.set(key, list);
  return list.length > max;
}

export const reports = Router();

reports.post('/', upload.single('photo'), wrap(async (req, res) => {
  const deviceId = req.get('x-device-id');
  if (!deviceId || deviceId.length > 100) throw new HttpError(400, 'Missing X-Device-Id header.');
  if (limited('d:' + deviceId) || limited('ip:' + req.ip)) throw new HttpError(429, 'Too many reports. Please try again later.');

  const d = parseReport(req.body);
  const photoType = req.file ? imageContentType(req.file.buffer) : null;
  if (req.file && !photoType) throw new HttpError(400, 'Photo must be a JPEG, PNG, WebP or GIF image.');
  const radius = Number(process.env.DUPLICATE_RADIUS_M || 50);

  // PostGIS: is there already an open report of the same kind within `radius` metres in the last 24h?
  const dup = await query(
    `SELECT id, tracking_id FROM reports
      WHERE status <> 'Resolved' AND leak_type = $3 AND created_at > now() - interval '24 hours'
        AND ST_DWithin(location, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $4)
      ORDER BY ST_Distance(location, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography)
      LIMIT 1`,
    [d.lng, d.lat, d.leakType, radius],
  );
  const dupRow = dup.rows[0] || null;
  const address = await reverseGeocode(d.lat, d.lng);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `WITH ins AS (
         INSERT INTO reports (device_id, leak_type, severity, location, notes, reporter_name, reporter_phone,
                              phone_key, duplicate_of, address, street, city)
         VALUES ($1, $2, $3, ST_SetSRID(ST_MakePoint($4, $5), 4326)::geography, $6, $7, $8, $9, $10, $11, $12, $13)
         RETURNING id, tracking_id, leak_type, severity, status, address, street, city, created_at,
                   ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng
       ), act AS (
         INSERT INTO report_activity (report_id, actor, message)
         SELECT id, 'System', $14 FROM ins
       )
       SELECT * FROM ins`,
      [
        deviceId, d.leakType, d.severity, d.lng, d.lat, d.notes, d.name, d.phone, d.phoneKey,
        dupRow?.id ?? null, address?.address ?? null, address?.street ?? null, address?.city ?? null,
        dupRow ? `New report received (possible duplicate of ${dupRow.tracking_id})` : 'New report received',
      ],
    );
    const row = rows[0];
    if (req.file) {
      await client.query(
        'INSERT INTO report_photos (report_id, content_type, image_data) VALUES ($1, $2, $3)',
        [row.id, photoType, req.file.buffer],
      );
      await client.query(
        'UPDATE reports SET photo_url = $1 WHERE id = $2',
        [`/api/reports/photo/${row.tracking_id}`, row.id],
      );
    }
    await client.query('COMMIT');
    res.status(201).json({ ...toReport(row), possibleDuplicateOf: dupRow?.tracking_id ?? null });
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}));

reports.get('/photo/:trackingId', wrap(async (req, res) => {
  const { rows } = await query(
    `SELECT p.content_type, p.image_data
       FROM report_photos p JOIN reports r ON r.id = p.report_id
      WHERE r.tracking_id = $1`,
    [req.params.trackingId],
  );
  if (!rows[0]) throw new HttpError(404, 'Photo not found.');
  res.set('Content-Type', rows[0].content_type);
  res.set('Cache-Control', 'private, max-age=3600');
  res.send(rows[0].image_data);
}));

// "My reports": every report made with a phone number, including ones from other devices.
// POST (not GET) so the number never appears in URLs or server logs.
reports.post('/lookup', wrap(async (req, res) => {
  const raw = String(req.body?.phone ?? '').trim();
  const key = phoneKey(raw);
  if (!key) throw new HttpError(400, 'Enter a valid phone number.');
  if (limited('lip:' + req.ip, 120) || limited('lph:' + key, 60)) throw new HttpError(429, 'Too many lookups. Please try again later.');

  // Reports this device made before phone numbers were required are linked to the number now entered.
  const deviceId = req.get('x-device-id');
  if (deviceId) {
    await query(
      `UPDATE reports SET reporter_phone = COALESCE(reporter_phone, $2), phone_key = $3
        WHERE device_id = $1 AND phone_key IS NULL`,
      [deviceId, raw.slice(0, 30), key],
    );
  }

  const { rows } = await query(
    `SELECT ${REPORT_COLS} FROM reports WHERE phone_key = $1 ORDER BY created_at DESC LIMIT 200`,
    [key],
  );
  res.json(rows.map(toReport));
}));

// Public city search returns tracking/status information and street name only, never reporter details or house numbers.
reports.get('/city', wrap(async (req, res) => {
  const city = String(req.query.city ?? '').trim();
  if (city.length < 2 || city.length > 80) {
    throw new HttpError(400, 'Enter a city name between 2 and 80 characters.');
  }
  if (limited('city:' + req.ip, 120)) throw new HttpError(429, 'Too many city searches. Please try again later.');

  const { rows } = await query(
    `SELECT ${CITY_REPORT_COLS}
       FROM reports
      WHERE lower(city) = lower($1)
      ORDER BY created_at DESC
      LIMIT 100`,
    [city],
  );
  res.json(rows.map(toCityReport));
}));

// Public status lookup by tracking id
reports.get('/:trackingId', wrap(async (req, res) => {
  const { rows } = await query(`SELECT ${REPORT_COLS} FROM reports WHERE tracking_id = $1`, [req.params.trackingId]);
  if (!rows[0]) throw new HttpError(404, 'Report not found.');
  res.json(toReport(rows[0]));
}));
