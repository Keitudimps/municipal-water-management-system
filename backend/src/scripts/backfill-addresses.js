import { pool } from '../db.js';
import { reverseGeocode } from '../util.js';

const batchSize = 25;

try {
  const { rows } = await pool.query(
    `SELECT tracking_id, ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng
       FROM reports
      WHERE city IS NULL OR street IS NULL OR address IS NULL
      ORDER BY created_at
      LIMIT $1`,
    [batchSize],
  );
  let updated = 0;
  let unresolved = 0;

  for (const [index, report] of rows.entries()) {
    if (index > 0) await new Promise((resolve) => setTimeout(resolve, 1100));
    const location = await reverseGeocode(report.lat, report.lng);
    if (!location) {
      unresolved += 1;
      continue;
    }
    await pool.query(
      `UPDATE reports
          SET address = COALESCE(address, $1),
              street = COALESCE(street, $2),
          city = COALESCE(city, $3)
        WHERE tracking_id = $4`,
      [location.address, location.street, location.city, report.tracking_id],
    );
    updated += 1;
  }

  console.log(`Address lookup updated ${updated} report(s); ${unresolved} could not be geocoded.`);
  if (rows.length === batchSize) {
    console.log(`More older reports may need lookup; run this command again to process the next batch.`);
  }
} finally {
  await pool.end();
}
