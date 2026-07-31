-- Run this ONCE in the Supabase SQL Editor
-- (Project -> SQL Editor -> New query -> paste -> Run).
--
-- Why: the `transactions` table has row-level security enabled but no DELETE
-- policy, so deletes silently remove 0 rows and the records get re-pulled on
-- every sync ("deleted sales come back"). This grants each user permission to
-- delete their own transactions, matching the existing per-user pattern used
-- by products / product_variants.
--
-- Safe to run more than once (drops the policy first if it already exists).

drop policy if exists "Users can delete their own transactions" on transactions;

create policy "Users can delete their own transactions"
  on transactions
  for delete
  using (auth.uid() = user_id);
