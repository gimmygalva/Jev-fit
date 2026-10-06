-- JEV FIT — cache HealthKit, migrazione h001 (M2, Agent 03). File SQLite separato ed escluso
-- dal backup (SECURITY SEC-LS-04, ADR-012). Solo aggregati giornalieri; ricostruibile da Salute.
-- IMMUTABILE dopo il rilascio.

CREATE TABLE health_metric_daily (
  day_key       TEXT PRIMARY KEY NOT NULL CHECK (length(day_key) = 10),
  steps         INTEGER CHECK (steps BETWEEN 0 AND 200000),
  active_kcal   REAL CHECK (active_kcal BETWEEN 0 AND 20000),
  sleep_minutes REAL CHECK (sleep_minutes BETWEEN 0 AND 1440),
  resting_hr    REAL CHECK (resting_hr BETWEEN 20 AND 250),
  hrv_sdnn_ms   REAL CHECK (hrv_sdnn_ms BETWEEN 0 AND 500),
  updated_at    TEXT NOT NULL
);
