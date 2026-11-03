# AquaAlert backend tests

80 automated tests (unit, API integration against PostgreSQL/PostGIS, and performance) using Node's built-in test runner.

> **Warning:** the suite deletes all data in the database it uses. It only runs against a database whose name ends in `_test`.

## Files

| File | Purpose |
|---|---|
| `env.js` | Test configuration and safety guard (imported first by every test file) |
| `helpers.js` | Shared helpers (requests, database reset, test users) |
| `unit.test.js` | TC-001 to TC-012: validation and credential security |
| `api.test.js` | TC-013 to TC-072, TC-078 to TC-080: API, duplicate detection, tracking, auth, dashboard, resilience |
| `perf.test.js` | TC-073 to TC-077: performance with 10,000 stored reports |

## Requirements

- Node.js 20 or newer
- PostgreSQL 16 or newer with the PostGIS extension (a local install or Docker)

## Setup (Windows PowerShell, run from the `backend` folder)

1. Go to the backend folder and install packages:
   ```powershell
   Set-Location 'C:\path\to\aquaalert1\backend'
   npm.cmd install
   ```
2. Make sure PostgreSQL is running. If you use Docker: `docker compose up -d`.
3. Create the test database (the name must end in `_test`).
   - Local PostgreSQL:
     ```powershell
     & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -c "CREATE DATABASE aquaalert_test;"
     ```
   - Docker:
     ```powershell
     docker exec aquaalert-db psql -U aquaalert -d aquaalert -c "CREATE DATABASE aquaalert_test;"
     ```
4. Set the connection string. Use your own user and password. `DATABASE_URL` is read by `npm run migrate`; `TEST_DATABASE_URL` is read by the tests (they do not read `DATABASE_URL`).
   ```powershell
   $env:DATABASE_URL = "postgres://postgres:YOUR_PASSWORD@localhost:5432/aquaalert_test"
   $env:TEST_DATABASE_URL = $env:DATABASE_URL
   ```
   For the Docker defaults use `postgres://aquaalert:aquaalert@localhost:5432/aquaalert_test`.
5. Create the tables in the test database:
   ```powershell
   npm.cmd run migrate
   ```

The two variables only last for the current terminal window; set them again in a new one.

## Run

```powershell
node --test --test-concurrency=1 --test-force-exit --experimental-test-coverage --test-coverage-include="src/**" --test-coverage-exclude="src/scripts/**" --test-reporter=spec test/unit.test.js test/api.test.js test/perf.test.js
```

Save the output to a file (UTF-8):

```powershell
node --test --test-concurrency=1 --test-force-exit --experimental-test-coverage --test-coverage-include="src/**" --test-coverage-exclude="src/scripts/**" --test-reporter=spec test/unit.test.js test/api.test.js test/perf.test.js 2>&1 | Out-File -Encoding utf8 test-results.txt
```

## Expected result on the submitted code

80 tests: 69 pass, 11 fail. The 11 failures are known defects documented in the Defect Log: TC-016, 027, 028, 036, 045, 067, 068, 069, 070, 079 and 080. Server line coverage is about 92.7 percent. When a defect is fixed, its test should turn green.

Optional: set `PERF_ROWS` (default 10000) to change the size of the performance data set, and `TEST_PORT` (default 4100) if that port is in use.

## Troubleshooting

| Message | Fix |
|---|---|
| `Refusing to run: tests TRUNCATE tables` | The database name does not end in `_test`. Set `TEST_DATABASE_URL` to the `_test` database. |
| `password authentication failed` | The user or password in `TEST_DATABASE_URL` is wrong. |
| `extension "postgis" is not available` | Install PostGIS (Stack Builder > Spatial Extensions, or use the Docker image), then run `npm.cmd run migrate` again. |
| `Could not read package.json` | Run the commands from the `backend` folder. |
| `node` or `npm.cmd` not recognised | Close and reopen the terminal (or VS Code) after installing Node.js. |