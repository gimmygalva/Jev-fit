-- Test RLS di user_consent (SECURITY §6.6): il consenso si concede e si revoca, non si modifica
-- né si "ripristina"; ognuno vede solo i propri consensi; anon non vede nulla.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'a@test.invalid'),
  ('00000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'b@test.invalid');
insert into public.user_consent (id, user_id, kind, policy_version) values
  ('20000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', 'cloud_sync', 'test'),
  ('20000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', 'cloud_sync', 'test');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);

select results_eq($$ select count(*) from public.user_consent $$, $$ values (1::bigint) $$,
  'A vede solo il proprio consenso');
select ok((select private.has_active_consent('cloud_sync')), 'A ha il consenso cloud_sync attivo');
select ok(not (select private.has_active_consent('ai_online')), 'A non ha il consenso ai_online');

select lives_ok($$ insert into public.user_consent (kind, policy_version, app_version) values ('ai_online', 'v1', '1.0') $$,
  'A concede il consenso ai_online (user_id dal JWT)');
select throws_ok($$ insert into public.user_consent (user_id, kind, policy_version)
                    values ('00000000-0000-0000-0000-00000000000b', 'ai_online', 'v1') $$,
  '42501', null, 'A non può concedere un consenso per B');
select throws_ok($$ insert into public.user_consent (kind, policy_version, revoked_at) values ('ai_online', 'v1', now()) $$,
  '42501', null, 'un consenso non nasce già revocato');
select throws_ok($$ update public.user_consent set kind = 'ai_online' where id = '20000000-0000-0000-0000-00000000000a' $$,
  '42501', null, 'il tipo di consenso non si modifica (grant solo su revoked_at)');

select lives_ok($$ update public.user_consent set revoked_at = now() where id = '20000000-0000-0000-0000-00000000000a' $$,
  'A revoca il proprio consenso');
select ok(not (select private.has_active_consent('cloud_sync')), 'dopo la revoca il consenso non è attivo');
-- Una riga revocata non è più aggiornabile (using: revoked_at is null): l'update non tocca nulla.
select results_eq($$ with u as (update public.user_consent set revoked_at = null
                                where id = '20000000-0000-0000-0000-00000000000a' returning 1)
                     select count(*) from u $$,
  $$ values (0::bigint) $$, 'un consenso revocato non si ripristina: serve un nuovo consenso');

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok($$ select * from public.user_consent $$, '42501', null, 'anon: permesso negato');

select * from finish();
rollback;
