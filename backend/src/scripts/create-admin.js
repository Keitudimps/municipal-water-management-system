import { pool } from '../db.js';
import crypto from 'node:crypto';
import { hashPassword } from '../auth-security.js';

const lockId = 1095781964;

function readInput(label, { hidden = false } = {}) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error('Run this command in an interactive terminal so the password can be entered privately.');
  }
  process.stdout.write(label);
  return new Promise((resolve, reject) => {
    const wasRaw = process.stdin.isRaw;
    process.stdin.setRawMode(true);
    process.stdin.resume();
    let value = '';
    const finish = (error) => {
      process.stdin.removeListener('data', onData);
      process.stdin.setRawMode(wasRaw);
      process.stdout.write('\n');
      if (error) reject(error);
      else resolve(value);
    };
    const onData = (chunk) => {
      for (const character of chunk.toString('utf8')) {
        if (character === '\u0003') return finish(new Error('Setup cancelled.'));
        if (character === '\r' || character === '\n') return finish();
        if (character === '\u007f' || character === '\b') {
          if (value.length) {
            value = value.slice(0, -1);
            process.stdout.write('\b \b');
          }
          continue;
        }
        value += character;
        process.stdout.write(hidden ? '*' : character);
      }
    };
    process.stdin.on('data', onData);
  });
}

async function provisionAdmin({ userNumber, displayName, password }) {
  const passwordHash = await hashPassword(password);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock($1)', [lockId]);
    const admins = await client.query("SELECT count(*)::int AS count FROM dashboard_users WHERE role = 'admin'");
    if (admins.rows[0].count > 0) throw new Error('An administrator already exists.');
    await client.query(
      `INSERT INTO dashboard_users (user_number, display_name, password_hash, role)
       VALUES ($1, $2, $3, 'admin')`,
      [userNumber, displayName, passwordHash],
    );
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    if (error.code === '23505') throw new Error('That user number is already in use.');
    throw error;
  } finally {
    client.release();
  }
}

try {
  if (process.argv.includes('--generate')) {
    const { rows } = await pool.query("SELECT count(*)::int AS count FROM dashboard_users WHERE role = 'admin'");
    if (rows[0].count > 0) throw new Error('An administrator already exists. Sign in and add staff from the dashboard.');
    const credentials = {
      userNumber: `AQ-ADMIN-${crypto.randomBytes(3).toString('hex').toUpperCase()}`,
      displayName: 'AquaAlert Administrator',
      password: crypto.randomBytes(24).toString('base64url'),
    };
    await provisionAdmin(credentials);
    console.log('Administrator created. Save these credentials; the password cannot be retrieved later.');
    console.log(`User number: ${credentials.userNumber}`);
    console.log(`Password: ${credentials.password}`);
  } else if (process.stdin.isTTY) {
    const { rows } = await pool.query("SELECT count(*)::int AS count FROM dashboard_users WHERE role = 'admin'");
    if (rows[0].count > 0) throw new Error('An administrator already exists. Sign in and add staff from the dashboard.');

    const userNumber = (await readInput('Admin user number: ')).trim().toUpperCase();
    const displayName = (await readInput('Admin name: ')).trim();
    const password = await readInput('Password (minimum 12 characters): ', { hidden: true });
    const confirmation = await readInput('Confirm password: ', { hidden: true });
    if (!/^[A-Z0-9][A-Z0-9._-]{1,31}$/.test(userNumber)) {
      throw new Error('User number must be 2–32 letters, numbers, dots, underscores or hyphens.');
    }
    if (!displayName || displayName.length > 80) throw new Error('Name is required (up to 80 characters).');
    if (password.length < 12 || password.length > 128) throw new Error('Password must be between 12 and 128 characters.');
    if (password !== confirmation) throw new Error('Passwords do not match.');

    await provisionAdmin({ userNumber, displayName, password });
    console.log('Administrator created. Sign in to the dashboard with that user number and password.');
  } else {
    throw new Error('Run this command in an interactive terminal, or pass --generate for random credentials.');
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
