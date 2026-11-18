-- ONLY for the disposable lightweight test runtime, never a project migration.
-- GoTrue itself creates/migrates auth.users. No mocked Auth table.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role authenticator login noinherit password 'local-test-only';
grant anon, authenticated, service_role to authenticator;
create role supabase_auth_admin login createrole password 'local-test-only';
create schema auth authorization supabase_auth_admin;
alter role supabase_auth_admin set search_path = auth;
grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;
