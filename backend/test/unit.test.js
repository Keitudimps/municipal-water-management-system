import './env.js';
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { parseReport, phoneKey, HttpError, coordsText } from '../src/util.js';
import { hashPassword, verifyPassword, hashSessionToken } from '../src/auth-security.js';

const ok = { leak_type: 'burst_pipe', severity: 'major', lat: '-33.9249', lng: '18.4241', phone: '+27 82 123 4567' };
const rejects = (body, re) => assert.throws(() => parseReport(body), (e) => e instanceof HttpError && e.status === 400 && re.test(e.message));

describe('Unit: report validation (util.js parseReport)', () => {
  test('TC-001 accepts a valid report and trims optional fields', () => {
    const r = parseReport({ ...ok, name: '  Thandi  ', notes: ' pooling at kerb ' });
    assert.equal(r.leakType, 'burst_pipe'); assert.equal(r.severity, 'major');
    assert.equal(r.lat, -33.9249); assert.equal(r.lng, 18.4241);
    assert.equal(r.name, 'Thandi'); assert.equal(r.notes, 'pooling at kerb');
  });
  test('TC-002 rejects an unknown leak type', () => rejects({ ...ok, leak_type: 'flood' }, /leak type/i));
  test('TC-003 rejects an unknown severity', () => rejects({ ...ok, severity: 'catastrophic' }, /severity/i));
  test('TC-004 rejects latitude/longitude outside valid ranges', () => {
    rejects({ ...ok, lat: '91' }, /location/i);
    rejects({ ...ok, lng: '181' }, /location/i);
    rejects({ ...ok, lat: 'abc' }, /location/i);
  });
  test('TC-005 rejects a missing, too-short or non-numeric phone number', () => {
    rejects({ ...ok, phone: undefined }, /phone/i);
    rejects({ ...ok, phone: '123' }, /phone/i);
    rejects({ ...ok, phone: 'call me maybe' }, /phone/i);
  });
  test('TC-006 rejects over-long notes (>1000 chars) and names (>80 chars)', () => {
    rejects({ ...ok, notes: 'x'.repeat(1001) }, /too long/i);
    rejects({ ...ok, name: 'n'.repeat(81) }, /too long/i);
  });
  test('TC-007 phoneKey matches local and international formats of one number', () => {
    assert.equal(phoneKey('+27 82 123 4567'), phoneKey('082 123 4567'));
    assert.equal(phoneKey('+27 82 123 4567'), '821234567');
    assert.equal(phoneKey('12'), null);
  });
  test('TC-008 coordsText formats hemispheres correctly', () => {
    assert.equal(coordsText(-33.9249, 18.4241), '33.9249° S, 18.4241° E');
  });
});

describe('Unit: credential security (auth-security.js)', () => {
  test('TC-009 scrypt hash verifies the right password and rejects a wrong one', async () => {
    const h = await hashPassword('correct-horse-battery');
    assert.match(h, /^scrypt\$[0-9a-f]{32}\$[0-9a-f]{128}$/);
    assert.equal(await verifyPassword('correct-horse-battery', h), true);
    assert.equal(await verifyPassword('wrong-password-1234', h), false);
  });
  test('TC-010 hashing is salted (same password gives different hashes)', async () => {
    assert.notEqual(await hashPassword('same-password-123'), await hashPassword('same-password-123'));
  });
  test('TC-011 malformed stored hashes never verify', async () => {
    for (const bad of [null, '', 'plaintext', 'scrypt$zz$zz', 'bcrypt$00$00']) assert.equal(await verifyPassword('x', bad), false);
  });
  test('TC-012 session tokens are stored only as SHA-256 digests', () => {
    const d = hashSessionToken('abc');
    assert.match(d, /^[0-9a-f]{64}$/); assert.notEqual(d, 'abc');
  });
});
