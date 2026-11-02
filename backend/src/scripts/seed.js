import { pool } from '../db.js';
import { phoneKey } from '../util.js';

// Sample incidents for the dashboard. Re-running replaces the previous sample data.
const rows = [
  ['AQ-9210', 'burst_pipe', 'emergency', 'In Progress', 40.7128, -74.006, '412 Westview Terrace, North Sector',
    '6-inch cast iron main rupture. Significant flooding in the basement of a nearby residential complex. Pressure drop reported across 4 blocks.',
    'Marcus Holloway', '+1 555 012 4455', 'Delta Quick-Response', 'Sarah Jenkins', 'Arrived at 08:35 AM', 240, -12, 21, 95],
  ['AQ-9211', 'visible_leak', 'minor', 'Received', 40.7306, -73.9866, '88 King St, Downtown District',
    'Slow leak from the base of a hydrant with water pooling at the curb. No pressure complaints so far.',
    'Priya Nair', '+1 555 013 2210', null, null, null, 40, -1, null, 40],
  ['AQ-9212', 'running_water', 'major', 'Received', 40.7411, -73.9897, '15 Oak Lane, Residential Zone 4',
    'Wet patch spreading across a front lawn. Resident reports reduced water pressure since morning.',
    'Tom Becker', '+1 555 014 7782', 'Bravo Crew', 'Daniel Ortiz', 'En route · ETA 20 min', 90, -4, null, 20],
  ['AQ-9213', 'equipment', 'major', 'Delayed', 40.7001, -74.0113, 'Industrial Way, East Port',
    'Seepage visible at the valve vault cover. Access is blocked by delivery vehicles.',
    'Lena Park', '+1 555 015 9034', 'Echo Crew', 'Lena Ortiz', 'Delayed · access issue', 60, -3, null, 10],
];

await pool.query(`DELETE FROM reports WHERE device_id = 'seed'`);

// Sample field teams (the dashboard counts its "teams assigned" figure from this table)
for (const [name, lead] of [
  ['Alpha Crew', 'Ravi Shah'],
  ['Bravo Crew', 'Daniel Ortiz'],
  ['Delta Quick-Response', 'Sarah Jenkins'],
  ['Echo Crew', 'Lena Ortiz'],
]) {
  await pool.query(`INSERT INTO teams (name, lead) VALUES ($1, $2) ON CONFLICT (name) DO UPDATE SET lead = EXCLUDED.lead`, [name, lead]);
}

for (const r of rows) {
  const [tid, type, sev, status, lat, lng, addr, notes, name, phone, team, lead, arrival, vol, psi, respMin, agoMin] = r;
  await pool.query(
    `WITH ins AS (
       INSERT INTO reports (tracking_id, device_id, leak_type, severity, status, location, address, notes,
                            reporter_name, reporter_phone, phone_key, assigned_team, team_lead, arrival_note,
                            volume_loss_gph, pressure_psi, created_at, first_response_at)
       VALUES ($1, 'seed', $2, $3, $4, ST_SetSRID(ST_MakePoint($6::float8, $5::float8), 4326)::geography, $7, $8, $9, $10, $18, $11, $12, $13,
               $14, $15, now() - make_interval(mins => $17::int),
               CASE WHEN $16::int IS NULL THEN NULL ELSE now() - make_interval(mins => $17::int) + make_interval(mins => $16::int) END)
       RETURNING id
     )
     INSERT INTO report_activity (report_id, actor, message, created_at)
     SELECT id, 'System', 'New report received', now() - make_interval(mins => $17::int) FROM ins`,
    [tid, type, sev, status, lat, lng, addr, notes, name, phone, team, lead, arrival, vol, psi, respMin, agoMin, phoneKey(phone)],
  );
}

await pool.query(`
  INSERT INTO report_activity (report_id, actor, message, created_at)
  SELECT id, 'Sarah Jenkins', 'Main valve secured. Excavation started on the 6-inch fracture.', now() - interval '35 minutes'
  FROM reports WHERE tracking_id = 'AQ-9210'`);
await pool.query(`
  INSERT INTO report_activity (report_id, actor, message, created_at)
  SELECT id, 'System', 'Pressure recovery confirmed at North Pump Station. Flow redirected.', now() - interval '10 minutes'
  FROM reports WHERE tracking_id = 'AQ-9210'`);

console.log(`Seeded ${rows.length} sample incidents.`);
await pool.end();
