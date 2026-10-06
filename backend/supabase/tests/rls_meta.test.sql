-- Meta-test RLS sull'intero schema public (SECURITY §6.4). Protegge anche le tabelle future:
-- una migrazione che dimentica RLS, grant o policy fa fallire questo file.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

select is_empty(
  $$ select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity $$,
  'nessuna tabella in public senza RLS'
);

select is_empty(
  $$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'private') and p.prosecdef $$,
  'nessuna funzione security definer in public o private (SEC-DB-06)'
);

select is_empty(
  $$ select t.table_name from information_schema.columns t
     join pg_class c on c.relname = t.table_name
     join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
     where t.table_schema = 'public' and t.column_name = 'user_id' and c.relkind = 'r'
       and (select count(distinct p.cmd) from pg_policies p
            where p.schemaname = 'public' and p.tablename = t.table_name
              and p.cmd in ('SELECT', 'INSERT', 'UPDATE')) < 3 $$,
  'ogni tabella con user_id ha policy per select, insert e update'
);

select is_empty(
  $$ select tablename || '.' || policyname from pg_policies
     where schemaname = 'public'
       and (coalesce(qual, '') ~* '^\s*\(?\s*true\s*\)?\s*$' or coalesce(with_check, '') ~* '^\s*\(?\s*true\s*\)?\s*$') $$,
  'nessuna policy con espressione true'
);

select is_empty(
  $$ select tablename || '.' || policyname from pg_policies
     where schemaname = 'public' and cmd = 'ALL' $$,
  'nessuna policy FOR ALL (SEC-DB-02)'
);

select is_empty(
  $$ select tablename || '.' || policyname from pg_policies
     where schemaname = 'public' and not ('authenticated' = any (roles)) $$,
  'tutte le policy sono to authenticated'
);

select is_empty(
  $$ select table_name || ':' || privilege_type from information_schema.role_table_grants
     where table_schema = 'public' and grantee = 'anon' $$,
  'anon non ha privilegi su nessuna tabella di public'
);

select is_empty(
  $$ select table_name from information_schema.role_table_grants
     where table_schema = 'public' and grantee = 'authenticated' and privilege_type in ('DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER') $$,
  'il client non ha DELETE, TRUNCATE, REFERENCES o TRIGGER (cancellazioni solo come tombstone)'
);

select is_empty(
  $$ select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'v'
       and not coalesce(c.reloptions @> array['security_invoker=true'], false)
     union all
     select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'm' $$,
  'nessuna vista senza security_invoker e nessuna vista materializzata in public (SEC-DB-07)'
);

select * from finish();
rollback;
