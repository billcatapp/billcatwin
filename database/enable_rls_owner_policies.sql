-- ============================================================================
-- Row-Level Security: each shop can only see/change its OWN rows.
--
-- WHY: a read with the public anon key currently returns transaction rows,
-- which means anonymous read access to sales data is open. These policies
-- lock every user-data table to the signed-in owner (auth.uid() = user_id).
--
-- The app always talks to Supabase with the logged-in user's session, and it
-- already filters every query by user_id, so nothing in normal use changes —
-- this just makes the database enforce it instead of trusting the client.
--
-- Run this whole file once in the Supabase SQL Editor.
-- ============================================================================

-- One owner-only policy per table covering SELECT / INSERT / UPDATE / DELETE.
-- Idempotent: safe to re-run.

-- transactions -------------------------------------------------------------
-- transactions had an extra permissive policy (anon could read other shops'
-- bills). RLS policies are OR'd, so we must remove EVERY existing policy and
-- keep only the owner one. This DO block drops them all, then recreates it.
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'transactions'
  loop
    execute format('drop policy if exists %I on transactions', p.policyname);
  end loop;
end $$;
alter table transactions enable row level security;
create policy "owner_all_transactions" on transactions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- products -----------------------------------------------------------------
alter table products enable row level security;
drop policy if exists "owner_all_products" on products;
create policy "owner_all_products" on products
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- product_variants ---------------------------------------------------------
alter table product_variants enable row level security;
drop policy if exists "owner_all_product_variants" on product_variants;
create policy "owner_all_product_variants" on product_variants
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- customers ----------------------------------------------------------------
alter table customers enable row level security;
drop policy if exists "owner_all_customers" on customers;
create policy "owner_all_customers" on customers
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- user_categories ----------------------------------------------------------
alter table user_categories enable row level security;
drop policy if exists "owner_all_user_categories" on user_categories;
create policy "owner_all_user_categories" on user_categories
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── OPTIONAL: keep cross-device DELETE instant over realtime ──────────────
-- With RLS on, a realtime DELETE event only carries the primary key by
-- default, so the policy can't confirm ownership and the event may not reach
-- the other till. Deletes still propagate via the app's periodic pull (within
-- a few minutes). To keep them INSTANT, include the full old row in the WAL:
--   (small extra write cost; enable only if instant cross-device delete matters)
-- alter table transactions     replica identity full;
-- alter table products         replica identity full;
-- alter table product_variants replica identity full;
-- alter table customers        replica identity full;
-- alter table user_categories  replica identity full;

-- ── ROLLBACK (if anything misbehaves, turn RLS back off) ──────────────────
-- alter table transactions     disable row level security;
-- alter table products         disable row level security;
-- alter table product_variants disable row level security;
-- alter table customers        disable row level security;
-- alter table user_categories  disable row level security;
