export const TITLES = {
  burst_pipe: 'Burst pipe',
  visible_leak: 'Visible leak',
  running_water: 'Running water',
  equipment: 'Equipment issue',
};
export const SEVERITY_LABEL = { minor: 'Minor', major: 'Major', emergency: 'Emergency' };
export const LEVEL = { minor: 'Minor', major: 'Major', emergency: 'Urgent' };
export const ETA = { minor: '24–48 hours', major: '2–4 hours', emergency: 'under 1 hour' };
export const STATUSES = ['Received', 'In Progress', 'Delayed', 'Resolved'];

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

export function coordsText(lat, lng) {
  return `${Math.abs(lat).toFixed(4)}° ${lat >= 0 ? 'N' : 'S'}, ${Math.abs(lng).toFixed(4)}° ${lng >= 0 ? 'E' : 'W'}`;
}

export function absUrl(req, path) {
  if (!path) return null;
  const base = process.env.PUBLIC_URL || `${req.protocol}://${req.get('host')}`;
  return base.replace(/\/$/, '') + path;
}

/** Columns the citizen app needs. */
export const REPORT_COLS = `tracking_id, leak_type, severity, status, address, created_at,
  street, city,
  ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng`;

export const CITY_REPORT_COLS = `tracking_id, leak_type, severity, status, street, city, created_at`;

/** Columns the operations dashboard needs. */
export const INCIDENT_COLS = `tracking_id, leak_type, severity, status, address, notes, photo_url,
  street, city,
  reporter_name, reporter_phone, assigned_team, team_lead, arrival_note, volume_loss_gph,
  assigned_user_id,
  (SELECT display_name FROM dashboard_users WHERE id = assigned_user_id) AS assigned_user_name,
  (SELECT user_number FROM dashboard_users WHERE id = assigned_user_id) AS assigned_user_number,
  pressure_psi::float8 AS pressure_psi, created_at, updated_at,
  ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng`;

export function toReport(r) {
  return {
    trackingId: r.tracking_id,
    leakType: r.leak_type,
    title: TITLES[r.leak_type],
    severity: SEVERITY_LABEL[r.severity],
    status: r.status,
    address: r.address || coordsText(r.lat, r.lng),
    city: r.city || null,
    eta: ETA[r.severity],
    createdAt: r.created_at,
    lat: r.lat,
    lng: r.lng,
  };
}

export function toIncident(r, req) {
  return {
    id: r.tracking_id,
    leakType: r.leak_type,
    title: TITLES[r.leak_type],
    address: r.address || coordsText(r.lat, r.lng),
    city: r.city || null,
    status: r.status,
    level: LEVEL[r.severity],
    narrative: r.notes || null,
    reporter: r.reporter_name || null,
    phone: r.reporter_phone || null,
    volumeGph: r.volume_loss_gph,
    pressurePsi: r.pressure_psi,
    team: r.assigned_team,
    lead: r.team_lead,
    assignedUserId: r.assigned_user_id,
    assignedUserName: r.assigned_user_name || null,
    assignedUserNumber: r.assigned_user_number || null,
    arrival: r.arrival_note,
    lat: r.lat,
    lng: r.lng,
    photoUrl: absUrl(req, r.photo_url),
    createdAt: r.created_at,
    updatedAt: r.updated_at,
    distanceM: r.distance_m ?? null,
  };
}

export function toCityReport(r) {
  const street = r.street || 'Street not available';
  return {
    trackingId: r.tracking_id,
    leakType: r.leak_type,
    title: TITLES[r.leak_type],
    severity: SEVERITY_LABEL[r.severity],
    status: r.status,
    street,
    city: r.city,
    address: `${street}, ${r.city}`,
    createdAt: r.created_at,
  };
}

/** Best-effort reverse geocoding (OpenStreetMap Nominatim). */
export async function reverseGeocode(lat, lng) {
  if (process.env.ENABLE_GEOCODING === 'false') return null;
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&lat=${lat}&lon=${lng}`;
    const res = await fetch(url, {
      headers: { 'User-Agent': 'AquaAlert/1.0 (leak reporting)' },
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) return null;
    const j = await res.json();
    const a = j.address || {};
    const road = a.road || a.residential || a.pedestrian || a.path || null;
    const number = a.house_number || a.house_name || null;
    const streetAddress = [number, road].filter(Boolean).join(' ');
    const city = a.city || a.town || a.village || a.municipality || null;
    const area = a.suburb || a.neighbourhood || a.quarter || null;
    const parts = [...new Set([streetAddress, area, city].filter(Boolean))];
    if (parts.length === 0 && !j.display_name) return null;
    return {
      address: parts.join(', ') || j.display_name.split(',').slice(0, 3).join(',').trim(),
      street: road,
      city,
    };
  } catch {
    return null;
  }
}

/**
 * Key used to match a person's reports: the last 9 digits of their number, so "+27 82 123 4567"
 * and "082 123 4567" match. Returns null if the number doesn't look like a phone number.
 */
export function phoneKey(raw) {
  const digits = String(raw ?? '').replace(/\D/g, '');
  if (digits.length < 7 || digits.length > 15) return null;
  return digits.slice(-9);
}

function clean(v, max) {
  if (v === undefined || v === null) return null;
  const s = String(v).trim();
  if (!s) return null;
  if (s.length > max) throw new HttpError(400, `Text is too long (max ${max} characters).`);
  return s;
}

export function parseReport(body) {
  const leakType = body.leak_type;
  const severity = body.severity;
  const lat = Number(body.lat);
  const lng = Number(body.lng);
  if (!TITLES[leakType]) throw new HttpError(400, 'Invalid leak type.');
  if (!SEVERITY_LABEL[severity]) throw new HttpError(400, 'Invalid severity.');
  if (!Number.isFinite(lat) || lat < -90 || lat > 90 || !Number.isFinite(lng) || lng < -180 || lng > 180) {
    throw new HttpError(400, 'A valid location is required.');
  }
  const phone = clean(body.phone, 30);
  if (!phone) throw new HttpError(400, 'A phone number is required so you can track your reports.');
  const key = /^[+\d\s()-]{7,30}$/.test(phone) ? phoneKey(phone) : null;
  if (!key) throw new HttpError(400, 'Enter a valid phone number.');
  return {
    leakType, severity, lat, lng, phone, phoneKey: key,
    name: clean(body.name, 80),
    notes: clean(body.notes, 1000),
  };
}
