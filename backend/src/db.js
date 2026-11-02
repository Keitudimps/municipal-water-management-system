import 'dotenv/config';
import pg from 'pg';

export const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://aquaalert:aquaalert@localhost:5432/aquaalert',
});

export const query = (text, params) => pool.query(text, params);
