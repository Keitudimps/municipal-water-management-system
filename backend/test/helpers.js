// Shared helpers for the AquaAlert backend test suite.
// Tests run the real Express app in-process against a real PostgreSQL + PostGIS database.
import crypto from 'node:crypto';
import { pool } from '../src/db.js';
import { hashPassword, hashSessionToken } from '../src/auth-security.js';

export const BASE = `http://127.0.0.1:${process.env.PORT}`;

let ipCounter = 0;
/** A fresh fake client IP per call (the API trusts one proxy hop), so the per-IP rate limiter never leaks between tests. */
export const freshIp = () => `10.${(++ipCounter >> 8) & 255}.${ipCounter & 255}.7`;
let devCounter = 0;
export const freshDevice = () => `test-dev-${Date.now()}-${++devCounter}`;

export const CT = { lat: -33.9249, lng: 18.4241 }; // Cape Town CBD (pilot municipality)
/** Latitude offset (degrees) that moves a point about `m` metres north. */
export const northBy = (m) => m / 111_195;

export const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 1)]);
export const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(64, 2)]);

export function defaults(over = {}) {
  return { leak_type: 'burst_pipe', severity: 'major', lat: CT.lat, lng: CT.lng, phone: '+27 82 123 4567', ...over };
}

export async function postReport({ fields = {}, photo, device = freshDevice(), ip = freshIp(), omitDevice = false } = {}) {
  const fd = new FormData();
  for (const [k, v] of Object.entries(defaults(fields))) if (v !== undefined) fd.append(k, String(v));
  if (photo) fd.append('photo', new Blob([photo.buf], { type: photo.type || 'image/jpeg' }), photo.name || 'leak.jpg');
  const headers = { 'x-forwarded-for': ip };
  if (!omitDevice) headers['x-device-id'] = device;
  const res = await fetch(`${BASE}/api/reports`, { method: 'POST', headers, body: fd });
  const text = await res.text();
  let body = null; try { body = JSON.parse(text); } catch { /* not JSON */ }
  return { status: res.status, body, text, device, ip };
}

export async function api(method, path, { token, json, ip = freshIp(), headers = {} } = {}) {
  const h = { 'x-forwarded-for': ip, ...headers };
  if (token) h.authorization = `Bearer ${token}`;
  if (json !== undefined) h['content-type'] = 'application/json';
  const res = await fetch(`${BASE}${path}`, { method, headers: h, body: json !== undefined ? (typeof json === 'string' ? json : JSON.stringify(json)) : undefined });
  const text = await res.text();
  let body = null; try { body = JSON.parse(text); } catch { /* not JSON */ }
  return { status: res.status, body, text };
}

export async function resetDb() {
  await pool.query(`TRUNCATE report_activity, report_photos, reports, dashboard_sessions, dashboard_users, teams RESTART IDENTITY CASCADE`);
  await pool.query(`ALTER SEQUENCE report_seq RESTART WITH 10000`);
}

export async function makeUser({ number = 'STAFF01', name = 'Test Staff', password = 'correct-horse-battery', role = 'staff' } = {}) {
  const hash = await hashPassword(password);
  const { rows } = await pool.query(
    `INSERT INTO dashboard_users (user_number, display_name, password_hash, role) VALUES ($1,$2,$3,$4) RETURNING id`,
    [number, name, hash, role]);
  return { id: rows[0].id, number, password };
}

export async function login(number, password, ip = freshIp()) {
  const r = await api('POST', '/api/auth/login', { json: { userNumber: number, password }, ip });
  return r;
}

export async function signedInToken(opts) {
  const u = await makeUser(opts);
  const r = await login(u.number, u.password);
  return { token: r.body.token, user: u };
}

export { pool, crypto, hashSessionToken };
