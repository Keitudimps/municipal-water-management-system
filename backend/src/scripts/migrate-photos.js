import 'dotenv/config';
import fs from 'node:fs/promises';
import path from 'node:path';
import { pool } from '../db.js';

const uploadDir = path.resolve(process.env.UPLOAD_DIR || './uploads');

function imageContentType(buf) {
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.subarray(0, 4).toString() === 'RIFF' && buf.subarray(8, 12).toString() === 'WEBP') return 'image/webp';
  if (buf.subarray(0, 3).toString() === 'GIF') return 'image/gif';
  return null;
}

try {
  const { rows } = await pool.query(
    `SELECT id, tracking_id, photo_url
       FROM reports
      WHERE photo_url LIKE '/uploads/%'
      ORDER BY id`,
  );
  let migrated = 0;

  for (const report of rows) {
    const match = /^\/uploads\/([a-f0-9]{32}\.(?:jpg|png|webp|gif))$/i.exec(report.photo_url);
    if (!match) throw new Error('A stored report photo has an invalid legacy path.');

    const filePath = path.join(uploadDir, match[1]);
    const image = await fs.readFile(filePath);
    const contentType = imageContentType(image);
    if (!contentType) throw new Error(`An existing report photo is not a supported image: ${match[1]}`);

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO report_photos (report_id, content_type, image_data)
         VALUES ($1, $2, $3)
         ON CONFLICT (report_id) DO NOTHING`,
        [report.id, contentType, image],
      );
      await client.query(
        'UPDATE reports SET photo_url = $1 WHERE id = $2',
        [`/api/reports/photo/${report.tracking_id}`, report.id],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }

    await fs.unlink(filePath);
    migrated += 1;
  }

  const remaining = await fs.readdir(uploadDir).catch((error) => {
    if (error.code === 'ENOENT') return [];
    throw error;
  });
  if (remaining.length) {
    throw new Error(`Photo migration left ${remaining.length} file(s) in the upload folder.`);
  }
  await fs.rmdir(uploadDir).catch((error) => {
    if (error.code !== 'ENOENT') throw error;
  });
  console.log(`Moved ${migrated} report photo(s) into the database; no upload files remain.`);
} finally {
  await pool.end();
}
