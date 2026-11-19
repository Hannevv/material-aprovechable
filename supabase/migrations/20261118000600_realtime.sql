-- Solo solicitudes: relaciones/materiales se recuperan mediante SELECT autorizado.
do $$ begin
 if not exists (select 1 from pg_publication where pubname='supabase_realtime') then
  create publication supabase_realtime;
 end if;
 if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime'
                 and schemaname='public' and tablename='solicitudes') then
  alter publication supabase_realtime add table public.solicitudes;
 end if;
end $$;
-- No se cambian RLS, grants del cliente ni visibilidad de estados finales.
