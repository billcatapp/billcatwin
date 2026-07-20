-- Run once in the Supabase SQL Editor (Project -> SQL Editor -> New query).
-- Adds the settings columns that were previously local-only, so a user who
-- reinstalls or signs in on another machine keeps their WhatsApp integration
-- and auto-print preference instead of silently reconfiguring them.
--
-- These rows are already protected by the existing per-user RLS policy on
-- user_settings, so a user can only ever read/write their own credentials.

alter table user_settings
  add column if not exists wa_access_token   text,
  add column if not exists wa_phone_number_id text,
  add column if not exists auto_print        text;
