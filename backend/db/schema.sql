-- AquaAlert schema (PostgreSQL + PostGIS).
-- Safe to run again: it creates what is missing and upgrades older databases without deleting data.
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE SEQUENCE IF NOT EXISTS report_seq START 10000;

CREATE TABLE IF NOT EXISTS dashboard_users (
  id            BIGSERIAL PRIMARY KEY,
  user_number   TEXT NOT NULL UNIQUE,
  display_name  TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  role          TEXT NOT NULL DEFAULT 'staff' CHECK (role IN ('admin','staff')),
  active        BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dashboard_sessions (
  token_hash TEXT PRIMARY KEY,
  user_id    BIGINT NOT NULL REFERENCES dashboard_users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS reports (
  id                BIGSERIAL PRIMARY KEY,
  tracking_id       TEXT NOT NULL UNIQUE DEFAULT ('AQ-' || nextval('report_seq')),
  device_id         TEXT NOT NULL,

  leak_type         TEXT NOT NULL CHECK (leak_type IN ('burst_pipe','visible_leak','running_water','equipment')),
  severity          TEXT NOT NULL CHECK (severity IN ('minor','major','emergency')),
  status            TEXT NOT NULL DEFAULT 'Received' CHECK (status IN ('Received','In Progress','Delayed','Resolved')),

  location          GEOGRAPHY(Point, 4326) NOT NULL,
  address           TEXT,
  street            TEXT,
  city              TEXT,
  notes             TEXT,
  photo_url         TEXT,

  reporter_name     TEXT,
  reporter_phone    TEXT,
  phone_key         TEXT,            -- last 9 digits of the phone number, used to find a person's reports

  duplicate_of      BIGINT REFERENCES reports(id) ON DELETE SET NULL,

  -- recorded by operations (null = nobody has recorded it)
  assigned_team     TEXT,
  team_lead         TEXT,
  assigned_user_id  BIGINT REFERENCES dashboard_users(id) ON DELETE SET NULL,
  arrival_note      TEXT,
  volume_loss_gph   INTEGER,
  pressure_psi      NUMERIC(6,1),
  first_response_at TIMESTAMPTZ,
  resolved_at       TIMESTAMPTZ,

  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Upgrades for databases created by earlier versions
ALTER TABLE reports ADD COLUMN IF NOT EXISTS phone_key TEXT;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS volume_loss_gph INTEGER;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS assigned_user_id BIGINT REFERENCES dashboard_users(id) ON DELETE SET NULL;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS street TEXT;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS city TEXT;

-- The old est_volume_gph column held a guess based on severity, not a measurement, so it is no longer used.
-- Only the sample data (device 'seed') is carried over, because its figures were entered by hand.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'reports' AND column_name = 'est_volume_gph') THEN
    UPDATE reports SET volume_loss_gph = est_volume_gph WHERE device_id = 'seed' AND volume_loss_gph IS NULL;
  END IF;
END $$;

-- Link existing reports that already have a phone number to the lookup key
UPDATE reports
   SET phone_key = right(regexp_replace(reporter_phone, '\D', '', 'g'), 9)
 WHERE phone_key IS NULL
   AND reporter_phone IS NOT NULL
   AND length(regexp_replace(reporter_phone, '\D', '', 'g')) BETWEEN 7 AND 15;

CREATE INDEX IF NOT EXISTS reports_location_gix ON reports USING GIST (location);
CREATE INDEX IF NOT EXISTS reports_status_idx   ON reports (status);
CREATE INDEX IF NOT EXISTS reports_device_idx   ON reports (device_id);
CREATE INDEX IF NOT EXISTS reports_phone_idx    ON reports (phone_key);
CREATE INDEX IF NOT EXISTS reports_created_idx  ON reports (created_at DESC);
CREATE INDEX IF NOT EXISTS reports_assigned_user_idx ON reports (assigned_user_id);
CREATE INDEX IF NOT EXISTS reports_city_idx ON reports (lower(city));

CREATE TABLE IF NOT EXISTS report_photos (
  report_id    BIGINT PRIMARY KEY REFERENCES reports(id) ON DELETE CASCADE,
  content_type TEXT NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp', 'image/gif')),
  image_data   BYTEA NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS report_activity (
  id         BIGSERIAL PRIMARY KEY,
  report_id  BIGINT NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  actor      TEXT NOT NULL,
  message    TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS activity_created_idx ON report_activity (created_at DESC);

-- Field teams. The dashboard's "teams assigned" figure is counted from this table.
CREATE TABLE IF NOT EXISTS teams (
  id     BIGSERIAL PRIMARY KEY,
  name   TEXT NOT NULL UNIQUE,
  lead   TEXT,
  active BOOLEAN NOT NULL DEFAULT true
);

-- Pick up teams that earlier versions only stored as text on a report
INSERT INTO teams (name, lead)
SELECT DISTINCT ON (assigned_team) assigned_team, team_lead
  FROM reports
 WHERE assigned_team IS NOT NULL
 ORDER BY assigned_team, updated_at DESC
ON CONFLICT (name) DO NOTHING;

INSERT INTO teams (name) VALUES
  ('Burst Pipe Repairs Team'),
  ('Water Leak Repairs Team'),
  ('Valve Maintenance Team'),
  ('Pipeline Maintenance Team'),
  ('Water Meter Maintenance Team'),
  ('Leak Detection and Inspection Team'),
  ('Pump Station Maintenance Team'),
  ('Reservoir and Tank Maintenance Team'),
  ('Water Quality and Treatment Team'),
  ('Emergency Water Response Team'),
  ('Water Network Maintenance Team')
ON CONFLICT (name) DO NOTHING;
