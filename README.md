# AquaAlert

AquaAlert is a water-leak reporting application with a citizen site and an
operations dashboard. The project has two parts:

- `backend/` — Node.js API and PostgreSQL/PostGIS database.
- `aquaalert/` — Flutter web app.

These instructions describe a first-time setup on Windows using PowerShell,
Docker Desktop, and Chrome.

## Requirements

Install these before continuing:

1. [Git for Windows](https://git-scm.com/download/win), if you have not already
   downloaded the project.
2. [Docker Desktop](https://www.docker.com/products/docker-desktop/) — start it
   before starting the database.
3. [Node.js 20 or newer](https://nodejs.org/) — use the LTS version.
4. [Flutter](https://docs.flutter.dev/get-started/install/windows) — install
   the Flutter SDK and add its `bin` folder to your PATH.
5. [Google Chrome](https://www.google.com/chrome/).

Open a new PowerShell window after installing tools so that updated PATH
settings are picked up. Check that the commands are available:

```powershell
git --version
docker --version
node --version
flutter --version
```

## First-time setup

### 1. Start the database

Start Docker Desktop and wait until it says Docker is running. Then open
PowerShell and enter the backend folder:

```powershell
Set-Location 'C:\path\to\aquaalert1\backend'
docker compose up -d
```

Replace `C:\path\to\aquaalert1` with the folder where you downloaded the
project. This starts PostgreSQL with PostGIS. The database data is kept in a
Docker volume when the container is stopped.

If Docker reports that port `5432` is already in use, stop any other PostgreSQL
server using that port, then run `docker compose up -d` again.

### 2. Install backend packages and create the database tables

In the same PowerShell window, run:

```powershell
npm.cmd install
npm.cmd run migrate
```

Use `npm.cmd` in PowerShell so the commands work even when PowerShell blocks
the `npm.ps1` script. The project has local development defaults for connecting
to the database started above; no `.env` file is needed for a basic local run.

### 3. Create the first dashboard administrator

Create one administrator for this database:

```powershell
npm.cmd run create-admin
```

Follow the prompts to enter a staff number, name, and password. The password
must be at least 12 characters and is hidden while typing. Save these
credentials; use them to sign in to the dashboard. You only need to create the
administrator once. If an administrator already exists, skip this step.

Optional: add sample incidents for testing:

```powershell
npm.cmd run seed
```

### 4. Start the backend

Run this in the backend folder:

```powershell
npm.cmd run dev
```

Keep this PowerShell window open. Check that the API is responding at
<http://localhost:4000/health>. A successful response includes `"ok": true`
and a PostGIS version.

### 5. Install Flutter packages and start the app

Open a second PowerShell window:

```powershell
Set-Location 'C:\path\to\aquaalert1\aquaalert'
flutter pub get
flutter run -d chrome --web-port 5000
```

Replace `C:\path\to\aquaalert1` with the project folder path. Keep this window
open while using the app. Flutter opens Chrome; if it does not, visit:

- Citizen reporting: <http://localhost:5000/#/>
- Operations dashboard: <http://localhost:5000/#/dashboard>

Sign in to the dashboard using the administrator credentials from step 3.

## Start the app again later

After the first-time setup, you do not need to reinstall packages, rerun the
migration, or create another administrator.

1. Start Docker Desktop.
2. In PowerShell, go to `backend/` and run `docker compose up -d` if the
   database container is stopped.
3. In `backend/`, run `npm.cmd run dev` and leave the window open.
4. In a second PowerShell window, go to `aquaalert/` and run
   `flutter run -d chrome --web-port 5000`.

Press Ctrl+C in the backend and Flutter windows to stop those processes. Stop
the database container when you no longer need it:

```powershell
Set-Location 'C:\path\to\aquaalert1\backend'
docker compose stop
```

## Troubleshooting

- **`docker` is not recognized:** install Docker Desktop, start it, and reopen
  PowerShell.
- **`npm` is blocked by PowerShell:** use `npm.cmd` as shown above; do not
  change the PowerShell execution policy.
- **`node` is not recognized:** install Node.js 20 or newer, ensure it is on
  PATH, and reopen PowerShell.
- **`flutter` is not recognized:** add the Flutter SDK's `bin` folder to PATH
  and reopen PowerShell.
- **The health check fails:** make sure the database container and backend are
  running. The backend window displays database connection errors.
