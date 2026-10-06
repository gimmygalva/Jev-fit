-- JEV FIT — migrazione locale v001_initial (M2, Agent 03). Speculare a
-- backend/supabase/migrations/20261006190920_v001_initial.sql per le tabelle "fatto".
-- Riferimento: docs/DATA_MODEL.md. IMMUTABILE dopo il rilascio: le modifiche vanno in v002+.
--
-- Convenzioni locali (DATA_MODEL §3):
--   - id e riferimenti a record: BLOB di 16 byte (UUIDv7 generato sul dispositivo; formato
--     predefinito di GRDB per UUID, nel cloud sono colonne uuid);
--   - istanti: TEXT "yyyy-MM-dd HH:mm:ss.SSS" in UTC (formato GRDB); day_key: TEXT "yyyy-MM-dd";
--   - numeri decimali REAL, booleani INTEGER 0/1, liste ed oggetti JSON in TEXT;
--   - le tabelle "fatto" NON hanno user_id: il dispositivo ha un solo proprietario
--     (schema_meta.local_owner_user_id dopo il primo login, SECURITY §5);
--   - colonne di sync: created_at, updated_at, deleted_at (tombstone), origin_device_id,
--     server_updated_at (ultimo valore visto dal server, NULL se mai sincronizzata),
--     sync_state ('pending' | 'synced' | 'conflict');
--   - FK tra tabelle "fatto" DEFERRABLE INITIALLY DEFERRED e senza cascade: si cancella solo con
--     tombstone, e la sync applica una pagina di record in una sola transazione (DATA_MODEL §5).
--   - ogni insert/update con sync_state = 'pending' accoda il record nell'outbox tramite trigger
--     (tabella outbox in fondo): la coda è sempre coerente con i dati, nella stessa transazione.

-- ═════════════════════════════════════════════════════════════════════════════════════════════
-- FATTI SINCRONIZZATI (F)
-- ═════════════════════════════════════════════════════════════════════════════════════════════

CREATE TABLE user_profile (
  id                     BLOB PRIMARY KEY NOT NULL,
  birth_year             INTEGER NOT NULL CHECK (birth_year BETWEEN 1900 AND 2100),
  height_cm              REAL NOT NULL CHECK (height_cm BETWEEN 100 AND 250),
  sex                    TEXT CHECK (sex IN ('male', 'female')),
  experience             TEXT NOT NULL CHECK (experience IN ('beginner', 'intermediate', 'advanced')),
  activity_level         TEXT NOT NULL CHECK (activity_level IN ('sedentary', 'light', 'moderate', 'high')),
  unit_system            TEXT NOT NULL DEFAULT 'metric' CHECK (unit_system IN ('metric', 'imperial')),
  energy_unit            TEXT NOT NULL DEFAULT 'kcal' CHECK (energy_unit IN ('kcal', 'kj')),
  pregnancy_or_lactation INTEGER CHECK (pregnancy_or_lactation IN (0, 1)),
  created_at             TEXT NOT NULL,
  updated_at             TEXT NOT NULL,
  deleted_at             TEXT,
  origin_device_id       BLOB,
  server_updated_at      TEXT,
  sync_state             TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE UNIQUE INDEX user_profile_one_alive ON user_profile ((1)) WHERE deleted_at IS NULL;

CREATE TABLE goal (
  id                   BLOB PRIMARY KEY NOT NULL,
  type                 TEXT NOT NULL CHECK (type IN ('strength', 'hypertrophy', 'maintenance', 'recomposition', 'fat_loss', 'general_fitness')),
  target_weight_kg     REAL CHECK (target_weight_kg BETWEEN 20 AND 400),
  target_rate_pct_week REAL CHECK (target_rate_pct_week BETWEEN -1.5 AND 1.0),
  started_at           TEXT NOT NULL,
  ended_at             TEXT CHECK (ended_at IS NULL OR ended_at >= started_at),
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL,
  deleted_at           TEXT,
  origin_device_id     BLOB,
  server_updated_at    TEXT,
  sync_state           TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);

CREATE TABLE app_settings (
  id                      BLOB PRIMARY KEY NOT NULL,
  macro_mode              TEXT NOT NULL DEFAULT 'auto' CHECK (macro_mode IN ('auto', 'assisted', 'manual')),
  check_in_weekday        INTEGER NOT NULL DEFAULT 1 CHECK (check_in_weekday BETWEEN 1 AND 7),
  calorie_cycling_enabled INTEGER NOT NULL DEFAULT 0 CHECK (calorie_cycling_enabled IN (0, 1)),
  notifications           TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(notifications) AND json_type(notifications) = 'object' AND length(notifications) <= 4096),
  display                 TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(display) AND json_type(display) = 'object' AND length(display) <= 4096),
  created_at              TEXT NOT NULL,
  updated_at              TEXT NOT NULL,
  deleted_at              TEXT,
  origin_device_id        BLOB,
  server_updated_at       TEXT,
  sync_state              TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE UNIQUE INDEX app_settings_one_alive ON app_settings ((1)) WHERE deleted_at IS NULL;

CREATE TABLE training_preferences (
  id                 BLOB PRIMARY KEY NOT NULL,
  days_per_week      INTEGER NOT NULL CHECK (days_per_week BETWEEN 1 AND 7),
  preferred_weekdays TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(preferred_weekdays) AND json_type(preferred_weekdays) = 'array'),
  session_minutes    INTEGER NOT NULL CHECK (session_minutes BETWEEN 15 AND 240),
  split_preference   TEXT CHECK (split_preference IN ('full_body', 'upper_lower', 'push_pull_legs', 'torso_limbs', 'hybrid', 'custom')),
  equipment          TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(equipment) AND json_type(equipment) = 'array'),
  muscle_priority    TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(muscle_priority) AND json_type(muscle_priority) = 'array'),
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,
  deleted_at         TEXT,
  origin_device_id   BLOB,
  server_updated_at  TEXT,
  sync_state         TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE UNIQUE INDEX training_preferences_one_alive ON training_preferences ((1)) WHERE deleted_at IS NULL;

CREATE TABLE limitation (
  id                BLOB PRIMARY KEY NOT NULL,
  body_area         TEXT NOT NULL CHECK (body_area IN ('shoulder', 'elbow', 'wrist', 'neck', 'lower_back', 'hip', 'knee', 'ankle', 'other')),
  severity          TEXT NOT NULL CHECK (severity IN ('mild', 'moderate')),
  note              TEXT CHECK (length(note) <= 1000),
  active            INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);

-- Corpo ---------------------------------------------------------------------------------------
CREATE TABLE weight_entry (
  id                BLOB PRIMARY KEY NOT NULL,
  measured_at       TEXT NOT NULL,
  day_key           TEXT NOT NULL CHECK (length(day_key) = 10),
  tz                TEXT NOT NULL CHECK (length(tz) BETWEEN 1 AND 64),
  weight_kg         REAL NOT NULL CHECK (weight_kg BETWEEN 20 AND 400),
  source            TEXT NOT NULL CHECK (source IN ('manual', 'healthkit')),
  hk_uuid           BLOB UNIQUE,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE INDEX weight_entry_day_idx ON weight_entry (day_key) WHERE deleted_at IS NULL;

CREATE TABLE body_measurement (
  id                BLOB PRIMARY KEY NOT NULL,
  type              TEXT NOT NULL CHECK (type IN ('body_fat_pct', 'waist', 'hips', 'chest', 'arm', 'thigh', 'neck')),
  value             REAL NOT NULL CHECK (value > 0 AND value <= 300),
  measured_at       TEXT NOT NULL,
  day_key           TEXT NOT NULL CHECK (length(day_key) = 10),
  tz                TEXT NOT NULL CHECK (length(tz) BETWEEN 1 AND 64),
  source            TEXT NOT NULL CHECK (source IN ('manual', 'healthkit')),
  hk_uuid           BLOB UNIQUE,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict')),
  CHECK (type <> 'body_fat_pct' OR value BETWEEN 2 AND 70)
);

CREATE TABLE subjective_check (
  id                BLOB PRIMARY KEY NOT NULL,
  day_key           TEXT NOT NULL CHECK (length(day_key) = 10),
  sleep_quality     INTEGER CHECK (sleep_quality BETWEEN 1 AND 5),
  energy            INTEGER CHECK (energy BETWEEN 1 AND 5),
  soreness          INTEGER CHECK (soreness BETWEEN 1 AND 5),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE UNIQUE INDEX subjective_check_one_per_day ON subjective_check (day_key) WHERE deleted_at IS NULL;

-- Esercizi custom ----------------------------------------------------------------------------
CREATE TABLE custom_exercise (
  id                    BLOB PRIMARY KEY NOT NULL,
  name                  TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
  load_type             TEXT NOT NULL CHECK (load_type IN ('external', 'bodyweight', 'assisted', 'timed')),
  equipment             TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(equipment) AND json_type(equipment) = 'array'),
  mechanics             TEXT CHECK (mechanics IN ('compound', 'isolation')),
  laterality            TEXT CHECK (laterality IN ('bilateral', 'unilateral')),
  bodyweight_fraction   REAL CHECK (bodyweight_fraction BETWEEN 0 AND 1.5),
  load_increment_kg     REAL CHECK (load_increment_kg > 0 AND load_increment_kg <= 50),
  contraindicated_areas TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(contraindicated_areas) AND json_type(contraindicated_areas) = 'array'),
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL,
  deleted_at            TEXT,
  origin_device_id      BLOB,
  server_updated_at     TEXT,
  sync_state            TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);

CREATE TABLE custom_exercise_muscle (
  id                 BLOB PRIMARY KEY NOT NULL,
  custom_exercise_id BLOB NOT NULL REFERENCES custom_exercise(id) DEFERRABLE INITIALLY DEFERRED,
  muscle             TEXT NOT NULL CHECK (muscle IN ('chest','lats','upper_back','front_delts','side_delts','rear_delts','biceps','triceps','forearms','abs','obliques','lower_back','glutes','quads','hamstrings','adductors','calves')),
  role               TEXT NOT NULL CHECK (role IN ('primary', 'secondary')),
  contribution       REAL NOT NULL CHECK (contribution > 0 AND contribution <= 1),
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,
  deleted_at         TEXT,
  origin_device_id   BLOB,
  server_updated_at  TEXT,
  sync_state         TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE UNIQUE INDEX custom_exercise_muscle_unique ON custom_exercise_muscle (custom_exercise_id, muscle) WHERE deleted_at IS NULL;

CREATE TABLE exercise_preference (
  id                 BLOB PRIMARY KEY NOT NULL,
  exercise_key       TEXT CHECK (length(exercise_key) BETWEEN 1 AND 64),
  custom_exercise_id BLOB REFERENCES custom_exercise(id) DEFERRABLE INITIALLY DEFERRED,
  kind               TEXT NOT NULL CHECK (kind IN ('favorite', 'excluded', 'disliked')),
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,
  deleted_at         TEXT,
  origin_device_id   BLOB,
  server_updated_at  TEXT,
  sync_state         TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict')),
  CHECK ((exercise_key IS NULL) <> (custom_exercise_id IS NULL))
);

CREATE TABLE recovery_calibration (
  id                  BLOB PRIMARY KEY NOT NULL,
  muscle              TEXT NOT NULL CHECK (muscle IN ('chest','lats','upper_back','front_delts','side_delts','rear_delts','biceps','triceps','forearms','abs','obliques','lower_back','glutes','quads','hamstrings','adductors','calves')),
  user_tau_multiplier REAL NOT NULL CHECK (user_tau_multiplier BETWEEN 0.5 AND 2.0),
  n_observations      INTEGER NOT NULL DEFAULT 0 CHECK (n_observations >= 0),
  created_at          TEXT NOT NULL,
  updated_at          TEXT NOT NULL,
  deleted_at          TEXT,
  origin_device_id    BLOB,
  server_updated_at   TEXT,
  sync_state          TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE UNIQUE INDEX recovery_calibration_one_per_muscle ON recovery_calibration (muscle) WHERE deleted_at IS NULL;

-- Programma e allenamenti --------------------------------------------------------------------
CREATE TABLE training_program (
  id                BLOB PRIMARY KEY NOT NULL,
  split             TEXT NOT NULL CHECK (split IN ('full_body', 'upper_lower', 'push_pull_legs', 'torso_limbs', 'hybrid', 'custom')),
  mesocycle_index   INTEGER NOT NULL DEFAULT 0 CHECK (mesocycle_index BETWEEN 0 AND 1000),
  week_index        INTEGER NOT NULL DEFAULT 0 CHECK (week_index BETWEEN 0 AND 52),
  scheme            TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(scheme) AND json_type(scheme) = 'object' AND length(scheme) <= 8192),
  status            TEXT NOT NULL CHECK (status IN ('active', 'completed', 'archived')),
  engine_version    INTEGER NOT NULL CHECK (engine_version >= 1),
  started_at        TEXT NOT NULL,
  ended_at          TEXT CHECK (ended_at IS NULL OR ended_at >= started_at),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);

CREATE TABLE workout_template (
  id                BLOB PRIMARY KEY NOT NULL,
  program_id        BLOB REFERENCES training_program(id) DEFERRABLE INITIALLY DEFERRED,
  sequence_index    INTEGER NOT NULL DEFAULT 0 CHECK (sequence_index BETWEEN 0 AND 100),
  name              TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
  focus_muscles     TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(focus_muscles) AND json_type(focus_muscles) = 'array'),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE INDEX workout_template_program_idx ON workout_template (program_id);

CREATE TABLE workout_template_exercise (
  id                 BLOB PRIMARY KEY NOT NULL,
  template_id        BLOB NOT NULL REFERENCES workout_template(id) DEFERRABLE INITIALLY DEFERRED,
  exercise_key       TEXT CHECK (length(exercise_key) BETWEEN 1 AND 64),
  custom_exercise_id BLOB REFERENCES custom_exercise(id) DEFERRABLE INITIALLY DEFERRED,
  position           INTEGER NOT NULL CHECK (position BETWEEN 0 AND 100),
  sets               INTEGER NOT NULL CHECK (sets BETWEEN 1 AND 20),
  rep_min            INTEGER NOT NULL CHECK (rep_min BETWEEN 1 AND 100),
  rep_max            INTEGER NOT NULL CHECK (rep_max BETWEEN 1 AND 100),
  target_rir         INTEGER CHECK (target_rir BETWEEN 0 AND 10),
  rest_s             INTEGER CHECK (rest_s BETWEEN 0 AND 1800),
  superset_group     INTEGER CHECK (superset_group BETWEEN 0 AND 50),
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,
  deleted_at         TEXT,
  origin_device_id   BLOB,
  server_updated_at  TEXT,
  sync_state         TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict')),
  CHECK ((exercise_key IS NULL) <> (custom_exercise_id IS NULL)),
  CHECK (rep_min <= rep_max)
);
CREATE INDEX workout_template_exercise_template_idx ON workout_template_exercise (template_id);

CREATE TABLE workout_session (
  id                BLOB PRIMARY KEY NOT NULL,
  template_id       BLOB REFERENCES workout_template(id) DEFERRABLE INITIALLY DEFERRED,
  program_id        BLOB REFERENCES training_program(id) DEFERRABLE INITIALLY DEFERRED,
  started_at        TEXT NOT NULL,
  ended_at          TEXT CHECK (ended_at IS NULL OR ended_at >= started_at),
  status            TEXT NOT NULL CHECK (status IN ('in_progress', 'completed', 'abandoned')),
  day_key           TEXT NOT NULL CHECK (length(day_key) = 10),
  tz                TEXT NOT NULL CHECK (length(tz) BETWEEN 1 AND 64),
  notes             TEXT CHECK (length(notes) <= 1000),
  source            TEXT NOT NULL DEFAULT 'app' CHECK (source IN ('app', 'manual')),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE INDEX workout_session_day_idx ON workout_session (day_key) WHERE deleted_at IS NULL;
-- Al massimo un workout in corso sul dispositivo (ripresa dopo la chiusura dell'app, PS §11.2).
CREATE UNIQUE INDEX workout_session_one_in_progress ON workout_session (status) WHERE status = 'in_progress' AND deleted_at IS NULL;

CREATE TABLE workout_exercise (
  id                               BLOB PRIMARY KEY NOT NULL,
  session_id                       BLOB NOT NULL REFERENCES workout_session(id) DEFERRABLE INITIALLY DEFERRED,
  exercise_key                     TEXT CHECK (length(exercise_key) BETWEEN 1 AND 64),
  custom_exercise_id               BLOB REFERENCES custom_exercise(id) DEFERRABLE INITIALLY DEFERRED,
  position                         INTEGER NOT NULL CHECK (position BETWEEN 0 AND 100),
  replaced_from_exercise_key       TEXT CHECK (length(replaced_from_exercise_key) BETWEEN 1 AND 64),
  replaced_from_custom_exercise_id BLOB REFERENCES custom_exercise(id) DEFERRABLE INITIALLY DEFERRED,
  superset_group                   INTEGER CHECK (superset_group BETWEEN 0 AND 50),
  created_at                       TEXT NOT NULL,
  updated_at                       TEXT NOT NULL,
  deleted_at                       TEXT,
  origin_device_id                 BLOB,
  server_updated_at                TEXT,
  sync_state                       TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict')),
  CHECK ((exercise_key IS NULL) <> (custom_exercise_id IS NULL)),
  CHECK (replaced_from_exercise_key IS NULL OR replaced_from_custom_exercise_id IS NULL)
);
CREATE INDEX workout_exercise_session_idx ON workout_exercise (session_id);
CREATE INDEX workout_exercise_key_idx ON workout_exercise (exercise_key);

CREATE TABLE workout_set (
  id                  BLOB PRIMARY KEY NOT NULL,
  workout_exercise_id BLOB NOT NULL REFERENCES workout_exercise(id) DEFERRABLE INITIALLY DEFERRED,
  set_index           INTEGER NOT NULL CHECK (set_index BETWEEN 0 AND 100),
  set_type            TEXT NOT NULL CHECK (set_type IN ('warmup', 'working', 'top', 'backoff', 'drop', 'failure', 'amrap')),
  weight_kg           REAL CHECK (weight_kg BETWEEN 0 AND 1000),
  entered_value       REAL CHECK (entered_value BETWEEN 0 AND 2500),
  entered_unit        TEXT CHECK (entered_unit IN ('kg', 'lb')),
  added_load_kg       REAL CHECK (added_load_kg BETWEEN -300 AND 500),
  reps                INTEGER CHECK (reps BETWEEN 0 AND 200),
  rir                 REAL CHECK (rir BETWEEN 0 AND 10),
  rpe                 REAL CHECK (rpe BETWEEN 1 AND 10),
  duration_s          INTEGER CHECK (duration_s BETWEEN 0 AND 36000),
  rest_s              INTEGER CHECK (rest_s BETWEEN 0 AND 3600),
  completed_at        TEXT,
  target_weight_kg    REAL CHECK (target_weight_kg BETWEEN 0 AND 1000),
  target_reps         INTEGER CHECK (target_reps BETWEEN 0 AND 200),
  pain_level          TEXT NOT NULL DEFAULT 'none' CHECK (pain_level IN ('none', 'mild', 'strong')),
  created_at          TEXT NOT NULL,
  updated_at          TEXT NOT NULL,
  deleted_at          TEXT,
  origin_device_id    BLOB,
  server_updated_at   TEXT,
  sync_state          TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict')),
  CHECK ((entered_value IS NULL) = (entered_unit IS NULL))
);
CREATE INDEX workout_set_exercise_idx ON workout_set (workout_exercise_id);

CREATE TABLE pain_report (
  id                 BLOB PRIMARY KEY NOT NULL,
  day_key            TEXT NOT NULL CHECK (length(day_key) = 10),
  body_area          TEXT NOT NULL CHECK (body_area IN ('shoulder', 'elbow', 'wrist', 'neck', 'lower_back', 'hip', 'knee', 'ankle', 'other')),
  level              TEXT NOT NULL CHECK (level IN ('mild', 'strong')),
  exercise_key       TEXT CHECK (length(exercise_key) BETWEEN 1 AND 64),
  custom_exercise_id BLOB REFERENCES custom_exercise(id) DEFERRABLE INITIALLY DEFERRED,
  workout_set_id     BLOB REFERENCES workout_set(id) DEFERRABLE INITIALLY DEFERRED,
  acknowledged_at    TEXT,
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,
  deleted_at         TEXT,
  origin_device_id   BLOB,
  server_updated_at  TEXT,
  sync_state         TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict')),
  CHECK (exercise_key IS NULL OR custom_exercise_id IS NULL)
);
CREATE INDEX pain_report_unacknowledged_idx ON pain_report (day_key) WHERE acknowledged_at IS NULL AND deleted_at IS NULL;

-- Nutrizione ---------------------------------------------------------------------------------
CREATE TABLE custom_food (
  id                BLOB PRIMARY KEY NOT NULL,
  name              TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
  brand             TEXT CHECK (length(brand) <= 120),
  barcode           TEXT CHECK (length(barcode) BETWEEN 8 AND 14 AND barcode NOT GLOB '*[^0-9]*'),
  energy_kcal       REAL NOT NULL CHECK (energy_kcal BETWEEN 0 AND 900),
  protein_g         REAL NOT NULL CHECK (protein_g BETWEEN 0 AND 100),
  carbs_g           REAL NOT NULL CHECK (carbs_g BETWEEN 0 AND 100),
  fat_g             REAL NOT NULL CHECK (fat_g BETWEEN 0 AND 100),
  fiber_g           REAL CHECK (fiber_g BETWEEN 0 AND 100),
  sugar_g           REAL CHECK (sugar_g BETWEEN 0 AND 100),
  sat_fat_g         REAL CHECK (sat_fat_g BETWEEN 0 AND 100),
  sodium_mg         REAL CHECK (sodium_mg BETWEEN 0 AND 40000),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict')),
  CHECK (protein_g + carbs_g + fat_g <= 100)
);
CREATE INDEX custom_food_barcode_idx ON custom_food (barcode) WHERE barcode IS NOT NULL;

CREATE TABLE custom_food_serving (
  id                BLOB PRIMARY KEY NOT NULL,
  custom_food_id    BLOB NOT NULL REFERENCES custom_food(id) DEFERRABLE INITIALLY DEFERRED,
  label             TEXT NOT NULL CHECK (length(label) BETWEEN 1 AND 60),
  grams             REAL NOT NULL CHECK (grams > 0 AND grams <= 5000),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE INDEX custom_food_serving_food_idx ON custom_food_serving (custom_food_id);

CREATE TABLE recipe (
  id                BLOB PRIMARY KEY NOT NULL,
  name              TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
  yield_grams       REAL CHECK (yield_grams > 0 AND yield_grams <= 50000),
  servings          REAL CHECK (servings > 0 AND servings <= 100),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);

CREATE TABLE recipe_ingredient (
  id                BLOB PRIMARY KEY NOT NULL,
  recipe_id         BLOB NOT NULL REFERENCES recipe(id) DEFERRABLE INITIALLY DEFERRED,
  position          INTEGER NOT NULL DEFAULT 0 CHECK (position BETWEEN 0 AND 200),
  food_source       TEXT NOT NULL CHECK (food_source IN ('catalog', 'custom', 'open_food_facts', 'usda')),
  food_source_id    TEXT NOT NULL CHECK (length(food_source_id) BETWEEN 1 AND 64),
  food_name         TEXT NOT NULL CHECK (length(food_name) BETWEEN 1 AND 160),
  grams             REAL NOT NULL CHECK (grams > 0 AND grams <= 10000),
  energy_kcal_100g  REAL NOT NULL CHECK (energy_kcal_100g BETWEEN 0 AND 900),
  protein_g_100g    REAL NOT NULL CHECK (protein_g_100g BETWEEN 0 AND 100),
  carbs_g_100g      REAL NOT NULL CHECK (carbs_g_100g BETWEEN 0 AND 100),
  fat_g_100g        REAL NOT NULL CHECK (fat_g_100g BETWEEN 0 AND 100),
  fiber_g_100g      REAL CHECK (fiber_g_100g BETWEEN 0 AND 100),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE INDEX recipe_ingredient_recipe_idx ON recipe_ingredient (recipe_id);

CREATE TABLE saved_meal (
  id                BLOB PRIMARY KEY NOT NULL,
  name              TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);

CREATE TABLE saved_meal_item (
  id                BLOB PRIMARY KEY NOT NULL,
  saved_meal_id     BLOB NOT NULL REFERENCES saved_meal(id) DEFERRABLE INITIALLY DEFERRED,
  position          INTEGER NOT NULL DEFAULT 0 CHECK (position BETWEEN 0 AND 200),
  food_source       TEXT NOT NULL CHECK (food_source IN ('catalog', 'custom', 'open_food_facts', 'usda', 'recipe')),
  food_source_id    TEXT NOT NULL CHECK (length(food_source_id) BETWEEN 1 AND 64),
  food_name         TEXT NOT NULL CHECK (length(food_name) BETWEEN 1 AND 160),
  grams             REAL NOT NULL CHECK (grams > 0 AND grams <= 10000),
  energy_kcal_100g  REAL NOT NULL CHECK (energy_kcal_100g BETWEEN 0 AND 900),
  protein_g_100g    REAL NOT NULL CHECK (protein_g_100g BETWEEN 0 AND 100),
  carbs_g_100g      REAL NOT NULL CHECK (carbs_g_100g BETWEEN 0 AND 100),
  fat_g_100g        REAL NOT NULL CHECK (fat_g_100g BETWEEN 0 AND 100),
  fiber_g_100g      REAL CHECK (fiber_g_100g BETWEEN 0 AND 100),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE INDEX saved_meal_item_meal_idx ON saved_meal_item (saved_meal_id);

CREATE TABLE food_log_entry (
  id                BLOB PRIMARY KEY NOT NULL,
  day_key           TEXT NOT NULL CHECK (length(day_key) = 10),
  tz                TEXT NOT NULL CHECK (length(tz) BETWEEN 1 AND 64),
  meal_slot         TEXT NOT NULL CHECK (meal_slot IN ('breakfast', 'lunch', 'dinner', 'snack')),
  logged_at         TEXT NOT NULL,
  food_source       TEXT NOT NULL CHECK (food_source IN ('catalog', 'custom', 'open_food_facts', 'usda', 'recipe', 'quick_add')),
  food_source_id    TEXT CHECK (length(food_source_id) BETWEEN 1 AND 64),
  food_name         TEXT CHECK (length(food_name) BETWEEN 1 AND 160),
  grams             REAL CHECK (grams > 0 AND grams <= 10000),
  servings          REAL CHECK (servings > 0 AND servings <= 100),
  serving_label     TEXT CHECK (length(serving_label) BETWEEN 1 AND 60),
  energy_kcal       REAL NOT NULL CHECK (energy_kcal BETWEEN 0 AND 20000),
  protein_g         REAL NOT NULL CHECK (protein_g BETWEEN 0 AND 2000),
  carbs_g           REAL NOT NULL CHECK (carbs_g BETWEEN 0 AND 2000),
  fat_g             REAL NOT NULL CHECK (fat_g BETWEEN 0 AND 2000),
  fiber_g           REAL CHECK (fiber_g BETWEEN 0 AND 2000),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict')),
  CHECK (food_source = 'quick_add' OR (food_source_id IS NOT NULL AND food_name IS NOT NULL AND grams IS NOT NULL))
);
CREATE INDEX food_log_entry_day_idx ON food_log_entry (day_key) WHERE deleted_at IS NULL;

CREATE TABLE weekly_check_in (
  id                BLOB PRIMARY KEY NOT NULL,
  week_start        TEXT NOT NULL CHECK (length(week_start) = 10),
  metrics           TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(metrics) AND json_type(metrics) = 'object' AND length(metrics) <= 16384),
  decisions         TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(decisions) AND json_type(decisions) = 'array' AND length(decisions) <= 16384),
  responses         TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(responses) AND json_type(responses) = 'object' AND length(responses) <= 4096),
  engine_version    INTEGER NOT NULL CHECK (engine_version >= 1),
  completed_at      TEXT,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE UNIQUE INDEX weekly_check_in_one_per_week ON weekly_check_in (week_start) WHERE deleted_at IS NULL;

CREATE TABLE nutrition_day (
  id                BLOB PRIMARY KEY NOT NULL,
  day_key           TEXT NOT NULL CHECK (length(day_key) = 10),
  status            TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'complete', 'incomplete')),
  day_type          TEXT NOT NULL DEFAULT 'rest' CHECK (day_type IN ('training', 'rest')),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE UNIQUE INDEX nutrition_day_one_per_day ON nutrition_day (day_key) WHERE deleted_at IS NULL;

CREATE TABLE nutrition_target (
  id                BLOB PRIMARY KEY NOT NULL,
  effective_from    TEXT NOT NULL CHECK (length(effective_from) = 10),
  mode              TEXT NOT NULL CHECK (mode IN ('auto', 'assisted', 'manual')),
  kcal_training     REAL NOT NULL CHECK (kcal_training BETWEEN 800 AND 10000),
  kcal_rest         REAL NOT NULL CHECK (kcal_rest BETWEEN 800 AND 10000),
  weekly_avg_kcal   REAL NOT NULL CHECK (weekly_avg_kcal BETWEEN 800 AND 10000),
  origin            TEXT NOT NULL CHECK (origin IN ('onboarding', 'check_in', 'manual')),
  check_in_id       BLOB REFERENCES weekly_check_in(id) DEFERRABLE INITIALLY DEFERRED,
  engine_version    INTEGER NOT NULL CHECK (engine_version >= 1),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE INDEX nutrition_target_effective_idx ON nutrition_target (effective_from) WHERE deleted_at IS NULL;

CREATE TABLE macro_target (
  id                  BLOB PRIMARY KEY NOT NULL,
  nutrition_target_id BLOB NOT NULL REFERENCES nutrition_target(id) DEFERRABLE INITIALLY DEFERRED,
  day_type            TEXT NOT NULL CHECK (day_type IN ('training', 'rest')),
  protein_g           REAL NOT NULL CHECK (protein_g BETWEEN 0 AND 600),
  carbs_g             REAL NOT NULL CHECK (carbs_g BETWEEN 0 AND 1500),
  fat_g               REAL NOT NULL CHECK (fat_g BETWEEN 0 AND 600),
  fiber_g             REAL CHECK (fiber_g BETWEEN 0 AND 150),
  created_at          TEXT NOT NULL,
  updated_at          TEXT NOT NULL,
  deleted_at          TEXT,
  origin_device_id    BLOB,
  server_updated_at   TEXT,
  sync_state          TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
CREATE UNIQUE INDEX macro_target_one_per_day_type ON macro_target (nutrition_target_id, day_type) WHERE deleted_at IS NULL;

-- JEV ----------------------------------------------------------------------------------------
CREATE TABLE ai_recommendation (
  id                BLOB PRIMARY KEY NOT NULL,
  kind              TEXT NOT NULL CHECK (length(kind) BETWEEN 1 AND 40),
  payload           TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(payload) AND json_type(payload) = 'object' AND length(payload) <= 16384),
  text              TEXT CHECK (length(text) <= 4000),
  provider          TEXT CHECK (length(provider) <= 40),
  model             TEXT CHECK (length(model) <= 80),
  confidence        TEXT CHECK (confidence IN ('initial_estimate', 'calibrating', 'reliable')),
  status            TEXT NOT NULL CHECK (status IN ('proposed', 'accepted', 'rejected', 'expired')),
  check_in_id       BLOB REFERENCES weekly_check_in(id) DEFERRABLE INITIALLY DEFERRED,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  origin_device_id  BLOB,
  server_updated_at TEXT,
  sync_state        TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);

-- ═════════════════════════════════════════════════════════════════════════════════════════════
-- FATTI SOLO LOCALI (L)
-- ═════════════════════════════════════════════════════════════════════════════════════════════

-- Cache degli alimenti remoti (Open Food Facts, USDA via gateway). Contenuto di terzi non fidato.
CREATE TABLE food_cache (
  id                BLOB PRIMARY KEY NOT NULL,
  source            TEXT NOT NULL CHECK (source IN ('open_food_facts', 'usda')),
  source_id         TEXT NOT NULL CHECK (length(source_id) BETWEEN 1 AND 64),
  barcode           TEXT CHECK (length(barcode) BETWEEN 8 AND 14 AND barcode NOT GLOB '*[^0-9]*'),
  name              TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 160),
  brand             TEXT CHECK (length(brand) <= 120),
  energy_kcal       REAL NOT NULL CHECK (energy_kcal BETWEEN 0 AND 900),
  protein_g         REAL NOT NULL CHECK (protein_g BETWEEN 0 AND 100),
  carbs_g           REAL NOT NULL CHECK (carbs_g BETWEEN 0 AND 100),
  fat_g             REAL NOT NULL CHECK (fat_g BETWEEN 0 AND 100),
  fiber_g           REAL CHECK (fiber_g BETWEEN 0 AND 100),
  sugar_g           REAL CHECK (sugar_g BETWEEN 0 AND 100),
  sat_fat_g         REAL CHECK (sat_fat_g BETWEEN 0 AND 100),
  sodium_mg         REAL CHECK (sodium_mg BETWEEN 0 AND 40000),
  servings          TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(servings) AND json_type(servings) = 'array'),
  verified          INTEGER NOT NULL DEFAULT 0 CHECK (verified IN (0, 1)),
  fetched_at        TEXT NOT NULL,
  last_used_at      TEXT,
  UNIQUE (source, source_id)
);
CREATE INDEX food_cache_barcode_idx ON food_cache (barcode) WHERE barcode IS NOT NULL;

CREATE TABLE ai_conversation (
  id         BLOB PRIMARY KEY NOT NULL,
  started_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE ai_message (
  id              BLOB PRIMARY KEY NOT NULL,
  conversation_id BLOB NOT NULL REFERENCES ai_conversation(id) ON DELETE CASCADE,
  role            TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content         TEXT NOT NULL CHECK (length(content) <= 8000),
  context_refs    TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(context_refs) AND json_type(context_refs) = 'array'),
  created_at      TEXT NOT NULL
);
CREATE INDEX ai_message_conversation_idx ON ai_message (conversation_id, created_at);

-- ═════════════════════════════════════════════════════════════════════════════════════════════
-- DERIVATI (D): cache ricalcolabili dagli engine, mai sincronizzate (ADR-005).
-- Ogni riga porta engine_version: al cambio di versione le tabelle vengono svuotate e ricalcolate.
-- exercise_ref: chiave del catalogo oppure "custom:<uuid>".
-- ═════════════════════════════════════════════════════════════════════════════════════════════

CREATE TABLE weight_trend_daily (
  day_key        TEXT PRIMARY KEY NOT NULL,
  trend_kg       REAL NOT NULL,
  slope_kg_week  REAL NOT NULL,
  sd_kg          REAL NOT NULL CHECK (sd_kg >= 0),
  engine_version INTEGER NOT NULL,
  computed_at    TEXT NOT NULL
);

CREATE TABLE performance_record (
  session_id     BLOB NOT NULL,
  exercise_ref   TEXT NOT NULL,
  best_e1rm_kg   REAL,
  volume_kg      REAL NOT NULL CHECK (volume_kg >= 0),
  hard_sets      INTEGER NOT NULL CHECK (hard_sets >= 0),
  top_set_id     BLOB,
  engine_version INTEGER NOT NULL,
  computed_at    TEXT NOT NULL,
  PRIMARY KEY (session_id, exercise_ref)
);

CREATE TABLE exercise_trend (
  exercise_ref   TEXT NOT NULL,
  day_key        TEXT NOT NULL,
  e1rm_stable_kg REAL NOT NULL,
  sd_kg          REAL NOT NULL CHECK (sd_kg >= 0),
  plateau        INTEGER NOT NULL DEFAULT 0 CHECK (plateau IN (0, 1)),
  engine_version INTEGER NOT NULL,
  computed_at    TEXT NOT NULL,
  PRIMARY KEY (exercise_ref, day_key)
);

CREATE TABLE personal_record (
  exercise_ref   TEXT NOT NULL,
  kind           TEXT NOT NULL CHECK (kind IN ('e1rm', 'reps_at_weight', 'volume')),
  value          REAL NOT NULL,
  achieved_at    TEXT NOT NULL,
  set_id         BLOB,
  engine_version INTEGER NOT NULL,
  computed_at    TEXT NOT NULL,
  PRIMARY KEY (exercise_ref, kind)
);

CREATE TABLE muscle_recovery (
  muscle         TEXT PRIMARY KEY NOT NULL,
  as_of          TEXT NOT NULL,
  recovery_pct   REAL NOT NULL CHECK (recovery_pct BETWEEN 0 AND 100),
  fatigue_state  TEXT NOT NULL,
  eta_ready_at   TEXT,
  engine_version INTEGER NOT NULL,
  computed_at    TEXT NOT NULL
);

CREATE TABLE readiness_entry (
  day_key        TEXT PRIMARY KEY NOT NULL,
  score          INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
  components     TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(components)),
  confidence     TEXT NOT NULL CHECK (confidence IN ('initial_estimate', 'calibrating', 'reliable')),
  engine_version INTEGER NOT NULL,
  computed_at    TEXT NOT NULL
);

CREATE TABLE daily_nutrition (
  day_key        TEXT PRIMARY KEY NOT NULL,
  energy_kcal    REAL NOT NULL,
  protein_g      REAL NOT NULL,
  carbs_g        REAL NOT NULL,
  fat_g          REAL NOT NULL,
  fiber_g        REAL,
  entry_count    INTEGER NOT NULL CHECK (entry_count >= 0),
  adherence      REAL,
  engine_version INTEGER NOT NULL,
  computed_at    TEXT NOT NULL
);

CREATE TABLE energy_expenditure (
  day_key        TEXT PRIMARY KEY NOT NULL,
  tdee_kcal      REAL NOT NULL,
  sd_kcal        REAL NOT NULL CHECK (sd_kcal >= 0),
  confidence     TEXT NOT NULL CHECK (confidence IN ('initial_estimate', 'calibrating', 'reliable')),
  prior_weight   REAL NOT NULL CHECK (prior_weight BETWEEN 0 AND 1),
  engine_version INTEGER NOT NULL,
  computed_at    TEXT NOT NULL
);

-- ═════════════════════════════════════════════════════════════════════════════════════════════
-- SISTEMA: outbox e cursori di sync
-- ═════════════════════════════════════════════════════════════════════════════════════════════

-- Una riga per record da inviare (coalescing): il push legge lo stato ATTUALE del record, quindi
-- più modifiche prima della sync diventano un solo upsert. Le cancellazioni sono tombstone, cioè
-- upsert: non esiste un'operazione "delete". last_error contiene solo un codice (SECURITY §3).
CREATE TABLE outbox (
  seq             INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name      TEXT NOT NULL,
  record_id       BLOB NOT NULL,
  enqueued_at     TEXT NOT NULL,
  -- Incrementata a ogni nuova modifica del record: il push conferma solo la revisione inviata.
  revision        INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
  attempts        INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  next_attempt_at TEXT,
  last_error      TEXT CHECK (length(last_error) <= 64),
  UNIQUE (table_name, record_id)
);

CREATE TABLE sync_cursor (
  table_name             TEXT PRIMARY KEY NOT NULL,
  last_server_updated_at TEXT NOT NULL
);

-- Accodamento automatico nell'outbox (una riga per record, vedi sopra). Generato per tutte
-- le tabelle con sync_state; la sync che applica record dal server scrive sync_state = 'synced'
-- e quindi non accoda nulla.
CREATE TRIGGER user_profile_outbox_insert AFTER INSERT ON user_profile WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('user_profile', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER user_profile_outbox_update AFTER UPDATE ON user_profile WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('user_profile', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER goal_outbox_insert AFTER INSERT ON goal WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('goal', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER goal_outbox_update AFTER UPDATE ON goal WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('goal', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER app_settings_outbox_insert AFTER INSERT ON app_settings WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('app_settings', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER app_settings_outbox_update AFTER UPDATE ON app_settings WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('app_settings', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER training_preferences_outbox_insert AFTER INSERT ON training_preferences WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('training_preferences', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER training_preferences_outbox_update AFTER UPDATE ON training_preferences WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('training_preferences', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER limitation_outbox_insert AFTER INSERT ON limitation WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('limitation', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER limitation_outbox_update AFTER UPDATE ON limitation WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('limitation', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER weight_entry_outbox_insert AFTER INSERT ON weight_entry WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('weight_entry', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER weight_entry_outbox_update AFTER UPDATE ON weight_entry WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('weight_entry', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER body_measurement_outbox_insert AFTER INSERT ON body_measurement WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('body_measurement', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER body_measurement_outbox_update AFTER UPDATE ON body_measurement WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('body_measurement', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER subjective_check_outbox_insert AFTER INSERT ON subjective_check WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('subjective_check', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER subjective_check_outbox_update AFTER UPDATE ON subjective_check WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('subjective_check', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER custom_exercise_outbox_insert AFTER INSERT ON custom_exercise WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('custom_exercise', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER custom_exercise_outbox_update AFTER UPDATE ON custom_exercise WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('custom_exercise', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER custom_exercise_muscle_outbox_insert AFTER INSERT ON custom_exercise_muscle WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('custom_exercise_muscle', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER custom_exercise_muscle_outbox_update AFTER UPDATE ON custom_exercise_muscle WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('custom_exercise_muscle', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER exercise_preference_outbox_insert AFTER INSERT ON exercise_preference WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('exercise_preference', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER exercise_preference_outbox_update AFTER UPDATE ON exercise_preference WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('exercise_preference', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER recovery_calibration_outbox_insert AFTER INSERT ON recovery_calibration WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('recovery_calibration', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER recovery_calibration_outbox_update AFTER UPDATE ON recovery_calibration WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('recovery_calibration', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER training_program_outbox_insert AFTER INSERT ON training_program WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('training_program', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER training_program_outbox_update AFTER UPDATE ON training_program WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('training_program', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER workout_template_outbox_insert AFTER INSERT ON workout_template WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('workout_template', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER workout_template_outbox_update AFTER UPDATE ON workout_template WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('workout_template', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER workout_template_exercise_outbox_insert AFTER INSERT ON workout_template_exercise WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('workout_template_exercise', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER workout_template_exercise_outbox_update AFTER UPDATE ON workout_template_exercise WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('workout_template_exercise', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER workout_session_outbox_insert AFTER INSERT ON workout_session WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('workout_session', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER workout_session_outbox_update AFTER UPDATE ON workout_session WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('workout_session', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER workout_exercise_outbox_insert AFTER INSERT ON workout_exercise WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('workout_exercise', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER workout_exercise_outbox_update AFTER UPDATE ON workout_exercise WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('workout_exercise', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER workout_set_outbox_insert AFTER INSERT ON workout_set WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('workout_set', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER workout_set_outbox_update AFTER UPDATE ON workout_set WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('workout_set', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER pain_report_outbox_insert AFTER INSERT ON pain_report WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('pain_report', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER pain_report_outbox_update AFTER UPDATE ON pain_report WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('pain_report', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER custom_food_outbox_insert AFTER INSERT ON custom_food WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('custom_food', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER custom_food_outbox_update AFTER UPDATE ON custom_food WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('custom_food', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER custom_food_serving_outbox_insert AFTER INSERT ON custom_food_serving WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('custom_food_serving', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER custom_food_serving_outbox_update AFTER UPDATE ON custom_food_serving WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('custom_food_serving', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER recipe_outbox_insert AFTER INSERT ON recipe WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('recipe', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER recipe_outbox_update AFTER UPDATE ON recipe WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('recipe', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER recipe_ingredient_outbox_insert AFTER INSERT ON recipe_ingredient WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('recipe_ingredient', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER recipe_ingredient_outbox_update AFTER UPDATE ON recipe_ingredient WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('recipe_ingredient', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER saved_meal_outbox_insert AFTER INSERT ON saved_meal WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('saved_meal', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER saved_meal_outbox_update AFTER UPDATE ON saved_meal WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('saved_meal', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER saved_meal_item_outbox_insert AFTER INSERT ON saved_meal_item WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('saved_meal_item', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER saved_meal_item_outbox_update AFTER UPDATE ON saved_meal_item WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('saved_meal_item', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER food_log_entry_outbox_insert AFTER INSERT ON food_log_entry WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('food_log_entry', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER food_log_entry_outbox_update AFTER UPDATE ON food_log_entry WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('food_log_entry', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER weekly_check_in_outbox_insert AFTER INSERT ON weekly_check_in WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('weekly_check_in', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER weekly_check_in_outbox_update AFTER UPDATE ON weekly_check_in WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('weekly_check_in', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER nutrition_day_outbox_insert AFTER INSERT ON nutrition_day WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('nutrition_day', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER nutrition_day_outbox_update AFTER UPDATE ON nutrition_day WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('nutrition_day', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER nutrition_target_outbox_insert AFTER INSERT ON nutrition_target WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('nutrition_target', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER nutrition_target_outbox_update AFTER UPDATE ON nutrition_target WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('nutrition_target', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER macro_target_outbox_insert AFTER INSERT ON macro_target WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('macro_target', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER macro_target_outbox_update AFTER UPDATE ON macro_target WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('macro_target', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER ai_recommendation_outbox_insert AFTER INSERT ON ai_recommendation WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('ai_recommendation', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
CREATE TRIGGER ai_recommendation_outbox_update AFTER UPDATE ON ai_recommendation WHEN NEW.sync_state = 'pending'
BEGIN
  INSERT INTO outbox (table_name, record_id, enqueued_at) VALUES ('ai_recommendation', NEW.id, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT (table_name, record_id) DO UPDATE SET enqueued_at = excluded.enqueued_at, revision = outbox.revision + 1, attempts = 0, next_attempt_at = NULL, last_error = NULL;
END;
