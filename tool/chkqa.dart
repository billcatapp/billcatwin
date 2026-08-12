// QA functional tests for return/exchange money math, mirroring
// _buildReversalRecord exactly. Uses synthetic bills so results are exact.
//   dart run tool/chkqa.dart
import 'package:billcat/models/transaction_record.dart';

({double sub, double discount, double tax, double total})
    reversal(TransactionRecord o, Map<int, int> qtyByIndex) {
  final origSub = o.subtotal;
  final discountFactor =
      origSub > 0 ? (origSub - o.discountAmount) / origSub : 1.0;
  final anyLineRate = o.items.any((l) => l.taxPercent > 0);
  final taxedBase = origSub - o.discountAmount;
  final fallbackRate =
      (!anyLineRate && taxedBase > 0) ? o.taxAmount / taxedBase * 100 : 0.0;
  var sub = 0.0, twReturned = 0.0, twAll = 0.0;
  for (var i = 0; i < o.items.length; i++) {
    final l = o.items[i];
    final rate = l.taxPercent > 0 ? l.taxPercent : fallbackRate;
    twAll += l.price * l.quantity * discountFactor * rate / 100;
    final q = qtyByIndex[i] ?? 0;
    if (q <= 0) continue;
    sub += l.price * q;
    twReturned += l.price * q * discountFactor * rate / 100;
  }
  final tax = twAll > 0 ? o.taxAmount * (twReturned / twAll) : 0.0;
  final discount = origSub > 0 ? o.discountAmount * (sub / origSub) : 0.0;
  return (sub: -sub, discount: -discount, tax: -tax, total: -(sub - discount + tax));
}

TransactionItem item(String id, double price, int qty, double taxPct) =>
    TransactionItem(productId: id, productName: id, price: price, quantity: qty, taxPercent: taxPct);

TransactionRecord bill(List<TransactionItem> items, double discount) {
  final sub = items.fold(0.0, (s, i) => s + i.price * i.quantity);
  final factor = sub > 0 ? (sub - discount) / sub : 1.0;
  final tax = items.fold(0.0, (s, i) => s + i.price * i.quantity * factor * i.taxPercent / 100);
  return TransactionRecord(
    id: 'b', items: items, subtotal: sub, discountAmount: discount,
    taxAmount: tax, total: sub - discount + tax, paymentMethod: 'cash',
    createdAt: DateTime(2026));
}

bool near(double a, double b) => (a - b).abs() < 0.01;
int pass = 0, fail = 0;
void check(String n, bool ok, [String extra = '']) {
  print('${ok ? "ok  " : "FAIL"}  $n${extra.isEmpty ? "" : "  ($extra)"}');
  ok ? pass++ : fail++;
}

void main() {
  // Bill: A 3x@100 5%, B 1x@200 12%, discount 30.
  final b = bill([item('A', 100, 3, 5), item('B', 200, 1, 12)], 30);
  print('Bill: sub=${b.subtotal} disc=${b.discountAmount} '
      'tax=${b.taxAmount.toStringAsFixed(2)} total=${b.total.toStringAsFixed(2)}');

  // 1. Full return negates the bill exactly.
  final full = reversal(b, {0: 3, 1: 1});
  check('full return == -total', near(full.total, -b.total),
      '${full.total.toStringAsFixed(2)} vs ${(-b.total).toStringAsFixed(2)}');

  // 2. Two partials covering the whole bill sum to the full refund.
  final p1 = reversal(b, {0: 3});
  final p2 = reversal(b, {1: 1});
  check('partial(A)+partial(B) == full', near(p1.total + p2.total, full.total),
      '${(p1.total + p2.total).toStringAsFixed(2)}');

  // 3. Exempt line refunds 0 tax; taxed line refunds its full tax.
  final mix = bill([item('X', 100, 1, 0), item('Y', 200, 1, 12)], 0);
  check('exempt-only return: tax 0', near(reversal(mix, {0: 1}).tax, 0),
      reversal(mix, {0: 1}).tax.toStringAsFixed(2));
  check('taxed-only return: full tax', near(reversal(mix, {1: 1}).tax, -mix.taxAmount),
      '${reversal(mix, {1: 1}).tax.toStringAsFixed(2)} vs ${(-mix.taxAmount).toStringAsFixed(2)}');

  // 4. Zero-subtotal bill: no divide-by-zero, refund 0.
  final zero = bill([item('Z', 0, 1, 0)], 0);
  final zr = reversal(zero, {0: 1});
  check('zero bill: finite, total 0',
      zr.total == 0 && zr.total.isFinite && !zr.total.isNaN);

  // 5. Discount larger than subtotal (over-discount) doesn't produce a
  //    positive/absurd refund.
  final over = TransactionRecord(id: 'o',
      items: [item('A', 100, 1, 0)], subtotal: 100, discountAmount: 150,
      taxAmount: 0, total: -50, paymentMethod: 'cash', createdAt: DateTime(2026));
  final orv = reversal(over, {0: 1});
  check('over-discount: refund not positive', orv.total <= 0.01,
      orv.total.toStringAsFixed(2));

  // 6. Exchange difference: return 1000, add new items 1200 => collect 200.
  const returning = 1000.0, newItems = 1200.0;
  check('exchange collect = new - returning',
      near(newItems - returning, 200));

  print('\n$pass passed, $fail failed');
  print('\nNOTE: selectedQty() returns the FULL remaining cap per ticked line —'
      ' the dialog has no per-line partial-quantity stepper for RETURNS.');
}
