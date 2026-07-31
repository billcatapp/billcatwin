-- Run this ONCE in the Supabase SQL Editor
-- (Project -> SQL Editor -> New query -> paste -> Run).
--
-- Why: the app now syncs live between devices over Supabase Realtime.
-- Postgres only broadcasts change events for tables that are part of the
-- `supabase_realtime` publication, so each synced table must be added once.
-- Safe to run more than once (already-added tables are skipped).

do $$
declare
  t text;
begin
  foreach t in array array[
    'transactions',
    'products',
    'product_variants',
    'customers',
    'user_categories',
    'user_settings'
  ] loop
    begin
      execute format('alter publication supabase_realtime add table %I', t);
    exception
      when duplicate_object then null;  -- already in the publication
      when undefined_table then null;   -- table doesn't exist in this project
    end;
  end loop;
end $$;
