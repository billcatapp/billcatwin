-- Run this once in the Supabase SQL Editor (Project -> SQL Editor -> New query)
-- to add support for product variants (separate price/stock/SKU per variant).
-- Mirrors the existing `products` table's structure and RLS pattern.

create table if not exists product_variants (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  label text not null,
  price numeric not null default 0,
  buying_price numeric not null default 0,
  stock integer not null default 0,
  sku text not null default '',
  barcode_no text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists product_variants_product_id_idx
  on product_variants (product_id);

create index if not exists product_variants_user_id_idx
  on product_variants (user_id);

alter table product_variants enable row level security;

create policy "Users manage their own product variants"
  on product_variants for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
