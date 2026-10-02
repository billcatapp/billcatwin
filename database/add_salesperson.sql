-- ============================================================================
-- Salesperson on each bill: who rang it up.
--
-- Blank on every existing bill. The receipt simply omits the line until a
-- salesperson is chosen, so nothing already printed or filed changes.
--
-- The app reads a missing column as empty, so it keeps working against a
-- project where this has not been run yet — the value just will not survive
-- a cloud round trip until it has.
--
-- Run this once in the Supabase SQL Editor. Safe to re-run.
-- ============================================================================

alter table transactions
  add column if not exists salesperson text not null default '';

-- ── ROLLBACK ─────────────────────────────────────────────────────────────────
-- alter table transactions drop column if exists salesperson;
