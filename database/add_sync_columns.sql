-- Run this ONCE in the Supabase SQL Editor
-- (Project -> SQL Editor -> New query -> paste -> Run).
--
-- Why: two fields were stored locally but never carried by the cloud, so
-- they could not sync between devices:
--   * customers.address — collected by the Add Customer dialog but silently
--     dropped (lost forever on reinstall / other devices).
--   * products.barcode_no — each device generated its OWN barcode sequence,
--     so the same number could point to different products on different
--     machines and printed labels only scanned correctly on the machine
--     that printed them.
-- Safe to run more than once.

alter table customers add column if not exists address text not null default '';
alter table products  add column if not exists barcode_no text not null default '';
