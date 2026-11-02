import { Router } from 'express';
import crypto from 'node:crypto';
import { query } from '../db.js';
import { hashPassword, hashSessionToken, verifyPassword } from '../auth-security.js';
import { HttpError, wrap } from '../util.js';

export const auth = Router();

const SESSION_HOURS = 12;
const failedLogins = new Map();
const loginWindowMs = 15 * 60 * 1000;
const maxFailedLogins = 10;

function publicUser(user) {
  return {
    id: user.id,
    userNumber: user.user_number,
    displayName: user.display_name,
    role: user.role,
  };
}

function normalizedUserNumber(value) {
  return typeof value === 'string' ? value.trim().toUpperCase() : '';
}

function recordFailedLogin(key) {
  const now = Date.now();
  const attempts = (failedLogins.get(key) || []).filter((time) => now - time < loginWindowMs);
  attempts.push(now);
  failedLogins.set(key, attempts);
  return attempts.length >= maxFailedLogins;
}

export const requireAuth = wrap(async (req, _res, next) => {
  const match = /^Bearer ([A-Za-z0-9_-]{40,60})$/.exec(req.get('authorization') || '');
  if (!match) throw new HttpError(401, 'Please sign in to access the dashboard.');

  const tokenHash = hashSessionToken(match[1]);
  const { rows } = await query(
    `SELECT u.id, u.user_number, u.display_name, u.role
       FROM dashboard_sessions s
       JOIN dashboard_users u ON u.id = s.user_id
      WHERE s.token_hash = $1 AND s.expires_at > now() AND u.active`,
    [tokenHash],
  );
  if (!rows[0]) throw new HttpError(401, 'Your session has expired. Please sign in again.');
  req.user = {
    id: rows[0].id,
    userNumber: rows[0].user_number,
    displayName: rows[0].display_name,
    role: rows[0].role,
    tokenHash,
  };
  next();
});

export function requireAdmin(req, _res, next) {
  if (req.user?.role !== 'admin') return next(new HttpError(403, 'Administrator access is required.'));
  next();
}

auth.post('/login', wrap(async (req, res) => {
  const userNumber = normalizedUserNumber(req.body?.userNumber);
  const password = req.body?.password;
  if (!/^[A-Z0-9][A-Z0-9._-]{1,31}$/.test(userNumber) || typeof password !== 'string' || password.length > 128) {
    throw new HttpError(400, 'Enter your user number and password.');
  }

  const limitKey = req.ip;
  const attempts = (failedLogins.get(limitKey) || []).filter((time) => Date.now() - time < loginWindowMs);
  if (attempts.length >= maxFailedLogins) throw new HttpError(429, 'Too many sign-in attempts. Try again in 15 minutes.');

  const { rows } = await query(
    `SELECT id, user_number, display_name, password_hash, role
       FROM dashboard_users
      WHERE user_number = $1 AND active`,
    [userNumber],
  );
  const user = rows[0];
  if (!user || !(await verifyPassword(password, user.password_hash))) {
    if (recordFailedLogin(limitKey)) throw new HttpError(429, 'Too many sign-in attempts. Try again in 15 minutes.');
    throw new HttpError(401, 'User number or password is incorrect.');
  }

  failedLogins.delete(limitKey);
  const token = crypto.randomBytes(32).toString('base64url');
  const tokenHash = hashSessionToken(token);
  await query('DELETE FROM dashboard_sessions WHERE expires_at <= now()');
  await query(
    `INSERT INTO dashboard_sessions (token_hash, user_id, expires_at)
     VALUES ($1, $2, now() + ($3 * interval '1 hour'))`,
    [tokenHash, user.id, SESSION_HOURS],
  );
  res.json({ token, user: publicUser(user), expiresIn: SESSION_HOURS * 60 * 60 });
}));

auth.get('/me', requireAuth, (req, res) => res.json(publicUser({
  id: req.user.id,
  user_number: req.user.userNumber,
  display_name: req.user.displayName,
  role: req.user.role,
})));

auth.post('/logout', requireAuth, wrap(async (req, res) => {
  await query('DELETE FROM dashboard_sessions WHERE token_hash = $1', [req.user.tokenHash]);
  res.status(204).end();
}));

export async function createStaffUser({ userNumber, displayName, password }) {
  const normalized = normalizedUserNumber(userNumber);
  const name = typeof displayName === 'string' ? displayName.trim() : '';
  if (!/^[A-Z0-9][A-Z0-9._-]{1,31}$/.test(normalized)) {
    throw new HttpError(400, 'User number must be 2–32 letters, numbers, dots, underscores or hyphens.');
  }
  if (!name || name.length > 80) throw new HttpError(400, 'Name is required (up to 80 characters).');
  if (typeof password !== 'string' || password.length < 12 || password.length > 128) {
    throw new HttpError(400, 'Password must be between 12 and 128 characters.');
  }
  const passwordHash = await hashPassword(password);
  try {
    const { rows } = await query(
      `INSERT INTO dashboard_users (user_number, display_name, password_hash, role)
       VALUES ($1, $2, $3, 'staff')
       RETURNING id, user_number, display_name, role`,
      [normalized, name, passwordHash],
    );
    return {
      id: rows[0].id,
      userNumber: rows[0].user_number,
      displayName: rows[0].display_name,
      role: rows[0].role,
    };
  } catch (e) {
    if (e.code === '23505') throw new HttpError(409, 'That user number is already in use.');
    throw e;
  }
}
