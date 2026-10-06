-- JEV FIT — migrazione cloud v001 (M2, Agent 03). Speculare alla migrazione locale GRDB `v001_initial`.
-- Riferimenti: docs/DATA_MODEL.md, docs/SECURITY.md §6 (SEC-DB-01…10), ARCHITECTURE_PLAN §3.
--
-- Regole applicate a OGNI tabella "fatto" (F) di questo file:
--   - id uuid generato dal client (UUIDv7), user_id con default auth.uid(), colonne di sync comuni;
--   - RLS attiva nella stessa migrazione (SEC-DB-01), grant minimi, nessun privilegio ad anon;
--   - policy separate select/insert/update `to authenticated` con (select auth.uid()) = user_id;
--     insert/update richiedono anche il consenso `cloud_sync` attivo (SECURITY §6.6);
--   - NESSUN grant e nessuna policy DELETE: il client usa solo tombstone (deleted_at). Le
--     cancellazioni fisiche avvengono lato server (eliminazione account: cascade da auth.users);
--   - indice (user_id, server_updated_at) per RLS e pull (SEC-DB-04);
--   - trigger private.tg_fact_sync_columns (SEC-DB-05, QA-12, regole di merge di DATA_MODEL §5).
-- Nessuna FK tra tabelle "fatto": l'ordine di arrivo dei record durante la sync non è garantito
-- (DATA_MODEL §4.3). L'integrità referenziale è garantita sul dispositivo (FK nel DB locale).
-- Questa migrazione è IMMUTABILE dopo l'applicazione al progetto remoto: le modifiche vanno in v002+.

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- Schema private (non esposto da PostgREST)
-- ─────────────────────────────────────────────────────────────────────────────────────────────
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;   -- solo per private.has_active_consent()

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- Consensi (SECURITY §6.6, GDPR art. 7(1) e 9(2)(a))
-- ─────────────────────────────────────────────────────────────────────────────────────────────
create table public.user_consent (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind           text not null check (kind in ('cloud_sync', 'ai_online')),
  policy_version text not null check (char_length(policy_version) between 1 and 32),
  app_version    text check (char_length(app_version) <= 32),
  granted_at     timestamptz not null default now(),
  revoked_at     timestamptz
);
create index user_consent_user_kind_idx on public.user_consent (user_id, kind) where revoked_at is null;

alter table public.user_consent enable row level security;
revoke all on table public.user_consent from anon, authenticated;
grant select, insert on table public.user_consent to authenticated;
grant update (revoked_at) on table public.user_consent to authenticated;  -- si può solo revocare

create policy user_consent_select on public.user_consent
  for select to authenticated
  using ( (select auth.uid()) = user_id );
create policy user_consent_insert on public.user_consent
  for insert to authenticated
  with check ( (select auth.uid()) = user_id and revoked_at is null );
create policy user_consent_update on public.user_consent
  for update to authenticated
  using ( (select auth.uid()) = user_id and revoked_at is null )
  with check ( (select auth.uid()) = user_id and revoked_at is not null );

create or replace function private.has_active_consent(p_kind text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1 from public.user_consent c
    where c.user_id = (select auth.uid())
      and c.kind = p_kind
      and c.revoked_at is null
  );
$$;
revoke execute on function private.has_active_consent(text) from public, anon;
grant execute on function private.has_active_consent(text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- Trigger comune alle tabelle sincronizzate (SEC-DB-05, QA-12, DATA_MODEL §5)
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- Regole:
--   1. updated_at e created_at del client limitati a now() + 5 min (orologio avanti);
--   2. server_updated_at deciso dal server (cursore di pull), il valore del client è ignorato;
--   3. created_at immutabile;
--   4. il tombstone vince: una riga con deleted_at non torna mai viva e non cambia più;
--   5. last-writer-wins su updated_at: una scrittura più vecchia della riga salvata non la
--      sovrascrive (a meno che non sia un tombstone, regola 4).
-- Nei casi 4 e 5 la scrittura NON viene scartata in silenzio (return null): si mantengono i
-- valori salvati e si aggiorna comunque server_updated_at, così il client che ha scritto riceve
-- la versione del server al pull successivo (SECURITY §6.2, note al template).
create or replace function private.tg_fact_sync_columns()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := least(coalesce(new.updated_at, now()), now() + interval '5 minutes');
  new.created_at := least(coalesce(new.created_at, now()), now() + interval '5 minutes');
  if tg_op = 'UPDATE' then
    if old.deleted_at is not null
       or (new.deleted_at is null and new.updated_at < old.updated_at) then
      new := old;
    end if;
    new.created_at := old.created_at;
  end if;
  new.server_updated_at := now();
  return new;
end;
$$;
revoke execute on function private.tg_fact_sync_columns() from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- Tabelle "fatto". Colonne comuni in coda a ogni tabella:
--   created_at, updated_at, server_updated_at, deleted_at, origin_device_id
-- Unità canoniche (ADR-010): kg, kcal, grammi, secondi, cm, istanti UTC; day_key = giorno locale.
-- Gli enum sono check sui valori raw dei tipi di JevDomain.
-- ─────────────────────────────────────────────────────────────────────────────────────────────

-- Profilo e preferenze ------------------------------------------------------------------------
create table public.user_profile (
  id                     uuid primary key,
  user_id                uuid not null default auth.uid() references auth.users(id) on delete cascade,
  birth_year             smallint not null check (birth_year between 1900 and 2100),
  height_cm              numeric(4,1) not null check (height_cm between 100 and 250),
  sex                    text check (sex in ('male', 'female')),
  experience             text not null check (experience in ('beginner', 'intermediate', 'advanced')),
  activity_level         text not null check (activity_level in ('sedentary', 'light', 'moderate', 'high')),
  unit_system            text not null default 'metric' check (unit_system in ('metric', 'imperial')),
  energy_unit            text not null default 'kcal' check (energy_unit in ('kcal', 'kj')),
  pregnancy_or_lactation boolean,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  server_updated_at      timestamptz not null default now(),
  deleted_at             timestamptz,
  origin_device_id       uuid
);
-- Un solo profilo vivo per utente (DATA_MODEL §5.4: il secondo dispositivo adotta l'id del server).
create unique index user_profile_one_per_user on public.user_profile (user_id) where deleted_at is null;

create table public.goal (
  id                   uuid primary key,
  user_id              uuid not null default auth.uid() references auth.users(id) on delete cascade,
  type                 text not null check (type in ('strength', 'hypertrophy', 'maintenance', 'recomposition', 'fat_loss', 'general_fitness')),
  target_weight_kg     numeric(5,2) check (target_weight_kg between 20 and 400),
  target_rate_pct_week numeric(4,2) check (target_rate_pct_week between -1.50 and 1.00),
  started_at           timestamptz not null,
  ended_at             timestamptz check (ended_at is null or ended_at >= started_at),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  server_updated_at    timestamptz not null default now(),
  deleted_at           timestamptz,
  origin_device_id     uuid
);

create table public.app_settings (
  id                      uuid primary key,
  user_id                 uuid not null default auth.uid() references auth.users(id) on delete cascade,
  macro_mode              text not null default 'auto' check (macro_mode in ('auto', 'assisted', 'manual')),
  check_in_weekday        smallint not null default 1 check (check_in_weekday between 1 and 7),
  calorie_cycling_enabled boolean not null default false,
  notifications           jsonb not null default '{}'::jsonb
                          check (jsonb_typeof(notifications) = 'object' and octet_length(notifications::text) <= 4096),
  display                 jsonb not null default '{}'::jsonb
                          check (jsonb_typeof(display) = 'object' and octet_length(display::text) <= 4096),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  server_updated_at       timestamptz not null default now(),
  deleted_at              timestamptz,
  origin_device_id        uuid
);
create unique index app_settings_one_per_user on public.app_settings (user_id) where deleted_at is null;

create table public.training_preferences (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users(id) on delete cascade,
  days_per_week      smallint not null check (days_per_week between 1 and 7),
  preferred_weekdays smallint[] not null default '{}'
                     check (preferred_weekdays <@ array[1,2,3,4,5,6,7]::smallint[]),
  session_minutes    smallint not null check (session_minutes between 15 and 240),
  split_preference   text check (split_preference in ('full_body', 'upper_lower', 'push_pull_legs', 'torso_limbs', 'hybrid', 'custom')),
  equipment          text[] not null default '{}'
                     check (equipment <@ array['barbell','dumbbell','kettlebell','cable','machine','smith_machine','ez_bar','trap_bar','pull_up_bar','dip_station','bench','resistance_band','bodyweight']),
  muscle_priority    text[] not null default '{}'
                     check (muscle_priority <@ array['chest','lats','upper_back','front_delts','side_delts','rear_delts','biceps','triceps','forearms','abs','obliques','lower_back','glutes','quads','hamstrings','adductors','calves']),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  server_updated_at  timestamptz not null default now(),
  deleted_at         timestamptz,
  origin_device_id   uuid
);
create unique index training_preferences_one_per_user on public.training_preferences (user_id) where deleted_at is null;

-- Riferimento a un esercizio: chiave del catalogo incluso nell'app OPPURE id di un esercizio custom.
create table public.exercise_preference (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users(id) on delete cascade,
  exercise_key       text check (char_length(exercise_key) between 1 and 64),
  custom_exercise_id uuid,
  kind               text not null check (kind in ('favorite', 'excluded', 'disliked')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  server_updated_at  timestamptz not null default now(),
  deleted_at         timestamptz,
  origin_device_id   uuid,
  check (num_nonnulls(exercise_key, custom_exercise_id) = 1)
);

create table public.limitation (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  body_area         text not null check (body_area in ('shoulder', 'elbow', 'wrist', 'neck', 'lower_back', 'hip', 'knee', 'ankle', 'other')),
  severity          text not null check (severity in ('mild', 'moderate')),
  note              text check (char_length(note) <= 1000),
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);

-- Corpo ---------------------------------------------------------------------------------------
create table public.weight_entry (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  measured_at       timestamptz not null,
  day_key           date not null,
  tz                text not null check (char_length(tz) between 1 and 64),
  weight_kg         numeric(5,2) not null check (weight_kg between 20 and 400),
  source            text not null check (source in ('manual', 'healthkit')),
  hk_uuid           uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid,
  unique (user_id, hk_uuid)
);

-- value in unità canonica del tipo: percentuale per body_fat_pct, centimetri per le circonferenze.
create table public.body_measurement (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  type              text not null check (type in ('body_fat_pct', 'waist', 'hips', 'chest', 'arm', 'thigh', 'neck')),
  value             numeric(5,1) not null check (value > 0 and value <= 300),
  measured_at       timestamptz not null,
  day_key           date not null,
  tz                text not null check (char_length(tz) between 1 and 64),
  source            text not null check (source in ('manual', 'healthkit')),
  hk_uuid           uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid,
  unique (user_id, hk_uuid),
  check (type <> 'body_fat_pct' or value between 2 and 70)
);

create table public.subjective_check (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day_key           date not null,
  sleep_quality     smallint check (sleep_quality between 1 and 5),
  energy            smallint check (energy between 1 and 5),
  soreness          smallint check (soreness between 1 and 5),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);
create unique index subjective_check_one_per_day on public.subjective_check (user_id, day_key) where deleted_at is null;

-- Esercizi custom ----------------------------------------------------------------------------
create table public.custom_exercise (
  id                    uuid primary key,
  user_id               uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name                  text not null check (char_length(name) between 1 and 120),
  load_type             text not null check (load_type in ('external', 'bodyweight', 'assisted', 'timed')),
  equipment             text[] not null default '{}'
                        check (equipment <@ array['barbell','dumbbell','kettlebell','cable','machine','smith_machine','ez_bar','trap_bar','pull_up_bar','dip_station','bench','resistance_band','bodyweight']),
  mechanics             text check (mechanics in ('compound', 'isolation')),
  laterality            text check (laterality in ('bilateral', 'unilateral')),
  bodyweight_fraction   numeric(3,2) check (bodyweight_fraction between 0 and 1.5),
  load_increment_kg     numeric(4,2) check (load_increment_kg > 0 and load_increment_kg <= 50),
  contraindicated_areas text[] not null default '{}'
                        check (contraindicated_areas <@ array['shoulder','elbow','wrist','neck','lower_back','hip','knee','ankle','other']),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  server_updated_at     timestamptz not null default now(),
  deleted_at            timestamptz,
  origin_device_id      uuid
);

create table public.custom_exercise_muscle (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users(id) on delete cascade,
  custom_exercise_id uuid not null,
  muscle             text not null check (muscle in ('chest','lats','upper_back','front_delts','side_delts','rear_delts','biceps','triceps','forearms','abs','obliques','lower_back','glutes','quads','hamstrings','adductors','calves')),
  role               text not null check (role in ('primary', 'secondary')),
  contribution       numeric(3,2) not null check (contribution > 0 and contribution <= 1),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  server_updated_at  timestamptz not null default now(),
  deleted_at         timestamptz,
  origin_device_id   uuid
);
create unique index custom_exercise_muscle_unique on public.custom_exercise_muscle (user_id, custom_exercise_id, muscle) where deleted_at is null;

create table public.recovery_calibration (
  id                  uuid primary key,
  user_id             uuid not null default auth.uid() references auth.users(id) on delete cascade,
  muscle              text not null check (muscle in ('chest','lats','upper_back','front_delts','side_delts','rear_delts','biceps','triceps','forearms','abs','obliques','lower_back','glutes','quads','hamstrings','adductors','calves')),
  user_tau_multiplier numeric(4,3) not null check (user_tau_multiplier between 0.5 and 2.0),
  n_observations      integer not null default 0 check (n_observations >= 0),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  server_updated_at   timestamptz not null default now(),
  deleted_at          timestamptz,
  origin_device_id    uuid
);
create unique index recovery_calibration_one_per_muscle on public.recovery_calibration (user_id, muscle) where deleted_at is null;

-- Programma e allenamenti --------------------------------------------------------------------
create table public.training_program (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  split             text not null check (split in ('full_body', 'upper_lower', 'push_pull_legs', 'torso_limbs', 'hybrid', 'custom')),
  mesocycle_index   smallint not null default 0 check (mesocycle_index between 0 and 1000),
  week_index        smallint not null default 0 check (week_index between 0 and 52),
  scheme            jsonb not null default '{}'::jsonb
                    check (jsonb_typeof(scheme) = 'object' and octet_length(scheme::text) <= 8192),
  status            text not null check (status in ('active', 'completed', 'archived')),
  engine_version    integer not null check (engine_version >= 1),
  started_at        timestamptz not null,
  ended_at          timestamptz check (ended_at is null or ended_at >= started_at),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);

create table public.workout_template (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  program_id        uuid,
  sequence_index    smallint not null default 0 check (sequence_index between 0 and 100),
  name              text not null check (char_length(name) between 1 and 120),
  focus_muscles     text[] not null default '{}'
                    check (focus_muscles <@ array['chest','lats','upper_back','front_delts','side_delts','rear_delts','biceps','triceps','forearms','abs','obliques','lower_back','glutes','quads','hamstrings','adductors','calves']),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);

create table public.workout_template_exercise (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users(id) on delete cascade,
  template_id        uuid not null,
  exercise_key       text check (char_length(exercise_key) between 1 and 64),
  custom_exercise_id uuid,
  position           smallint not null check (position between 0 and 100),
  sets               smallint not null check (sets between 1 and 20),
  rep_min            smallint not null check (rep_min between 1 and 100),
  rep_max            smallint not null check (rep_max between 1 and 100),
  target_rir         smallint check (target_rir between 0 and 10),
  rest_s             integer check (rest_s between 0 and 1800),
  superset_group     smallint check (superset_group between 0 and 50),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  server_updated_at  timestamptz not null default now(),
  deleted_at         timestamptz,
  origin_device_id   uuid,
  check (num_nonnulls(exercise_key, custom_exercise_id) = 1),
  check (rep_min <= rep_max)
);

create table public.workout_session (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  template_id       uuid,
  program_id        uuid,
  started_at        timestamptz not null,
  ended_at          timestamptz check (ended_at is null or ended_at >= started_at),
  status            text not null check (status in ('in_progress', 'completed', 'abandoned')),
  day_key           date not null,
  tz                text not null check (char_length(tz) between 1 and 64),
  notes             text check (char_length(notes) <= 1000),
  source            text not null default 'app' check (source in ('app', 'manual')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);

create table public.workout_exercise (
  id                               uuid primary key,
  user_id                          uuid not null default auth.uid() references auth.users(id) on delete cascade,
  session_id                       uuid not null,
  exercise_key                     text check (char_length(exercise_key) between 1 and 64),
  custom_exercise_id               uuid,
  position                         smallint not null check (position between 0 and 100),
  replaced_from_exercise_key       text check (char_length(replaced_from_exercise_key) between 1 and 64),
  replaced_from_custom_exercise_id uuid,
  superset_group                   smallint check (superset_group between 0 and 50),
  created_at                       timestamptz not null default now(),
  updated_at                       timestamptz not null default now(),
  server_updated_at                timestamptz not null default now(),
  deleted_at                       timestamptz,
  origin_device_id                 uuid,
  check (num_nonnulls(exercise_key, custom_exercise_id) = 1),
  check (num_nonnulls(replaced_from_exercise_key, replaced_from_custom_exercise_id) <= 1)
);

-- added_load_kg: zavorra (> 0) o assistenza (< 0) per gli esercizi a corpo libero (QA-01).
-- entered_value/entered_unit: il valore come digitato, per non creare falsi PR da conversione lb↔kg.
create table public.workout_set (
  id                  uuid primary key,
  user_id             uuid not null default auth.uid() references auth.users(id) on delete cascade,
  workout_exercise_id uuid not null,
  set_index           smallint not null check (set_index between 0 and 100),
  set_type            text not null check (set_type in ('warmup', 'working', 'top', 'backoff', 'drop', 'failure', 'amrap')),
  weight_kg           numeric(6,2) check (weight_kg between 0 and 1000),
  entered_value       numeric(7,2) check (entered_value between 0 and 2500),
  entered_unit        text check (entered_unit in ('kg', 'lb')),
  added_load_kg       numeric(6,2) check (added_load_kg between -300 and 500),
  reps                smallint check (reps between 0 and 200),
  rir                 numeric(3,1) check (rir between 0 and 10),
  rpe                 numeric(3,1) check (rpe between 1 and 10),
  duration_s          integer check (duration_s between 0 and 36000),
  rest_s              integer check (rest_s between 0 and 3600),
  completed_at        timestamptz,
  target_weight_kg    numeric(6,2) check (target_weight_kg between 0 and 1000),
  target_reps         smallint check (target_reps between 0 and 200),
  pain_level          text not null default 'none' check (pain_level in ('none', 'mild', 'strong')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  server_updated_at   timestamptz not null default now(),
  deleted_at          timestamptz,
  origin_device_id    uuid,
  check ((entered_value is null) = (entered_unit is null))
);

create table public.pain_report (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day_key            date not null,
  body_area          text not null check (body_area in ('shoulder', 'elbow', 'wrist', 'neck', 'lower_back', 'hip', 'knee', 'ankle', 'other')),
  level              text not null check (level in ('mild', 'strong')),
  exercise_key       text check (char_length(exercise_key) between 1 and 64),
  custom_exercise_id uuid,
  workout_set_id     uuid,
  acknowledged_at    timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  server_updated_at  timestamptz not null default now(),
  deleted_at         timestamptz,
  origin_device_id   uuid,
  check (num_nonnulls(exercise_key, custom_exercise_id) <= 1)
);

-- Nutrizione ---------------------------------------------------------------------------------
-- Nutrienti per 100 g. Sodio in mg.
create table public.custom_food (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name              text not null check (char_length(name) between 1 and 120),
  brand             text check (char_length(brand) <= 120),
  barcode           text check (barcode ~ '^[0-9]{8,14}$'),
  energy_kcal       numeric(5,1) not null check (energy_kcal between 0 and 900),
  protein_g         numeric(5,2) not null check (protein_g between 0 and 100),
  carbs_g           numeric(5,2) not null check (carbs_g between 0 and 100),
  fat_g             numeric(5,2) not null check (fat_g between 0 and 100),
  fiber_g           numeric(5,2) check (fiber_g between 0 and 100),
  sugar_g           numeric(5,2) check (sugar_g between 0 and 100),
  sat_fat_g         numeric(5,2) check (sat_fat_g between 0 and 100),
  sodium_mg         numeric(7,1) check (sodium_mg between 0 and 40000),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid,
  check (protein_g + carbs_g + fat_g <= 100)
);

create table public.custom_food_serving (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  custom_food_id    uuid not null,
  label             text not null check (char_length(label) between 1 and 60),
  grams             numeric(7,2) not null check (grams > 0 and grams <= 5000),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);

create table public.recipe (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name              text not null check (char_length(name) between 1 and 120),
  yield_grams       numeric(8,2) check (yield_grams > 0 and yield_grams <= 50000),
  servings          numeric(5,2) check (servings > 0 and servings <= 100),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);

-- Ingredienti e voci di pasti salvati: riferimento all'alimento + snapshot dei nutrienti per 100 g
-- (un alimento Open Food Facts esiste solo nella cache locale, ADR-009).
create table public.recipe_ingredient (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  recipe_id         uuid not null,
  position          smallint not null default 0 check (position between 0 and 200),
  food_source       text not null check (food_source in ('catalog', 'custom', 'open_food_facts', 'usda')),
  food_source_id    text not null check (char_length(food_source_id) between 1 and 64),
  food_name         text not null check (char_length(food_name) between 1 and 160),
  grams             numeric(7,2) not null check (grams > 0 and grams <= 10000),
  energy_kcal_100g  numeric(5,1) not null check (energy_kcal_100g between 0 and 900),
  protein_g_100g    numeric(5,2) not null check (protein_g_100g between 0 and 100),
  carbs_g_100g      numeric(5,2) not null check (carbs_g_100g between 0 and 100),
  fat_g_100g        numeric(5,2) not null check (fat_g_100g between 0 and 100),
  fiber_g_100g      numeric(5,2) check (fiber_g_100g between 0 and 100),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);

create table public.saved_meal (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name              text not null check (char_length(name) between 1 and 120),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);

create table public.saved_meal_item (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  saved_meal_id     uuid not null,
  position          smallint not null default 0 check (position between 0 and 200),
  food_source       text not null check (food_source in ('catalog', 'custom', 'open_food_facts', 'usda', 'recipe')),
  food_source_id    text not null check (char_length(food_source_id) between 1 and 64),
  food_name         text not null check (char_length(food_name) between 1 and 160),
  grams             numeric(7,2) not null check (grams > 0 and grams <= 10000),
  energy_kcal_100g  numeric(5,1) not null check (energy_kcal_100g between 0 and 900),
  protein_g_100g    numeric(5,2) not null check (protein_g_100g between 0 and 100),
  carbs_g_100g      numeric(5,2) not null check (carbs_g_100g between 0 and 100),
  fat_g_100g        numeric(5,2) not null check (fat_g_100g between 0 and 100),
  fiber_g_100g      numeric(5,2) check (fiber_g_100g between 0 and 100),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);

-- Voce del diario: snapshot dei TOTALI della porzione (ADR-009: lo storico non cambia se il
-- provider modifica il prodotto). quick_add: solo calorie/macro, senza alimento.
create table public.food_log_entry (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day_key           date not null,
  tz                text not null check (char_length(tz) between 1 and 64),
  meal_slot         text not null check (meal_slot in ('breakfast', 'lunch', 'dinner', 'snack')),
  logged_at         timestamptz not null,
  food_source       text not null check (food_source in ('catalog', 'custom', 'open_food_facts', 'usda', 'recipe', 'quick_add')),
  food_source_id    text check (char_length(food_source_id) between 1 and 64),
  food_name         text check (char_length(food_name) between 1 and 160),
  grams             numeric(7,2) check (grams > 0 and grams <= 10000),
  servings          numeric(6,2) check (servings > 0 and servings <= 100),
  serving_label     text check (char_length(serving_label) between 1 and 60),
  energy_kcal       numeric(6,1) not null check (energy_kcal between 0 and 20000),
  protein_g         numeric(6,2) not null check (protein_g between 0 and 2000),
  carbs_g           numeric(6,2) not null check (carbs_g between 0 and 2000),
  fat_g             numeric(6,2) not null check (fat_g between 0 and 2000),
  fiber_g           numeric(6,2) check (fiber_g between 0 and 2000),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid,
  check (food_source = 'quick_add' or (food_source_id is not null and food_name is not null and grams is not null))
);

create table public.nutrition_day (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day_key           date not null,
  status            text not null default 'open' check (status in ('open', 'complete', 'incomplete')),
  day_type          text not null default 'rest' check (day_type in ('training', 'rest')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);
create unique index nutrition_day_one_per_day on public.nutrition_day (user_id, day_key) where deleted_at is null;

create table public.nutrition_target (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  effective_from    date not null,
  mode              text not null check (mode in ('auto', 'assisted', 'manual')),
  kcal_training     numeric(6,1) not null check (kcal_training between 800 and 10000),
  kcal_rest         numeric(6,1) not null check (kcal_rest between 800 and 10000),
  weekly_avg_kcal   numeric(6,1) not null check (weekly_avg_kcal between 800 and 10000),
  origin            text not null check (origin in ('onboarding', 'check_in', 'manual')),
  check_in_id       uuid,
  engine_version    integer not null check (engine_version >= 1),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);

create table public.macro_target (
  id                  uuid primary key,
  user_id             uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nutrition_target_id uuid not null,
  day_type            text not null check (day_type in ('training', 'rest')),
  protein_g           numeric(5,1) not null check (protein_g between 0 and 600),
  carbs_g             numeric(5,1) not null check (carbs_g between 0 and 1500),
  fat_g               numeric(5,1) not null check (fat_g between 0 and 600),
  fiber_g             numeric(5,1) check (fiber_g between 0 and 150),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  server_updated_at   timestamptz not null default now(),
  deleted_at          timestamptz,
  origin_device_id    uuid
);
create unique index macro_target_one_per_day_type on public.macro_target (user_id, nutrition_target_id, day_type) where deleted_at is null;

-- JEV ----------------------------------------------------------------------------------------
-- Snapshot decisionali: fatti immutabili dopo la conferma (ADR-005). I JSON seguono gli schemi
-- versionati del CheckInEngine (`engine_version`).
create table public.weekly_check_in (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  week_start        date not null,
  metrics           jsonb not null default '{}'::jsonb
                    check (jsonb_typeof(metrics) = 'object' and octet_length(metrics::text) <= 16384),
  decisions         jsonb not null default '[]'::jsonb
                    check (jsonb_typeof(decisions) = 'array' and octet_length(decisions::text) <= 16384),
  responses         jsonb not null default '{}'::jsonb
                    check (jsonb_typeof(responses) = 'object' and octet_length(responses::text) <= 4096),
  engine_version    integer not null check (engine_version >= 1),
  completed_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);
create unique index weekly_check_in_one_per_week on public.weekly_check_in (user_id, week_start) where deleted_at is null;

create table public.ai_recommendation (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind              text not null check (char_length(kind) between 1 and 40),
  payload           jsonb not null default '{}'::jsonb
                    check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 16384),
  text              text check (char_length(text) <= 4000),
  provider          text check (char_length(provider) <= 40),
  model             text check (char_length(model) <= 80),
  confidence        text check (confidence in ('initial_estimate', 'calibrating', 'reliable')),
  status            text not null check (status in ('proposed', 'accepted', 'rejected', 'expired')),
  check_in_id       uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid
);

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- Indice di sync, trigger, RLS, grant e policy: identici per tutte le tabelle "fatto".
-- Il blocco genera SQL statico per un elenco esplicito di tabelle; il meta-test pgTAP
-- (tests/rls_meta.test.sql) verifica il risultato su tutto lo schema.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  t text;
  fact_tables constant text[] := array[
    'user_profile', 'goal', 'app_settings', 'training_preferences', 'exercise_preference',
    'limitation', 'weight_entry', 'body_measurement', 'subjective_check',
    'custom_exercise', 'custom_exercise_muscle', 'recovery_calibration',
    'training_program', 'workout_template', 'workout_template_exercise',
    'workout_session', 'workout_exercise', 'workout_set', 'pain_report',
    'custom_food', 'custom_food_serving', 'recipe', 'recipe_ingredient',
    'saved_meal', 'saved_meal_item', 'food_log_entry', 'nutrition_day',
    'nutrition_target', 'macro_target', 'weekly_check_in', 'ai_recommendation'
  ];
begin
  foreach t in array fact_tables loop
    execute format('create index %I on public.%I (user_id, server_updated_at)', t || '_user_sync_idx', t);
    execute format(
      'create trigger %I before insert or update on public.%I '
      'for each row execute function private.tg_fact_sync_columns()',
      t || '_sync_columns', t);

    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
    execute format('grant select, insert, update on table public.%I to authenticated', t);

    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using ( (select auth.uid()) = user_id )',
      t || '_select', t);
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check ( (select auth.uid()) = user_id '
      'and (select private.has_active_consent(''cloud_sync'')) )',
      t || '_insert', t);
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using ( (select auth.uid()) = user_id ) '
      'with check ( (select auth.uid()) = user_id '
      'and (select private.has_active_consent(''cloud_sync'')) )',
      t || '_update', t);
  end loop;
end;
$$;
