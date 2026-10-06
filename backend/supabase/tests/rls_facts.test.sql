-- Test RLS e regole di sync per OGNI tabella "fatto" (SECURITY §6.4, casi 1–11, + DATA_MODEL §5).
-- Ogni tabella riceve gli stessi casi tramite pg_temp.check_fact_table(); la fixture indica solo
-- le colonne obbligatorie specifiche di ciascuna tabella.
--
-- Casi per tabella (14 asserzioni):
--   1 A vede solo le proprie righe              8  anon: permesso negato (42501)
--   2 A non legge le righe di B                 9  updated_at limitato a now() + 5 min
--   3 update sulle righe di B: 0 righe          10 server_updated_at deciso dal server
--   4 delete fisico negato al client (42501)    11 insert senza consenso cloud_sync: 42501
--   5 insert con user_id di B: 42501            12 il tombstone vince (la riga non torna viva)
--   6 A non può cedere una riga a B: 42501      13 last-writer-wins: scrittura vecchia ignorata
--   7 upsert sull'id di B: 42501                14 user_id assegnato da auth.uid() se omesso
--   (+ riga di B invariata dopo i casi 3 e 7, verificata come postgres)
begin;
create extension if not exists pgtap with schema extensions;
select plan(31 * 15 + 1);

-- Utenti: A e B con consenso cloud_sync, C senza consenso.
insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'a@test.invalid'),
  ('00000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'b@test.invalid'),
  ('00000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'c@test.invalid');
insert into public.user_consent (user_id, kind, policy_version) values
  ('00000000-0000-0000-0000-00000000000a', 'cloud_sync', 'test'),
  ('00000000-0000-0000-0000-00000000000b', 'cloud_sync', 'test');

-- Esegue `sql` con il ruolo e il JWT indicati. Restituisce il SQLSTATE ('00000' se ok) e,
-- in `affected`, le righe toccate (o lette, per una select di conteggio).
create function pg_temp.run_as(p_role text, p_sub text, p_sql text, out code text, out affected bigint)
language plpgsql as $$
begin
  affected := 0;
  begin
    perform set_config('request.jwt.claims',
      case when p_sub is null then '{"role":"anon"}'
           else json_build_object('sub', p_sub, 'role', p_role)::text end, true);
    execute format('set local role %I', p_role);
    execute p_sql;
    get diagnostics affected = row_count;
    reset role;
    code := '00000';
  exception when others then
    -- Il sotto-blocco viene annullato, compreso il cambio di ruolo.
    code := SQLSTATE;
  end;
end;
$$;

create function pg_temp.count_as(p_sub text, p_sql text) returns bigint
language plpgsql as $$
declare n bigint;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true);
  set local role authenticated;
  execute p_sql into n;
  reset role;
  return n;
end;
$$;

create function pg_temp.check_fact_table(t text, cols text, vals text) returns setof text
language plpgsql as $$
declare
  a constant text := '00000000-0000-0000-0000-00000000000a';
  b constant text := '00000000-0000-0000-0000-00000000000b';
  c constant text := '00000000-0000-0000-0000-00000000000c';
  id_a  uuid := gen_random_uuid();
  id_b  uuid := gen_random_uuid();
  id_a2 uuid := gen_random_uuid();
  id_a3 uuid := gen_random_uuid();
  id_a4 uuid := gen_random_uuid();
  -- `ins` viene formattato una seconda volta: i % dei valori vanno raddoppiati.
  ins   text := format('insert into public.%I (id, user_id, %s) values (%%L, %%L, %s)', t, cols, replace(vals, '%', '%%'));
  b_before jsonb;
  r record;
  st text;
  n bigint;
  ok_flag boolean;
begin
  -- Fixture come postgres (bypassa la RLS).
  execute format(ins, id_a, a);
  execute format(ins, id_b, b);
  execute format('select to_jsonb(x) from public.%I x where id = %L', t, id_b) into b_before;

  -- 1, 2
  return next is(pg_temp.count_as(a, format('select count(*) from public.%I', t)), 1::bigint,
    t || ': A vede solo la propria riga');
  return next is(pg_temp.count_as(a, format('select count(*) from public.%I where user_id = %L', t, b)), 0::bigint,
    t || ': A non legge le righe di B');

  -- 3
  select * into r from pg_temp.run_as('authenticated', a,
    format('update public.%I set origin_device_id = gen_random_uuid() where id = %L', t, id_b));
  return next ok(r.code = '00000' and r.affected = 0, t || ': update sulle righe di B non tocca nulla');

  -- 4
  select * into r from pg_temp.run_as('authenticated', a, format('delete from public.%I where id = %L', t, id_a));
  return next is(r.code, '42501', t || ': delete fisico negato al client');

  -- 5
  select * into r from pg_temp.run_as('authenticated', a, format(ins, gen_random_uuid(), b));
  return next is(r.code, '42501', t || ': insert con user_id di B rifiutato');

  -- 6
  select * into r from pg_temp.run_as('authenticated', a,
    format('update public.%I set user_id = %L where id = %L', t, b, id_a));
  return next is(r.code, '42501', t || ': A non può cedere una riga a B');

  -- 7
  select * into r from pg_temp.run_as('authenticated', a,
    format(ins, id_b, a) || ' on conflict (id) do update set origin_device_id = excluded.origin_device_id');
  return next is(r.code, '42501', t || ': upsert sull''id di una riga di B rifiutato');

  -- riga di B invariata dopo 3 e 7
  execute format('select to_jsonb(x) = %L::jsonb from public.%I x where id = %L', b_before, t, id_b) into ok_flag;
  return next ok(ok_flag, t || ': la riga di B è invariata');

  -- 8
  select * into r from pg_temp.run_as('anon', null, format('select * from public.%I', t));
  return next is(r.code, '42501', t || ': anon non ha privilegi');

  -- 9, 10: insert di A con orologio sbagliato (updated_at nel futuro, server_updated_at nel passato)
  select * into r from pg_temp.run_as('authenticated', a,
    format('insert into public.%I (id, user_id, %s, updated_at, server_updated_at) values (%L, %L, %s, now() + interval ''3 days'', now() - interval ''30 days'')',
      t, cols, id_a2, a, vals));
  execute format('select updated_at <= now() + interval ''5 minutes'' and server_updated_at = now() from public.%I where id = %L', t, id_a2)
    into ok_flag;
  return next ok(r.code = '00000' and coalesce(ok_flag, false), t || ': orologio del client limitato a now() + 5 min');
  execute format('select server_updated_at = now() from public.%I where id = %L', t, id_a2) into ok_flag;
  return next ok(coalesce(ok_flag, false), t || ': server_updated_at assegnato dal server');

  -- 11
  select * into r from pg_temp.run_as('authenticated', c, format(ins, gen_random_uuid(), c));
  return next is(r.code, '42501', t || ': insert senza consenso cloud_sync rifiutato');

  -- 12: il tombstone vince
  execute format(ins, id_a3, a);
  select * into r from pg_temp.run_as('authenticated', a,
    format('update public.%I set deleted_at = now(), updated_at = now() - interval ''1 hour'' where id = %L', t, id_a3));
  select * into r from pg_temp.run_as('authenticated', a,
    format('update public.%I set deleted_at = null, updated_at = now() + interval ''1 minute'' where id = %L', t, id_a3));
  execute format('select deleted_at is not null from public.%I where id = %L', t, id_a3) into ok_flag;
  return next ok(r.code = '00000' and coalesce(ok_flag, false), t || ': il tombstone vince');

  -- 13: last-writer-wins
  execute format('insert into public.%I (id, user_id, %s, updated_at) values (%L, %L, %s, now() - interval ''1 day'')',
    t, cols, id_a4, a, vals);
  select * into r from pg_temp.run_as('authenticated', a,
    format('update public.%I set origin_device_id = gen_random_uuid(), updated_at = now() - interval ''2 days'' where id = %L', t, id_a4));
  execute format('select origin_device_id is null and updated_at < now() - interval ''23 hours'' and server_updated_at = now() from public.%I where id = %L', t, id_a4) into ok_flag;
  return next ok(r.code = '00000' and coalesce(ok_flag, false), t || ': scrittura più vecchia ignorata, server_updated_at aggiornato');

  -- 14: user_id di default
  select * into r from pg_temp.run_as('authenticated', a,
    format('insert into public.%I (id, %s) values (gen_random_uuid(), %s)', t, cols, vals));
  return next is(r.code, '00000', t || ': insert senza user_id accettato (default auth.uid())');
end;
$$;

-- Fixture: colonne obbligatorie specifiche di ogni tabella (31 tabelle). Le tabelle con un indice
-- unico "una riga viva per utente/giorno/muscolo" ricevono valori distinti a ogni insert da
-- fixture_seq (A inserisce fino a 5 righe per tabella).
create temp sequence fixture_seq;
grant usage on sequence fixture_seq to public;

create temp table fixture (t text primary key, cols text not null, vals text not null);
insert into fixture values
  ('user_profile',              'birth_year, height_cm, experience, activity_level', '1990, 180, ''beginner'', ''moderate'''),
  ('goal',                      'type, started_at', '''fat_loss'', now()'),
  ('app_settings',              'macro_mode', '''auto'''),
  ('training_preferences',      'days_per_week, session_minutes', '3, 60'),
  ('exercise_preference',       'exercise_key, kind', '''bench_press'', ''favorite'''),
  ('limitation',                'body_area, severity', '''knee'', ''mild'''),
  ('weight_entry',              'measured_at, day_key, tz, weight_kg, source', 'now(), current_date, ''Europe/Rome'', 80, ''manual'''),
  ('body_measurement',          'type, value, measured_at, day_key, tz, source', '''waist'', 85, now(), current_date, ''Europe/Rome'', ''manual'''),
  ('subjective_check',          'day_key', 'current_date - nextval(''fixture_seq'')::int'),
  ('custom_exercise',           'name, load_type', '''Panca custom'', ''external'''),
  ('custom_exercise_muscle',    'custom_exercise_id, muscle, role, contribution', 'gen_random_uuid(), ''chest'', ''primary'', 1'),
  ('recovery_calibration',      'muscle, user_tau_multiplier', '(array[''chest'',''lats'',''upper_back'',''front_delts'',''side_delts'',''rear_delts'',''biceps'',''triceps'',''forearms'',''abs'',''obliques'',''lower_back'',''glutes'',''quads'',''hamstrings'',''adductors'',''calves''])[1 + nextval(''fixture_seq'')::int % 17], 1'),
  ('training_program',          'split, status, engine_version, started_at', '''upper_lower'', ''active'', 1, now()'),
  ('workout_template',          'name', '''Upper A'''),
  ('workout_template_exercise', 'template_id, exercise_key, position, sets, rep_min, rep_max', 'gen_random_uuid(), ''bench_press'', 0, 3, 6, 10'),
  ('workout_session',           'started_at, status, day_key, tz', 'now(), ''completed'', current_date, ''Europe/Rome'''),
  ('workout_exercise',          'session_id, exercise_key, position', 'gen_random_uuid(), ''bench_press'', 0'),
  ('workout_set',               'workout_exercise_id, set_index, set_type, weight_kg, reps', 'gen_random_uuid(), 0, ''working'', 80, 8'),
  ('pain_report',               'day_key, body_area, level', 'current_date, ''knee'', ''mild'''),
  ('custom_food',               'name, energy_kcal, protein_g, carbs_g, fat_g', '''Yogurt di casa'', 60, 4, 5, 2'),
  ('custom_food_serving',       'custom_food_id, label, grams', 'gen_random_uuid(), ''vasetto'', 125'),
  ('recipe',                    'name', '''Pasta al pomodoro'''),
  ('recipe_ingredient',         'recipe_id, food_source, food_source_id, food_name, grams, energy_kcal_100g, protein_g_100g, carbs_g_100g, fat_g_100g',
                                'gen_random_uuid(), ''catalog'', ''pasta_dry'', ''Pasta'', 80, 356, 12, 72, 1.5'),
  ('saved_meal',                'name', '''Colazione'''),
  ('saved_meal_item',           'saved_meal_id, food_source, food_source_id, food_name, grams, energy_kcal_100g, protein_g_100g, carbs_g_100g, fat_g_100g',
                                'gen_random_uuid(), ''catalog'', ''oats'', ''Avena'', 50, 380, 13, 60, 7'),
  ('food_log_entry',            'day_key, tz, meal_slot, logged_at, food_source, energy_kcal, protein_g, carbs_g, fat_g',
                                'current_date, ''Europe/Rome'', ''snack'', now(), ''quick_add'', 200, 10, 20, 8'),
  ('nutrition_day',             'day_key', 'current_date - nextval(''fixture_seq'')::int'),
  ('nutrition_target',          'effective_from, mode, kcal_training, kcal_rest, weekly_avg_kcal, origin, engine_version',
                                'current_date, ''auto'', 2600, 2200, 2371, ''onboarding'', 1'),
  ('macro_target',              'nutrition_target_id, day_type, protein_g, carbs_g, fat_g', 'gen_random_uuid(), ''training'', 160, 300, 70'),
  ('weekly_check_in',           'week_start, engine_version', 'current_date - nextval(''fixture_seq'')::int, 1'),
  ('ai_recommendation',         'kind, status', '''daily_tip'', ''proposed''');

-- La fixture copre tutte e sole le tabelle "fatto" (con user_id e trigger di sync).
select set_eq(
  $$ select t from fixture $$,
  $$ select event_object_table::text from information_schema.triggers
     where trigger_schema = 'public' and trigger_name like '%\_sync\_columns' and event_manipulation = 'INSERT' $$,
  'la fixture copre tutte le tabelle sincronizzate'
);

-- Le tabelle con indice unico "una riga viva per utente" non possono avere più righe di A:
-- per loro i casi che inseriscono altre righe di A partono dopo aver archiviato la precedente.
-- Per semplicità il test le esegue comunque: l'indice è parziale su deleted_at, quindi prima di
-- ogni insert aggiuntivo la riga precedente viene marcata come cancellata da un trigger di test.
create function pg_temp.tombstone_previous() returns trigger language plpgsql as $$
begin
  execute format('update public.%I set deleted_at = now(), updated_at = now() + interval ''1 second'' where user_id = %L and deleted_at is null',
    tg_table_name, new.user_id);
  return new;
end;
$$;
create trigger test_tombstone_previous before insert on public.user_profile
  for each row execute function pg_temp.tombstone_previous();
create trigger test_tombstone_previous before insert on public.app_settings
  for each row execute function pg_temp.tombstone_previous();
create trigger test_tombstone_previous before insert on public.training_preferences
  for each row execute function pg_temp.tombstone_previous();

select pg_temp.check_fact_table(t, cols, vals) from fixture order by t;

select * from finish();
rollback;
