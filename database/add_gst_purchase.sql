-- ============================================================================
-- GST purchase report: whether a recorded supplier bill belongs in the GST
-- purchase report.
--
-- Set in Bulk Add with the "GST REPORT" switch. A bill entered with it off is
-- still kept as a record and still syncs; only the GST purchase export leaves
-- it out. Every bill recorded so far was in the report, so the default is true.
--
-- (The same switch also marks the products themselves. That flag is local to
-- each till, beside the product's purchase date, and needs nothing here.)
--
-- RUN THIS BEFORE INSTALLING THE UPDATE THAT ADDS THE SWITCH. The app sends
-- this column with every purchase it uploads, and Supabase rejects an upload
-- that names a column the table does not have.
--
-- Run this once in the Supabase SQL Editor. Safe to re-run.
-- ============================================================================

alter table purchases
  add column if not exists gst_report boolean not null default true;

-- ── ROLLBACK ─────────────────────────────────────────────────────────────────
-- alter table purchases drop column if exists gst_report;
