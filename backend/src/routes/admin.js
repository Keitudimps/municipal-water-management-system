import { Router } from 'express';
import { pool, query } from '../db.js';
import { HttpError, wrap, toIncident, INCIDENT_COLS, STATUSES } from '../util.js';
import { createStaffUser, requireAdmin, requireAuth } from './auth.js';

export const admin = Router();

admin.use(requireAuth);

// List incidents. Optional: ?status=&q=&lat=&lng=&radius=  (radius in metres, PostGIS ST_DWithin)
admin.get('/incidents', wrap(async (req, res) => {
  const where = [];
  const params = [];
  const add = (v) => (params.push(v), `$${params.length}`);
  let distance = 'NULL::int';
  let order = `(status = 'Resolved'),
               CASE severity WHEN 'emergency' THEN 0 WHEN 'major' THEN 1 ELSE 2 END,
               created_at DESC`;

  if (req.query.status) {
    if (!STATUSES.includes(req.query.status)) throw new HttpError(400, 'Invalid status.');
    where.push(`status = ${add(req.query.status)}`);
  }
  if (req.query.q) {
    const term = String(req.query.q).slice(0, 80);
    const p = add(`%${term}%`);
    const digits = term.replace(/\D/g, '');
    const phoneMatch = digits.length >= 3
      ? ` OR regexp_replace(coalesce(reporter_phone, ''), '[^0-9]', '', 'g') ILIKE ${add(`%${digits}%`)}`
      : '';
    where.push(`(tracking_id ILIKE ${p} OR address ILIKE ${p} OR city ILIKE ${p} OR leak_type ILIKE ${p} OR notes ILIKE ${p} OR reporter_phone ILIKE ${p}${phoneMatch})`);
  }
  if (req.query.lat && req.query.lng) {
    const lat = Number(req.query.lat);
    const lng = Number(req.query.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) throw new HttpError(400, 'Invalid coordinates.');
    const pLng = add(lng);
    const pLat = add(lat);
    const pt = `ST_SetSRID(ST_MakePoint(${pLng}, ${pLat}), 4326)::geography`;
    distance = `ST_Distance(location, ${pt})::int`;
    order = `ST_Distance(location, ${pt})`;
    if (req.query.radius) where.push(`ST_DWithin(location, ${pt}, ${add(Number(req.query.radius) || 1000)})`);
  }

  const { rows } = await query(
    `SELECT ${INCIDENT_COLS}, ${distance} AS distance_m FROM reports
      ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
      ORDER BY ${order} LIMIT 100`,
    params,
  );
  res.json(rows.map((r) => toIncident(r, req)));
}));

admin.get('/incidents/:id', wrap(async (req, res) => {
  const { rows } = await query(`SELECT ${INCIDENT_COLS} FROM reports WHERE tracking_id = $1`, [req.params.id]);
  if (!rows[0]) throw new HttpError(404, 'Incident not found.');
  res.json(toIncident(rows[0], req));
}));

// Read an optional number from the request body: undefined = not sent, null/'' = clear it.
function optNumber(v, label, { min, max, int = false }) {
  if (v === undefined) return undefined;
  if (v === null || v === '') return null;
  const n = Number(v);
  if (!Number.isFinite(n) || n < min || n > max || (int && !Number.isInteger(n))) {
    throw new HttpError(400, `${label} must be ${int ? 'a whole number' : 'a number'} between ${min} and ${max}.`);
  }
  return n;
}

// Update status, team, arrival note and the readings operations record (volume loss, pressure change).
admin.patch('/incidents/:id', wrap(async (req, res) => {
  const b = req.body || {};
  if (b.status !== undefined && !STATUSES.includes(b.status)) throw new HttpError(400, 'Invalid status.');
  if (b.arrivalNote !== undefined && b.arrivalNote !== null && (typeof b.arrivalNote !== 'string' || b.arrivalNote.length > 100)) {
    throw new HttpError(400, 'Arrival note is too long (max 100 characters).');
  }
  if (b.team !== undefined && b.team !== null && typeof b.team !== 'string') throw new HttpError(400, 'Invalid team.');
  let assignedUserId;
  if (b.assignedUserId !== undefined) {
    if (b.assignedUserId === null || b.assignedUserId === '') {
      assignedUserId = null;
    } else {
      assignedUserId = Number(b.assignedUserId);
      if (!Number.isSafeInteger(assignedUserId) || assignedUserId < 1) throw new HttpError(400, 'Invalid assignee.');
    }
  }
  const volume = optNumber(b.volumeGph, 'Volume loss', { min: 0, max: 1_000_000, int: true });
  const pressure = optNumber(b.pressurePsi, 'Pressure change', { min: -1000, max: 1000 });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const cur = await client.query('SELECT id, status, assigned_team, assigned_user_id FROM reports WHERE tracking_id = $1 FOR UPDATE', [req.params.id]);
    if (!cur.rows[0]) throw new HttpError(404, 'Incident not found.');
    const { id, status: oldStatus, assigned_team: oldTeam, assigned_user_id: oldAssignedUserId } = cur.rows[0];

    const sets = ['updated_at = now()'];
    const params = [id];
    const add = (col, v) => {
      params.push(v);
      sets.push(`${col} = $${params.length}`);
      return params.length;
    };

    let newTeam;
    let newAssignedUserId;
    if (b.status !== undefined) {
      const p = add('status', b.status);
      sets.push(`first_response_at = CASE WHEN $${p}::text = 'In Progress' AND first_response_at IS NULL THEN now() ELSE first_response_at END`);
      sets.push(`resolved_at = CASE WHEN $${p}::text = 'Resolved' THEN now() ELSE NULL END`);
    }
    if (b.team !== undefined) {
      if (b.team === null || b.team === '') {
        newTeam = null;
        add('assigned_team', null);
        add('team_lead', null);
      } else {
        const t = await client.query('SELECT name, lead FROM teams WHERE name = $1 AND active', [b.team]);
        if (!t.rows[0]) throw new HttpError(400, 'Unknown team.');
        newTeam = t.rows[0].name;
        add('assigned_team', t.rows[0].name);
        add('team_lead', t.rows[0].lead);
      }
    }
    if (assignedUserId !== undefined) {
      if (assignedUserId === null) {
        newAssignedUserId = null;
        add('assigned_user_id', null);
      } else {
        const user = await client.query(
          'SELECT id FROM dashboard_users WHERE id = $1 AND active',
          [assignedUserId],
        );
        if (!user.rows[0]) throw new HttpError(400, 'Unknown or inactive assignee.');
        newAssignedUserId = user.rows[0].id;
        add('assigned_user_id', newAssignedUserId);
      }
    }
    if (b.arrivalNote !== undefined) add('arrival_note', b.arrivalNote ? b.arrivalNote.trim() || null : null);
    if (volume !== undefined) add('volume_loss_gph', volume);
    if (pressure !== undefined) add('pressure_psi', pressure);

    const { rows } = await client.query(`UPDATE reports SET ${sets.join(', ')} WHERE id = $1 RETURNING ${INCIDENT_COLS}`, params);

    const log = (message) =>
      client.query('INSERT INTO report_activity (report_id, actor, message) VALUES ($1, $2, $3)', [id, req.user.displayName, message]);
    if (b.status !== undefined && b.status !== oldStatus) await log(`Status changed to ${b.status}`);
    if (b.team !== undefined && newTeam !== oldTeam) await log(newTeam ? `Assigned to ${newTeam}` : 'Team unassigned');
    if (assignedUserId !== undefined && String(newAssignedUserId) !== String(oldAssignedUserId)) {
      const assignee = newAssignedUserId === null ? null : await client.query(
        'SELECT display_name FROM dashboard_users WHERE id = $1',
        [newAssignedUserId],
      );
      await log(assignee ? `Assigned to ${assignee.rows[0].display_name}` : 'Person unassigned');
    }
    if (volume !== undefined || pressure !== undefined) await log('Readings updated');

    await client.query('COMMIT');
    res.json(toIncident(rows[0], req));
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}));

// Every figure is calculated from what is in the database. Anything nobody has recorded comes back null.
admin.get('/stats', wrap(async (_req, res) => {
  const [r, t] = await Promise.all([
    query(`
      SELECT
        count(*) FILTER (WHERE status <> 'Resolved')::int AS active,
        round(avg(extract(epoch FROM (first_response_at - created_at)) / 60)
              FILTER (WHERE first_response_at IS NOT NULL AND created_at > now() - interval '7 days'))::int AS avg_response_min,
        sum(volume_loss_gph) FILTER (WHERE status <> 'Resolved')::int AS water_loss_gph
      FROM reports`),
    query(`
      SELECT count(*)::int AS total,
             count(*) FILTER (WHERE EXISTS (
               SELECT 1 FROM reports r WHERE r.assigned_team = t.name AND r.status <> 'Resolved'))::int AS busy
        FROM teams t WHERE t.active`),
  ]);
  res.json({
    active: r.rows[0].active,
    avgResponseMin: r.rows[0].avg_response_min,
    waterLossGph: r.rows[0].water_loss_gph,
    unitsBusy: t.rows[0].busy,
    unitsTotal: t.rows[0].total,
  });
}));

admin.get('/teams', wrap(async (_req, res) => {
  const { rows } = await query(`
    SELECT t.name, t.lead,
           EXISTS (SELECT 1 FROM reports r WHERE r.assigned_team = t.name AND r.status <> 'Resolved') AS busy
      FROM teams t WHERE t.active ORDER BY t.name`);
  res.json(rows.map((r) => ({ name: r.name, lead: r.lead, busy: r.busy })));
}));

admin.post('/teams', wrap(async (req, res) => {
  const name = String(req.body?.name ?? '').trim();
  const lead = String(req.body?.lead ?? '').trim() || null;
  if (!name || name.length > 60 || (lead && lead.length > 60)) throw new HttpError(400, 'A team name (up to 60 characters) is required.');
  const { rows } = await query(
    `INSERT INTO teams (name, lead) VALUES ($1, $2)
     ON CONFLICT (name) DO UPDATE SET lead = EXCLUDED.lead, active = true
     RETURNING name, lead`,
    [name, lead],
  );
  res.status(201).json(rows[0]);
}));

admin.get('/users', wrap(async (_req, res) => {
  const { rows } = await query(
    `SELECT id, user_number, display_name, role
       FROM dashboard_users WHERE active ORDER BY display_name, user_number`,
  );
  res.json(rows.map((r) => ({
    id: r.id,
    userNumber: r.user_number,
    displayName: r.display_name,
    role: r.role,
  })));
}));

admin.post('/users', requireAdmin, wrap(async (req, res) => {
  const user = await createStaffUser(req.body || {});
  res.status(201).json(user);
}));

admin.get('/activity', wrap(async (req, res) => {
  const limit = Math.min(Math.max(Number(req.query.limit) || 10, 1), 50);
  const { rows } = await query(
    `SELECT a.actor, a.message, a.created_at, r.tracking_id
       FROM report_activity a JOIN reports r ON r.id = a.report_id
      ORDER BY a.created_at DESC LIMIT $1`,
    [limit],
  );
  res.json(rows.map((r) => ({ trackingId: r.tracking_id, actor: r.actor, message: r.message, createdAt: r.created_at })));
}));

// Open incidents as GeoJSON (ready for a map layer)
admin.get('/map', wrap(async (_req, res) => {
  const { rows } = await query(`
    SELECT jsonb_build_object('type', 'FeatureCollection', 'features', coalesce(jsonb_agg(
      jsonb_build_object('type', 'Feature', 'geometry', ST_AsGeoJSON(location::geometry)::jsonb,
        'properties', jsonb_build_object('id', tracking_id, 'status', status, 'severity', severity))), '[]'::jsonb)) AS fc
    FROM reports WHERE status <> 'Resolved'`);
  res.json(rows[0].fc);
}));
