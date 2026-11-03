// Must be imported FIRST by every test file: configures the app for an isolated test run.
process.env.PORT = process.env.TEST_PORT || '4100';
process.env.DATABASE_URL = process.env.TEST_DATABASE_URL || 'postgres://aquaalert:aquaalert@localhost:5432/aquaalert_test';
process.env.ENABLE_GEOCODING = 'false';   // no calls to the public Nominatim service during tests
process.env.DUPLICATE_RADIUS_M = '50';
process.env.CORS_ORIGIN = '';

// Safety guard: the suite TRUNCATEs tables, so it must never run against a real database.
if (!/_test(\?|$)/.test(process.env.DATABASE_URL)) {
  throw new Error('Refusing to run: tests TRUNCATE tables. Use a database whose name ends in _test (see TEST_DATABASE_URL).');
}
