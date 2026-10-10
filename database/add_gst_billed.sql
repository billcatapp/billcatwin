-- ============================================================================
-- GST billed: whether a bill belongs in the GST return.
--
-- Set at Confirm Payment. A bill switched off is charged, printed and counted
-- in sales, profit and stock exactly as any other; only the GST page and its
-- exports leave it out. A return of such a bill follows it.
--
-- Every existing bill was a GST bill, so the default is true.
--
-- RUN THIS BEFORE INSTALLING THE UPDATE THAT ADDS THE SWITCH. The app sends
-- this column with every bill it uploads, and Supabase rejects an upload that
-- names a column the table does not have — bills would stop syncing until
-- this has been run.
--
-- Run this once in the Supabase SQL Editor. Safe to re-run.
-- ============================================================================

alter table transactions
  add column if not exists gst_billed boolean not null default true;

-- ── ROLLBACK ─────────────────────────────────────────────────────────────────
-- alter table transactions drop column if exists gst_billed;
