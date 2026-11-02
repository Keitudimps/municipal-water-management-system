# AquaAlert API

Node.js (Express) + PostgreSQL with PostGIS.

## Run locally

For normal startup on this computer, follow the project
[run guide](../Start%20PostgreSQL%20and%20Backend.txt). In PowerShell, check
that PostgreSQL is running, then start the backend:

```powershell
Set-Location 'C:\Users\keitu\aquaalert1\backend'
$node = "$env:LOCALAPPDATA\Programs\nodejs-v24\node-v24.22.2-win-x64"
$env:Path = "$node;$env:Path"
& "$node\npm.cmd" run dev
```

Keep the terminal open while using the app. Check
<http://localhost:4000/health> for `"ok": true`. The detailed setup and
administration information below is for maintenance, not required at each
startup.

## What PostGIS does here

| Feature | Where |
|---|---|
| Report locations stored as `GEOGRAPHY(Point, 4326)` with a GiST index | `db/schema.sql` |
| **Duplicate detection**: an open report of the same type within 50 m in the last 24 h is flagged (`ST_DWithin`) | `POST /api/reports` |
| **Nearby search**, sorted by distance in metres (`ST_Distance`) | `GET /api/admin/incidents?lat=&lng=&radius=` |
| Open incidents as GeoJSON for a map layer (`ST_AsGeoJSON`) | `GET /api/admin/map` |

## Endpoints

Citizen app (no login; identified by an `X-Device-Id` header the app generates):

| Method | Path | Notes |
|---|---|---|
| POST | `/api/reports` | multipart: `leak_type`, `severity`, `lat`, `lng`, **`phone` (required)**, optional `name`, `notes`, `photo` |
| POST | `/api/reports/lookup` | JSON `{"phone": "..."}`: every report made with that number, from any device |
| GET | `/api/reports/:trackingId` | public status lookup |

Dashboard (staff sign-in; authenticated requests use a session):

| Method | Path | Notes |
|---|---|---|
| GET | `/api/admin/incidents` | `?status=&q=&lat=&lng=&radius=` |
| GET | `/api/admin/incidents/:id` | one incident |
| PATCH | `/api/admin/incidents/:id` | JSON, send only what changed (`null` clears): `status`, `team`, `arrivalNote`, `volumeGph`, `pressurePsi` |
| GET | `/api/admin/stats` | the four dashboard cards |
| GET | `/api/admin/teams` | field teams and whether each is on an open incident |
| POST | `/api/admin/teams` | JSON `{"name": "...", "lead": "..."}`: add a team |
| GET | `/api/admin/activity` | recent activity feed |
| GET | `/api/admin/map` | open incidents as GeoJSON |

## Where the dashboard's numbers come from

Everything on the dashboard is read from the database. Nothing is estimated.

| Figure | Source |
|---|---|
| Active incidents | reports whose status is not `Resolved` |
| Avg. response | average time from `created_at` to the first move to `In Progress`, last 7 days. Shows `—` if there are none |
| Teams assigned | teams (from the `teams` table) that currently have an open incident, out of all active teams |
| Water loss | sum of the volume-loss readings staff have **recorded** on open incidents. Shows `—` if none |
| Volume loss / pressure change on an incident | recorded by staff with **Update ops**; shows "Not recorded" until then |
| Narrative, reporter name | what the person typed; otherwise the dashboard says nothing was provided |

## How "My reports" works

A phone number is required when reporting. Reports are matched by the **last 9 digits** of the number, so
`+27 82 123 4567` and `082 123 4567` find the same reports. The app remembers the number, and **My reports** asks
for it if it doesn't have one. A device that sent reports before numbers were required gets those reports linked to
the first number it looks up.

`leak_type`: `burst_pipe`, `visible_leak`, `running_water`, `equipment`.
`severity`: `minor`, `major`, `emergency`.
`status`: `Received`, `In Progress`, `Delayed`, `Resolved`.

Example:

```bash
curl -X POST http://localhost:4000/api/reports \
  -H "X-Device-Id: my-phone" \
  -F leak_type=burst_pipe -F severity=emergency -F lat=25.7617 -F lng=-80.1918 \
  -F photo=@leak.jpg
```

## Upgrading an existing database

`npm.cmd run migrate` is safe to run on a database from an earlier version. It adds the phone lookup key, the
`volume_loss_gph` column and the `teams` table, and it creates teams from the team names already stored on reports.
The old `est_volume_gph` column held a guess based on severity, so it is no longer used or shown.
The migration creates the standard municipal repair teams. Admins can add
more teams from the dashboard or with `POST /api/admin/teams`.

## Before going live

- The dashboard uses one shared key. Replace it with real staff sign-in (JWT or SSO) and roles.
- **Phone numbers are not verified.** Anyone who knows a number can list that number's reports (tracking ID, type,
  address, status). Add an SMS one-time code before relying on this with real residents.
- Citizen reports are anonymous, so someone can submit false reports. The app has a basic per-device and
  per-IP limit (10 an hour); add a CAPTCHA or app attestation if abuse becomes a problem.
- Photos are saved to `UPLOAD_DIR` on the server's disk. Move them to object storage (S3, etc.) when you deploy to more than one server.
- Serve over HTTPS, set `CORS_ORIGIN` to your real web addresses, and set `PUBLIC_URL`.
- Phone numbers are personal data; decide how long to keep them.
