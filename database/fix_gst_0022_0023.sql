-- One-off correction, 19 Nov 2026: two October bills saved their GST under
-- the old rule (GST on the amount BEFORE the discount). The current rule
-- takes the plain rate percent of what the customer actually paid, after
-- the discount. Totals paid are unchanged; only the GST and the 5% rate on
-- the taxed line are corrected.
--
--   INV/26-27/0022  paid 9,900 (test 5 10,000 + test 0 1,000, 10% off)
--                   GST 500.00 -> 450.00  (10,000 x 0.9 x 5%)
--   INV/26-27/0023  paid 900 (stripes shirt 1,100, 200 off)
--                   GST  55.00 ->  45.00  (900 x 5%)
--
-- Run once in the Supabase SQL editor. Each update matches the bill's id,
-- the shop's user id, the line it changes and the old GST, so running it
-- twice changes nothing. BillCat picks the new values up on its next sync.

update transactions
set tax_amount = 450,
    items = jsonb_set(items, '{1,taxPercent}', '5'::jsonb)
where id = '3393de68-40e1-492e-894d-07beb41e644e'
  and user_id = '2c965dc3-8992-46a1-ae71-6faf43004d78'
  and invoice_number = 'INV/26-27/0022'
  and items -> 1 ->> 'productName' = 'test 5'
  and tax_amount = 500;

update transactions
set tax_amount = 45,
    items = jsonb_set(items, '{0,taxPercent}', '5'::jsonb)
where id = '3a7dac5f-7105-46b9-aebf-318898557dbb'
  and user_id = '2c965dc3-8992-46a1-ae71-6faf43004d78'
  and invoice_number = 'INV/26-27/0023'
  and items -> 0 ->> 'productName' = 'stripes shirt'
  and tax_amount = 55;

-- Check: both rows should now show 450 and 45, rate 5 on the taxed line.
select invoice_number, total, tax_amount,
       items -> 0 ->> 'taxPercent' as line1_rate,
       items -> 1 ->> 'taxPercent' as line2_rate
from transactions
where id in ('3393de68-40e1-492e-894d-07beb41e644e',
             '3a7dac5f-7105-46b9-aebf-318898557dbb');
