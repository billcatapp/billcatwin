-- Run once in the Supabase SQL Editor (Project -> SQL Editor -> New query).
-- Records the date a product's stock was last purchased (ISO yyyy-MM-dd text).
--
-- NOTE: the app currently keeps purchase_date LOCAL-ONLY — it is NOT included
-- in the products upsert payload, because adding an unknown column to the
-- upsert would make the ENTIRE products sync fail (not just this one field).
-- The pull path already reads purchase_date defensively, so running this now is
-- safe and forward-compatible. Once this has run, tell the developer so
-- 'purchase_date': p.purchaseDate can be added to the push payload in
-- connectivity_service.dart and the date will sync across devices.

alter table products
  add column if not exists purchase_date text not null default '';
