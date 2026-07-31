-- Run this ONCE in the Supabase SQL Editor
-- (Project -> SQL Editor -> New query -> paste -> Run).
--
-- Why: with row-level security enabled, a table with no DELETE policy
-- silently deletes 0 rows — the app then re-pulls the "deleted" records and
-- they come back on every device. This grants each user permission to delete
-- their OWN rows in every synced table. Safe to run more than once, and safe
-- on tables that already have a broader "for all" policy (policies are OR'd).

do $$
declare
  t text;
begin
  foreach t in array array[
    'transactions',
    'products',
    'product_variants',
    'customers',
    'user_categories'
  ] loop
    begin
      execute format(
        'drop policy if exists "Users can delete their own rows" on %I', t);
      execute format(
        'create policy "Users can delete their own rows" on %I '
        'for delete using (auth.uid() = user_id)', t);
    exception
      when undefined_table then null;  -- table doesn't exist in this project
    end;
  end loop;
end $$;
