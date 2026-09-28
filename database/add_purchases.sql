-- ============================================================================
-- Purchases: supplier bills, so a GST purchase register can be reported with
-- the supplier's own invoice number and per-line HSN.
--
-- WHY a table of its own: BillCat kept purchase data as three columns on each
-- product (dealer_name, purchase_date, buying_price) holding only the LATEST
-- purchase. A register needs every bill, with its own invoice number and date,
-- so buying from one supplier twice keeps both rows instead of overwriting.
--
-- Shape mirrors `transactions`: one row per invoice, lines as JSON in `items`.
-- dealer_name / dealer_gstin are SNAPSHOTS taken when the bill was entered,
-- not live lookups — correcting a supplier's GSTIN today must not rewrite
-- records already filed under the old one.
--
-- Run this whole file once in the Supabase SQL Editor. Safe to re-run.
-- ============================================================================

create table if not exists purchases (
  id              text primary key,
  user_id         uuid not null,
  dealer_id       text        not null default '',
  dealer_name     text        not null default '',
  dealer_gstin    text        not null default '',
  invoice_no      text        not null default '',
  invoice_date    text        not null default '',
  place_of_supply text        not null default '',
  reverse_charge  boolean     not null default false,
  notes           text        not null default '',
  items           jsonb       not null default '[]'::jsonb,
  created_at      timestamptz not null default now()
);

-- The register is always read for a period, and always for one shop.
create index if not exists purchases_user_invoice_date_idx
  on purchases (user_id, invoice_date);

-- Row-Level Security: same owner-only rule as every other user-data table
-- (see enable_rls_owner_policies.sql).
alter table purchases enable row level security;
drop policy if exists "owner_all_purchases" on purchases;
create policy "owner_all_purchases" on purchases
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Realtime, so a bill entered on one till appears on the other
-- (see enable_realtime.sql).
do $$
begin
  begin
    execute 'alter publication supabase_realtime add table purchases';
  exception
    when duplicate_object then null;  -- already in the publication
    when undefined_table then null;   -- table doesn't exist in this project
  end;
end $$;

-- ── OPTIONAL: instant cross-device DELETE ────────────────────────────────────
-- With RLS on, a realtime DELETE only carries the primary key by default, so
-- the policy cannot confirm ownership. Deletes still arrive via the periodic
-- pull. Uncomment to make them instant, at a small extra write cost:
-- alter table purchases replica identity full;

-- ── ROLLBACK ─────────────────────────────────────────────────────────────────
-- drop policy if exists "owner_all_purchases" on purchases;
-- drop table if exists purchases;
