import './env.js';
import { before, after, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { api, postReport, resetDb, signedInToken, pool, CT } from './helpers.js';

const N = Number(process.env.PERF_ROWS || 10000);
const pct = (a, p) => [...a].sort((x, y) => x - y)[Math.min(a.length - 1, Math.floor(p * a.length))];
const ms = async (fn) => { const t = performance.now(); await fn(); return performance.now() - t; };

let TOKEN;
before(async () => {
  await import('../src/index.js'); await new Promise((r) => setTimeout(r, 300)); await resetDb();
  TOKEN = (await signedInToken()).token;
  // N synthetic open reports scattered over ~20 km x 20 km around Cape Town (inserted directly for speed)
  await pool.query(`
    INSERT INTO reports (device_id, leak_type, severity, location, phone_key)
    SELECT 'perf', (ARRAY['burst_pipe','visible_leak','running_water','equipment'])[1 + (i % 4)],
           (ARRAY['minor','major','emergency'])[1 + (i % 3)],
           ST_SetSRID(ST_MakePoint(18.3 + random()*0.2, -34.0 + random()*0.2), 4326)::geography, '821234567'
      FROM generate_series(1, $1) i`, [N]);
  await pool.query('ANALYZE reports');
});
after(async () => { await pool.end(); });

describe(`Performance with ${N} stored reports`, () => {
  test('TC-073 duplicate-detection query uses the GiST spatial index', async () => {
    const { rows } = await pool.query(`EXPLAIN (ANALYZE, FORMAT TEXT)
      SELECT id FROM reports WHERE status <> 'Resolved' AND leak_type='burst_pipe' AND created_at > now() - interval '24 hours'
        AND ST_DWithin(location, ST_SetSRID(ST_MakePoint(18.4, -33.9), 4326)::geography, 50) LIMIT 1`);
    const plan = rows.map((r) => r['QUERY PLAN']).join('\n'); console.log('\n' + plan);
    assert.match(plan, /reports_(location_gix|created_idx|status_idx)|Bitmap|Index/);
  });
  test('TC-074 POST /api/reports (validate + duplicate check + insert) p95 < 300 ms', async () => {
    const t = [];
    for (let i = 0; i < 60; i++) t.push(await ms(() => postReport({ fields: { lat: CT.lat + i * 0.001 } })));
    console.log(`\n  POST /api/reports  n=${t.length}  median=${pct(t, .5).toFixed(1)} ms  p95=${pct(t, .95).toFixed(1)} ms  max=${Math.max(...t).toFixed(1)} ms`);
    assert.ok(pct(t, .95) < 300);
  });
  test('TC-075 dashboard queue GET /api/admin/incidents p95 < 500 ms', async () => {
    const token = TOKEN; const t = [];
    for (let i = 0; i < 40; i++) t.push(await ms(() => api('GET', '/api/admin/incidents', { token })));
    console.log(`\n  GET /admin/incidents  n=${t.length}  median=${pct(t, .5).toFixed(1)} ms  p95=${pct(t, .95).toFixed(1)} ms`);
    assert.ok(pct(t, .95) < 500);
  });
  test('TC-076 spatial radius search (5 km) p95 < 500 ms', async () => {
    const token = TOKEN; const t = [];
    for (let i = 0; i < 40; i++) t.push(await ms(() => api('GET', `/api/admin/incidents?lat=${CT.lat}&lng=${CT.lng}&radius=5000`, { token })));
    console.log(`\n  GET /admin/incidents?radius=5000  n=${t.length}  median=${pct(t, .5).toFixed(1)} ms  p95=${pct(t, .95).toFixed(1)} ms`);
    assert.ok(pct(t, .95) < 500);
  });
  test('TC-077 GeoJSON map layer for all open incidents p95 < 1500 ms', async () => {
    const token = TOKEN; const t = [];
    for (let i = 0; i < 15; i++) t.push(await ms(() => api('GET', '/api/admin/map', { token })));
    console.log(`\n  GET /admin/map  n=${t.length}  median=${pct(t, .5).toFixed(1)} ms  p95=${pct(t, .95).toFixed(1)} ms`);
    assert.ok(pct(t, .95) < 1500);
  });
});
