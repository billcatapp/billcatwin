-- Adds the HSN/SAC code column to the cloud products table.
--
-- The app has sent `hsn_code` with every product upload since v1.10.0
-- (7 Sep 2026), but no migration ever added the column to Supabase. A
-- column the table does not have makes the WHOLE products upsert fail, not
-- just that field, so on a project without it no product edit, new product
-- or stock change from this app has reached the cloud since then: every
-- product stays "waiting to sync" on the till that made it.
--
-- Run once in the Supabase SQL editor. Safe to run again. The two columns
-- after it are the other optional ones the upload sends; they are included
-- (also "if not exists") so a project that skipped their own scripts is
-- covered too.

alter table products
  add column if not exists hsn_code text not null default '';

alter table products
  add column if not exists dealer_name text not null default '';

alter table products
  add column if not exists barcode_no text not null default '';

-- Check: all three columns should be listed.
select column_name, data_type
from information_schema.columns
where table_name = 'products'
  and column_name in ('hsn_code', 'dealer_name', 'barcode_no');
