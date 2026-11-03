import './env.js';
import { before, after, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { api, postReport, resetDb, makeUser, login, signedInToken, pool, crypto, hashSessionToken,
         CT, northBy, JPEG, PNG, freshIp, freshDevice, BASE } from './helpers.js';

before(async () => {
  await import('../src/index.js');             // starts the real Express app on TEST_PORT
  await new Promise((r) => setTimeout(r, 300));
});
after(async () => { await pool.end(); });
beforeEach(resetDb);

const near = (m, over = {}) => ({ lat: CT.lat + northBy(m), ...over });

describe('Integration: platform & robustness', () => {
  test('TC-013 health endpoint reports PostGIS is available', async () => {
    const r = await api('GET', '/health');
    assert.equal(r.status, 200); assert.equal(r.body.ok, true); assert.match(r.body.postgis, /^3\./);
  });
  test('TC-014 unknown route returns a JSON 404', async () => {
    const r = await api('GET', '/api/does-not-exist');
    assert.equal(r.status, 404); assert.equal(r.body.error, 'Not found.');
  });
  test('TC-015 malformed JSON returns 400 (not a server error)', async () => {
    const r = await api('POST', '/api/auth/login', { json: '{"userNumber": ' });
    assert.equal(r.status, 400); assert.equal(r.body.error, 'Invalid JSON.');
  });
  test('TC-016 oversized JSON body (>100 kb) is rejected with 413', async () => {
    const r = await api('POST', '/api/auth/login', { json: JSON.stringify({ userNumber: 'A1', password: 'x'.repeat(200_000) }) });
    assert.equal(r.status, 413, `expected 413 but got ${r.status}: ${r.text}`);
  });
  test('TC-017 security headers (helmet) are present', async () => {
    const res = await fetch(`${BASE}/health`);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.ok(!res.headers.has('x-powered-by'));
  });
});

describe('Integration: report submission (REQ-001)', () => {
  test('TC-018 valid report with photo is stored: 201, tracking ID, status Received, activity logged', async () => {
    const r = await postReport({ photo: { buf: JPEG }, fields: { name: 'Thandi', notes: 'Burst main on corner' } });
    assert.equal(r.status, 201);
    assert.match(r.body.trackingId, /^AQ-\d{5,}$/);
    assert.equal(r.body.status, 'Received'); assert.equal(r.body.severity, 'Major');
    assert.equal(r.body.possibleDuplicateOf, null);
    const photo = await pool.query('SELECT content_type, length(image_data) AS n FROM report_photos');
    assert.equal(photo.rows[0].content_type, 'image/jpeg');
    const act = await pool.query('SELECT message FROM report_activity');
    assert.equal(act.rows[0].message, 'New report received');
  });
  test('TC-019 report without a photo is accepted (photo optional in implementation)', async () => {
    const r = await postReport({});
    assert.equal(r.status, 201);
  });
  test('TC-020 GPS coordinates are stored as a PostGIS geography point and round-trip accurately', async () => {
    await postReport({ fields: { lat: -33.918861, lng: 18.423300 } });
    const { rows } = await pool.query(`SELECT ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng, ST_SRID(location::geometry) AS srid FROM reports`);
    assert.ok(Math.abs(rows[0].lat - -33.918861) < 1e-6); assert.ok(Math.abs(rows[0].lng - 18.4233) < 1e-6); assert.equal(rows[0].srid, 4326);
  });
  test('TC-021 request without X-Device-Id is rejected (400)', async () => {
    const r = await postReport({ omitDevice: true });
    assert.equal(r.status, 400);
  });
  test('TC-022 a file that is not a real image (renamed .jpg) is rejected by header check', async () => {
    const r = await postReport({ photo: { buf: Buffer.from('this is definitely not an image file'), name: 'leak.jpg' } });
    assert.equal(r.status, 400); assert.match(r.body.error, /JPEG, PNG, WebP or GIF/);
    assert.equal((await pool.query('SELECT count(*)::int n FROM reports')).rows[0].n, 0);
  });
  test('TC-023 PNG upload is accepted and stored with the correct content type', async () => {
    const r = await postReport({ photo: { buf: PNG, type: 'image/png', name: 'leak.png' } });
    assert.equal(r.status, 201);
    assert.equal((await pool.query('SELECT content_type FROM report_photos')).rows[0].content_type, 'image/png');
  });
  test('TC-024 photo larger than 8 MB is rejected with 413', async () => {
    const big = Buffer.concat([JPEG, Buffer.alloc(8 * 1024 * 1024 + 10, 7)]);
    const r = await postReport({ photo: { buf: big } });
    assert.equal(r.status, 413);
  });
  test('TC-025 missing/invalid phone number is rejected (400)', async () => {
    assert.equal((await postReport({ fields: { phone: '' } })).status, 400);
    assert.equal((await postReport({ fields: { phone: 'abc' } })).status, 400);
  });
  test('TC-026 invalid enum values and out-of-range coordinates are rejected (400)', async () => {
    assert.equal((await postReport({ fields: { leak_type: 'flood' } })).status, 400);
    assert.equal((await postReport({ fields: { severity: 'huge' } })).status, 400);
    assert.equal((await postReport({ fields: { lat: 95 } })).status, 400);
  });
  test('TC-027 empty latitude/longitude must be rejected, not stored at (0,0)', async () => {
    const r = await postReport({ fields: { lat: '', lng: '' } });
    assert.equal(r.status, 400, `expected 400 but got ${r.status}`);
  });
  test('TC-028 enum names that are JavaScript object keys (e.g. "constructor") are rejected with 400, not 500', async () => {
    const a = await postReport({ fields: { leak_type: 'constructor' } });
    assert.equal(a.status, 400, `leak_type=constructor returned ${a.status}`);
    const b = await postReport({ fields: { severity: 'toString' } });
    assert.equal(b.status, 400, `severity=toString returned ${b.status}`);
  });
  test('TC-029 per-device rate limit: the 11th report in an hour returns 429', async () => {
    const device = freshDevice(); let last;
    for (let i = 0; i < 11; i++) last = await postReport({ device });
    assert.equal(last.status, 429);
  });
});

describe('Integration: duplicate detection (REQ-002, PostGIS ST_DWithin)', () => {
  test('TC-030 same type 20 m away is flagged as a possible duplicate of the first report', async () => {
    const a = await postReport({});
    const b = await postReport({ fields: near(20) });
    assert.equal(b.body.possibleDuplicateOf, a.body.trackingId);
    const row = await pool.query(`SELECT duplicate_of FROM reports WHERE tracking_id = $1`, [b.body.trackingId]);
    assert.ok(row.rows[0].duplicate_of);
  });
  test('TC-031 boundary: 45 m is a duplicate, 60 m is not (50 m radius)', async () => {
    await postReport({});
    assert.ok((await postReport({ fields: near(45) })).body.possibleDuplicateOf);
    assert.equal((await postReport({ fields: near(-60) })).body.possibleDuplicateOf, null);   // 60 m on the opposite side
  });
  test('TC-032 a different leak type at the same spot is NOT a duplicate', async () => {
    await postReport({});
    const b = await postReport({ fields: { leak_type: 'visible_leak' } });
    assert.equal(b.body.possibleDuplicateOf, null);
  });
  test('TC-033 a Resolved report is never matched as the original', async () => {
    const a = await postReport({});
    await pool.query(`UPDATE reports SET status='Resolved' WHERE tracking_id=$1`, [a.body.trackingId]);
    assert.equal((await postReport({})).body.possibleDuplicateOf, null);
  });
  test('TC-034 reports older than 24 h are not matched', async () => {
    const a = await postReport({});
    await pool.query(`UPDATE reports SET created_at = now() - interval '25 hours' WHERE tracking_id=$1`, [a.body.trackingId]);
    assert.equal((await postReport({})).body.possibleDuplicateOf, null);
  });
  test('TC-035 nearest open match is chosen when several candidates exist', async () => {
    const far = await postReport({ fields: near(40) });
    const close = await postReport({ fields: near(-5) });   // 45 m from `far`, flagged against it
    const probe = await postReport({ fields: near(-2) });   // nearest candidate is `close` (3 m)
    assert.equal(probe.body.possibleDuplicateOf, close.body.trackingId);
    assert.ok(far.body.trackingId);
  });
  test('TC-036 design requirement: duplicates are MERGED into one queue item with a corroboration count', async () => {
    await postReport({}); await postReport({ fields: near(10) });
    const n = (await pool.query(`SELECT count(*)::int n FROM reports WHERE status <> 'Resolved'`)).rows[0].n;
    const cols = (await pool.query(`SELECT column_name FROM information_schema.columns WHERE table_name='reports'`)).rows.map((r) => r.column_name);
    assert.equal(n, 1, `queue contains ${n} items for one physical leak`);
    assert.ok(cols.includes('corroboration_count'), 'no corroboration_count column');
  });
  test('TC-037 eight simultaneous reports of the same leak: exactly seven are flagged (race condition check)', async () => {
    const rs = await Promise.all(Array.from({ length: 8 }, () => postReport({})));
    assert.ok(rs.every((x) => x.status === 201));
    const flagged = rs.filter((x) => x.body.possibleDuplicateOf).length;
    assert.equal(flagged, 7, `${flagged} of 8 simultaneous reports were flagged as duplicates (7 expected)`);
  });
});

describe('Integration: citizen status tracking (REQ-004)', () => {
  test('TC-038 status lookup by tracking ID returns the current status and ETA', async () => {
    const a = await postReport({ fields: { severity: 'emergency' } });
    const r = await api('GET', `/api/reports/${a.body.trackingId}`);
    assert.equal(r.status, 200); assert.equal(r.body.status, 'Received'); assert.equal(r.body.eta, 'under 1 hour');
  });
  test('TC-039 unknown tracking ID returns 404', async () => {
    assert.equal((await api('GET', '/api/reports/AQ-00000')).status, 404);
  });
  test('TC-040 "My reports" lookup finds a number in local and international format', async () => {
    await postReport({ fields: { phone: '+27 82 123 4567' } });
    await postReport({ fields: { phone: '082 123 4567', leak_type: 'equipment', lat: CT.lat + 0.01 } });
    const r = await api('POST', '/api/reports/lookup', { json: { phone: '0821234567' } });
    assert.equal(r.status, 200); assert.equal(r.body.length, 2);
  });
  test('TC-041 lookup of an invalid number returns 400; of an unused number returns an empty list', async () => {
    assert.equal((await api('POST', '/api/reports/lookup', { json: { phone: '12' } })).status, 400);
    const r = await api('POST', '/api/reports/lookup', { json: { phone: '0790000000' } });
    assert.deepEqual(r.body, []);
  });
  test('TC-042 status change by staff is visible to the citizen on next lookup', async () => {
    const a = await postReport({}); const { token } = await signedInToken();
    await api('PATCH', `/api/admin/incidents/${a.body.trackingId}`, { token, json: { status: 'In Progress' } });
    assert.equal((await api('GET', `/api/reports/${a.body.trackingId}`)).body.status, 'In Progress');
  });
  test('TC-043 public responses never expose reporter name, phone or notes', async () => {
    const a = await postReport({ fields: { name: 'Thandi Nkosi', notes: 'secret note', phone: '+27 82 123 4567' } });
    const single = await api('GET', `/api/reports/${a.body.trackingId}`);
    const mine = await api('POST', '/api/reports/lookup', { json: { phone: '0821234567' } });
    for (const txt of [single.text, mine.text]) { assert.ok(!/Thandi|secret note|123 4567|821234567/.test(txt), txt); }
  });
  test('TC-044 public city search returns only tracking, status and street (no coordinates or contact data)', async () => {
    const a = await postReport({});
    await pool.query(`UPDATE reports SET city='Cape Town', street='Long Street' WHERE tracking_id=$1`, [a.body.trackingId]);
    const r = await api('GET', '/api/reports/city?city=cape%20town');
    assert.equal(r.status, 200); assert.equal(r.body.length, 1);
    assert.deepEqual(Object.keys(r.body[0]).sort(), ['address','city','createdAt','leakType','severity','status','street','title','trackingId'].sort());
  });
  test('TC-045 tracking IDs are not guessable: another citizen\'s report cannot be enumerated', async () => {
    await postReport({}); const b = await postReport({ fields: { lat: CT.lat + 0.02 } });
    const n = Number(b.body.trackingId.split('-')[1]);
    const guess = await api('GET', `/api/reports/AQ-${n - 1}`);
    assert.equal(guess.status, 404, `sequential ID AQ-${n - 1} returned ${guess.status} with location data`);
  });
});

describe('Integration: privacy of public endpoints', () => {
  test('TC-080 a citizen cannot download another person\'s photo by guessing the next tracking ID', async () => {
    await postReport({ photo: { buf: JPEG } });
    const b = await postReport({ photo: { buf: JPEG }, fields: { lat: CT.lat + 0.02 } });
    const n = Number(b.body.trackingId.split('-')[1]);
    const res = await fetch(`${BASE}/api/reports/photo/AQ-${n - 1}`, { headers: { 'x-forwarded-for': freshIp() } });
    assert.notEqual(res.status, 200, 'photo of another report was served without any credential');
  });
});

describe('Integration: authentication & authorisation (Design §9.3)', () => {
  test('TC-046 dashboard endpoints reject requests with no token (401)', async () => {
    for (const p of ['/api/admin/incidents', '/api/admin/stats', '/api/admin/map', '/api/admin/teams', '/api/admin/users', '/api/admin/activity']) {
      assert.equal((await api('GET', p)).status, 401, p);
    }
  });
  test('TC-047 valid staff login returns a token; /auth/me returns the profile without the password hash', async () => {
    const u = await makeUser(); const r = await login(u.number, u.password);
    assert.equal(r.status, 200); assert.match(r.body.token, /^[A-Za-z0-9_-]{43}$/);
    const me = await api('GET', '/api/auth/me', { token: r.body.token });
    assert.equal(me.body.userNumber, 'STAFF01'); assert.ok(!/hash|scrypt/i.test(me.text));
  });
  test('TC-048 wrong password and unknown user both return the same 401 message (no user enumeration)', async () => {
    const u = await makeUser();
    const a = await login(u.number, 'wrong-password-123'); const b = await login('NOBODY', 'whatever-password-1');
    assert.equal(a.status, 401); assert.equal(b.status, 401); assert.equal(a.body.error, b.body.error);
  });
  test('TC-049 brute force: 10 failed logins from one IP lock further attempts (429), even with the right password', async () => {
    const u = await makeUser(); const ip = freshIp(); const codes = [];
    for (let i = 0; i < 10; i++) codes.push((await login(u.number, 'bad-password-123', ip)).status);
    assert.deepEqual(codes, [401, 401, 401, 401, 401, 401, 401, 401, 401, 429]);
    assert.equal((await login(u.number, u.password, ip)).status, 429);
  });
  test('TC-050 logout invalidates the session token', async () => {
    const { token } = await signedInToken();
    assert.equal((await api('POST', '/api/auth/logout', { token })).status, 204);
    assert.equal((await api('GET', '/api/auth/me', { token })).status, 401);
  });
  test('TC-051 an expired session is rejected', async () => {
    const u = await makeUser(); const token = crypto.randomBytes(32).toString('base64url');
    await pool.query(`INSERT INTO dashboard_sessions (token_hash, user_id, expires_at) VALUES ($1,$2, now() - interval '1 minute')`, [hashSessionToken(token), u.id]);
    assert.equal((await api('GET', '/api/auth/me', { token })).status, 401);
  });
  test('TC-052 a deactivated staff account can no longer use an existing token', async () => {
    const { token, user } = await signedInToken();
    await pool.query('UPDATE dashboard_users SET active=false WHERE id=$1', [user.id]);
    assert.equal((await api('GET', '/api/admin/stats', { token })).status, 401);
  });
  test('TC-053 forged / malformed bearer tokens are rejected', async () => {
    assert.equal((await api('GET', '/api/admin/stats', { token: 'abc' })).status, 401);
    assert.equal((await api('GET', '/api/admin/stats', { token: crypto.randomBytes(32).toString('base64url') })).status, 401);
  });
  test('TC-054 only the admin role can create staff accounts; password policy (>=12 chars) is enforced', async () => {
    const staff = await signedInToken({ number: 'S1' });
    assert.equal((await api('POST', '/api/admin/users', { token: staff.token, json: { userNumber: 'NEW1', displayName: 'N', password: 'long-enough-password' } })).status, 403);
    const adminTok = await signedInToken({ number: 'ADM1', role: 'admin' });
    assert.equal((await api('POST', '/api/admin/users', { token: adminTok.token, json: { userNumber: 'NEW1', displayName: 'New', password: 'short' } })).status, 400);
    const ok = await api('POST', '/api/admin/users', { token: adminTok.token, json: { userNumber: 'NEW1', displayName: 'New', password: 'long-enough-password' } });
    assert.equal(ok.status, 201); assert.equal(ok.body.role, 'staff');
    assert.equal((await api('POST', '/api/admin/users', { token: adminTok.token, json: { userNumber: 'new1', displayName: 'Dup', password: 'long-enough-password' } })).status, 409);
  });
  test('TC-055 stored password is a salted scrypt hash, never plaintext', async () => {
    await makeUser({ password: 'correct-horse-battery' });
    const { rows } = await pool.query('SELECT password_hash FROM dashboard_users');
    assert.match(rows[0].password_hash, /^scrypt\$/); assert.ok(!rows[0].password_hash.includes('correct-horse'));
  });
  test('TC-056 SQL-injection strings in search, tracking ID and login fields are handled safely', async () => {
    const a = await postReport({}); const { token } = await signedInToken();
    const evil = `' OR 1=1; DROP TABLE reports; --`;
    assert.equal((await api('GET', `/api/admin/incidents?q=${encodeURIComponent(evil)}`, { token })).status, 200);
    assert.equal((await api('GET', `/api/reports/${encodeURIComponent(evil)}`)).status, 404);
    assert.equal((await login(evil, 'x'.repeat(14))).status, 400);
    assert.equal((await pool.query('SELECT count(*)::int n FROM reports')).rows[0].n, 1);
    assert.ok(a.body.trackingId);
  });
});

describe('Integration: municipal dashboard – triage & workflow (REQ-003)', () => {
  test('TC-057 queue is ordered emergency > major > minor, with Resolved incidents last', async () => {
    const mk = (sev, dy) => postReport({ fields: { severity: sev, lat: CT.lat + dy, leak_type: 'visible_leak' } });
    const minor = await mk('minor', 0.01); const emerg = await mk('emergency', 0.02); const major = await mk('major', 0.03);
    const resolved = await mk('emergency', 0.04);
    await pool.query(`UPDATE reports SET status='Resolved' WHERE tracking_id=$1`, [resolved.body.trackingId]);
    const { token } = await signedInToken();
    const r = await api('GET', '/api/admin/incidents', { token });
    assert.deepEqual(r.body.map((x) => x.id), [emerg, major, minor, resolved].map((x) => x.body.trackingId));
  });
  test('TC-058 spatial filter: radius search returns only incidents within range, nearest first, with distance in metres', async () => {
    await postReport({ fields: { lat: CT.lat + northBy(100), leak_type: 'visible_leak' } });
    await postReport({ fields: { lat: CT.lat + northBy(500), leak_type: 'equipment' } });
    await postReport({ fields: { lat: CT.lat + northBy(5000), leak_type: 'running_water' } });
    const { token } = await signedInToken();
    const r = await api('GET', `/api/admin/incidents?lat=${CT.lat}&lng=${CT.lng}&radius=1000`, { token });
    assert.equal(r.body.length, 2);
    assert.ok(Math.abs(r.body[0].distanceM - 100) <= 2); assert.ok(Math.abs(r.body[1].distanceM - 500) <= 2);
  });
  test('TC-059 status/search filters work and invalid status is rejected (400)', async () => {
    const a = await postReport({}); await postReport({ fields: { lat: CT.lat + 0.01, leak_type: 'equipment' } });
    await pool.query(`UPDATE reports SET status='Delayed' WHERE tracking_id=$1`, [a.body.trackingId]);
    const { token } = await signedInToken();
    assert.equal((await api('GET', '/api/admin/incidents?status=Delayed', { token })).body.length, 1);
    assert.equal((await api('GET', '/api/admin/incidents?q=equipment', { token })).body.length, 1);
    assert.equal((await api('GET', '/api/admin/incidents?status=Bogus', { token })).status, 400);
  });
  test('TC-060 map endpoint returns valid GeoJSON containing only open incidents', async () => {
    const a = await postReport({}); await postReport({ fields: { lat: CT.lat + 0.01, leak_type: 'equipment' } });
    await pool.query(`UPDATE reports SET status='Resolved' WHERE tracking_id=$1`, [a.body.trackingId]);
    const { token } = await signedInToken();
    const r = await api('GET', '/api/admin/map', { token });
    assert.equal(r.body.type, 'FeatureCollection'); assert.equal(r.body.features.length, 1);
    assert.equal(r.body.features[0].geometry.type, 'Point');
  });
  test('TC-061 status update to In Progress records first_response_at and an audit entry attributed to the staff member', async () => {
    const a = await postReport({}); const { token } = await signedInToken({ name: 'Sipho Dlamini' });
    const r = await api('PATCH', `/api/admin/incidents/${a.body.trackingId}`, { token, json: { status: 'In Progress' } });
    assert.equal(r.status, 200); assert.equal(r.body.status, 'In Progress');
    const row = (await pool.query('SELECT first_response_at FROM reports')).rows[0]; assert.ok(row.first_response_at);
    const log = (await pool.query(`SELECT actor, message FROM report_activity WHERE message LIKE 'Status%'`)).rows[0];
    assert.deepEqual(log, { actor: 'Sipho Dlamini', message: 'Status changed to In Progress' });
  });
  test('TC-062 Resolved sets resolved_at; re-opening clears it', async () => {
    const a = await postReport({}); const { token } = await signedInToken(); const url = `/api/admin/incidents/${a.body.trackingId}`;
    await api('PATCH', url, { token, json: { status: 'Resolved' } });
    assert.ok((await pool.query('SELECT resolved_at FROM reports')).rows[0].resolved_at);
    await api('PATCH', url, { token, json: { status: 'In Progress' } });
    assert.equal((await pool.query('SELECT resolved_at FROM reports')).rows[0].resolved_at, null);
  });
  test('TC-063 invalid status, unknown team, bad readings and unknown incident are rejected', async () => {
    const a = await postReport({}); const { token } = await signedInToken(); const url = `/api/admin/incidents/${a.body.trackingId}`;
    assert.equal((await api('PATCH', url, { token, json: { status: 'Exploded' } })).status, 400);
    assert.equal((await api('PATCH', url, { token, json: { team: 'No Such Team' } })).status, 400);
    assert.equal((await api('PATCH', url, { token, json: { volumeGph: -5 } })).status, 400);
    assert.equal((await api('PATCH', url, { token, json: { pressurePsi: 99999 } })).status, 400);
    assert.equal((await api('PATCH', '/api/admin/incidents/AQ-99999', { token, json: { status: 'Resolved' } })).status, 404);
  });
  test('TC-064 assigning a team logs the assignment and the team shows as busy', async () => {
    const a = await postReport({}); const { token } = await signedInToken();
    await api('POST', '/api/admin/teams', { token, json: { name: 'Valve Maintenance Team', lead: 'R. Shah' } });
    const r = await api('PATCH', `/api/admin/incidents/${a.body.trackingId}`, { token, json: { team: 'Valve Maintenance Team' } });
    assert.equal(r.body.team, 'Valve Maintenance Team'); assert.equal(r.body.lead, 'R. Shah');
    const teams = await api('GET', '/api/admin/teams', { token }); assert.equal(teams.body[0].busy, true);
    const act = await api('GET', '/api/admin/activity', { token });
    assert.ok(act.body.some((x) => x.message === 'Assigned to Valve Maintenance Team'));
  });
  test('TC-065 dashboard statistics are calculated from real data (active count, average response time, water loss)', async () => {
    const a = await postReport({}); await postReport({ fields: { lat: CT.lat + 0.01, leak_type: 'equipment' } });
    await pool.query(`UPDATE reports SET status='In Progress', first_response_at = created_at + interval '30 minutes', volume_loss_gph=120 WHERE tracking_id=$1`, [a.body.trackingId]);
    const { token } = await signedInToken();
    const s = (await api('GET', '/api/admin/stats', { token })).body;
    assert.equal(s.active, 2); assert.equal(s.avgResponseMin, 30); assert.equal(s.waterLossGph, 120);
  });
  test('TC-066 stats are null (not invented) when nothing has been recorded', async () => {
    const { token } = await signedInToken();
    const s = (await api('GET', '/api/admin/stats', { token })).body;
    assert.equal(s.active, 0); assert.equal(s.avgResponseMin, null); assert.equal(s.waterLossGph, null);
  });
  test('TC-067 design requirement: weighted priority score (category + severity + corroboration + proximity + age) is exposed', async () => {
    await postReport({}); const { token } = await signedInToken();
    const inc = (await api('GET', '/api/admin/incidents', { token })).body[0];
    assert.ok('priorityScore' in inc || 'priority_score' in inc, `incident fields: ${Object.keys(inc).join(', ')}`);
  });
  test('TC-068 design requirement: hotspot endpoint for the heat-map view', async () => {
    const { token } = await signedInToken();
    assert.notEqual((await api('GET', '/api/admin/hotspots', { token })).status, 404);
  });
  test('TC-069 design requirement: reports are linked to a Municipality record (jurisdiction routing)', async () => {
    const t = await pool.query(`SELECT to_regclass('public.municipalities') AS t`);
    assert.ok(t.rows[0].t, 'no municipalities table in the schema');
  });
  test('TC-070 design requirement: push notification is dispatched on status change', async () => {
    const t = await pool.query(`SELECT to_regclass('public.notifications') AS t`);
    assert.ok(t.rows[0].t, 'no notifications table / FCM integration in the schema');
  });
});

describe('Integration: resilience', () => {
  test('TC-071 reverse-geocoder outage does not block submission; address falls back to coordinates', async () => {
    const realFetch = globalThis.fetch;
    globalThis.fetch = async (url, init) => {                 // simulate Nominatim being unreachable
      if (String(url).startsWith('https://nominatim.openstreetmap.org/')) throw new Error('simulated geocoder outage');
      return realFetch(url, init);
    };
    process.env.ENABLE_GEOCODING = 'true';
    try {
      const a = await postReport({ fields: { lat: -33.9249, lng: 18.4241 } });
      assert.equal(a.status, 201); assert.match(a.body.address, /33\.9249° S, 18\.4241° E/);
    } finally { globalThis.fetch = realFetch; process.env.ENABLE_GEOCODING = 'false'; }
  });
  test('TC-072 failed insert rolls back: no orphan report or activity row remains', async () => {
    await pool.query(`ALTER TABLE report_photos RENAME TO report_photos_x`);
    try {
      const r = await postReport({ photo: { buf: JPEG } });
      assert.equal(r.status, 500);
      assert.equal((await pool.query('SELECT count(*)::int n FROM reports')).rows[0].n, 0);
      assert.equal((await pool.query('SELECT count(*)::int n FROM report_activity')).rows[0].n, 0);
    } finally { await pool.query(`ALTER TABLE report_photos_x RENAME TO report_photos`); }
  });
});

describe('Integration: reverse geocoding (Nominatim stubbed)', () => {
  const realFetch = globalThis.fetch;
  const stub = (delayMs) => {
    globalThis.fetch = async (url, init) => {
      if (String(url).startsWith('https://nominatim.openstreetmap.org/')) {
        await new Promise((r) => setTimeout(r, delayMs));
        return new Response(JSON.stringify({ address: { road: 'Long Street', suburb: 'Gardens', city: 'Cape Town' }, display_name: 'x' }), { status: 200 });
      }
      return realFetch(url, init);
    };
    process.env.ENABLE_GEOCODING = 'true';
  };
  const unstub = () => { globalThis.fetch = realFetch; process.env.ENABLE_GEOCODING = 'false'; };

  test('TC-078 street, suburb and city from the geocoder are stored and shown (supports REQ-005 jurisdiction display)', async () => {
    stub(0);
    try {
      const a = await postReport({});
      assert.equal(a.status, 201); assert.equal(a.body.address, 'Long Street, Gardens, Cape Town'); assert.equal(a.body.city, 'Cape Town');
      const row = (await pool.query('SELECT street, city FROM reports')).rows[0]; assert.deepEqual(row, { street: 'Long Street', city: 'Cape Town' });
    } finally { unstub(); }
  });
  test('TC-079 with a slow geocoder (400 ms), eight simultaneous reports of one leak are still consolidated (7 flagged)', async () => {
    stub(400);
    try {
      const rs = await Promise.all(Array.from({ length: 8 }, () => postReport({})));
      assert.ok(rs.every((x) => x.status === 201));
      const flagged = rs.filter((x) => x.body.possibleDuplicateOf).length;
      assert.equal(flagged, 7, `${flagged} of 8 simultaneous reports were flagged as duplicates (7 expected)`);
    } finally { unstub(); }
  });
});
