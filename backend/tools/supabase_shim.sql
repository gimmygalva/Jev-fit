-- Emulazione minima di Supabase su un Postgres "nudo", SOLO per eseguire migrazioni e test pgTAP
-- dove la CLI di Supabase non è disponibile (sviluppo senza Docker).
-- La CI esegue anche gli stessi test su Supabase vero (`supabase test db`): in caso di differenze
-- vale quello. Riproduce solo ciò che le migrazioni usano:
--   - ruoli anon, authenticated, service_role (NOLOGIN, come su Supabase);
--   - schema auth con auth.users (colonne minime) e auth.uid() letta dai claim JWT;
--   - schema extensions con pgcrypto e pgtap;
--   - default privileges di Supabase sullo schema public (grant a anon/authenticated alla
--     creazione di ogni tabella): servono a verificare che le migrazioni li revochino davvero.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end;
$$;

grant anon, authenticated, service_role to current_user;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pgtap with schema extensions;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

create table if not exists auth.users (
  id    uuid primary key,
  aud   varchar(255),
  role  varchar(255),
  email varchar(255)
);

-- Come su Supabase: il "sub" del JWT dalla GUC request.jwt.claims (o dalla legacy request.jwt.claim.sub).
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;
grant execute on function auth.uid() to anon, authenticated, service_role;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema extensions to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

-- Su Supabase search_path include extensions: le funzioni pgTAP si chiamano senza prefisso.
do $$
begin
  execute format('alter database %I set search_path = "$user", public, extensions', current_database());
end;
$$;
