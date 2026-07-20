-- Run once in the Supabase SQL Editor (Project -> SQL Editor -> New query).
-- Records which dealer/supplier a product's stock was last purchased from.
--
-- NOTE: the app deliberately does NOT push dealer_name to Supabase until this
-- column exists — adding it to the upsert payload before the column is created
-- would make the entire products sync fail, not just this one field. Once this
-- has run, tell the developer so the field can be added to the sync.

alter table products
  add column if not exists dealer_name text not null default '';
