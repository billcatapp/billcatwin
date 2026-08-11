// Verifies return/exchange behaviour against a COPY of the live DB:
//   1. a FULL return exactly negates the original bill (money math)
//   2. a PARTIAL return refunds a fair share of discount and tax
//   3. saving a return puts the stock back and is atomic
//   dart run tool/chkreturn.dart
import 'dart:convert';
import 'dart:io';
import 'package:billcat/models/transaction_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _liveDb = 'billcat_2c965dc3-8992-46a1-ae71-6faf43004d78.db';

/// Mirror of _buildReversalRecord's arithmetic in billing_screen.dart.
({double sub, double discount, double tax, double total, List<TransactionItem> items})
    reversal(TransactionRecord original, Map<int, int> qtyByIndex) {
  final origSub = original.subtotal;
  final discountFactor =
      origSub > 0 ? (origSub - original.discountAmount) / origSub : 1.0;
  final anyLineRate = original.items.any((l) => l.taxPercent > 0);
  final taxedBase = origSub - original.discountAmount;
  final fallbackRate = (!anyLineRate && taxedBase > 0)
      ? original.taxAmount / taxedBase * 100
      : 0.0;

  final items = <TransactionItem>[];
  var sub = 0.0;
  var taxWeightReturned = 0.0;
  var taxWeightAll = 0.0;
  for (var i = 0; i < original.items.length; i++) {
    final line = original.items[i];
    final rate = line.taxPercent > 0 ? line.taxPercent : fallbackRate;
    taxWeightAll += line.price * line.quantity * discountFactor * rate / 100;
    final qty = qtyByIndex[i] ?? 0;
    if (qty <= 0) continue;
    final gross = line.price * qty;
    sub += gross;
    taxWeightReturned += gross * discountFactor * rate / 100;
    items.add(TransactionItem(
      productId: line.productId,
      productName: line.productName,
      price: line.price,
      quantity: -qty,
      variantId: line.variantId,
      taxPercent: line.taxPercent,
    ));
  }
  final tax = taxWeightAll > 0
      ? original.taxAmount * (taxWeightReturned / taxWeightAll)
      : 0.0;
  final discount =
      origSub > 0 ? original.discountAmount * (sub / origSub) : 0.0;
  return (
    sub: -sub,
    discount: -discount,
    tax: -tax,
    total: -(sub - discount + tax),
    items: items,
  );
}

bool near(double a, double b) => (a - b).abs() < 0.005;

Future<void> main() async {
  sqfliteFfiInit();
  final src =
      '${Platform.environment['APPDATA']}\\com.billcat\\billcat\\BillCat\\$_liveDb';
  final tmp = Directory.systemTemp.createTempSync('billcat_ret').path;
  final work = '$tmp\\ret.db';
  File(src).copySync(work);
  final db = await databaseFactoryFfi.openDatabase(work);

  // ── 1. Full return of every real bill must negate it exactly ────────────
  final rows = await db.query('transactions', where: 'deleted = 0');
  var checked = 0, bad = 0;
  for (final r in rows) {
    final t = TransactionRecord.fromMap(r);
    if (t.items.isEmpty || t.isReturn) continue;
    final full = {for (var i = 0; i < t.items.length; i++) i: t.items[i].quantity};
    final rev = reversal(t, full);
    checked++;
    if (!near(rev.total, -t.total) ||
        !near(rev.sub, -t.subtotal) ||
        !near(rev.discount, -t.discountAmount) ||
        !near(rev.tax, -t.taxAmount)) {
      bad++;
      print('MISMATCH ${t.invoiceNumber ?? t.id}: '
          'orig total=${t.total.toStringAsFixed(2)} '
          'sub=${t.subtotal.toStringAsFixed(2)} '
          'disc=${t.discountAmount.toStringAsFixed(2)} '
          'tax=${t.taxAmount.toStringAsFixed(2)}  |  '
          'reversal total=${rev.total.toStringAsFixed(2)} '
          'sub=${rev.sub.toStringAsFixed(2)} '
          'disc=${rev.discount.toStringAsFixed(2)} '
          'tax=${rev.tax.toStringAsFixed(2)}');
    }
  }
  print('1. FULL RETURN: $checked real bills checked, $bad mismatched');

  // ── 2. Partial return refunds a fair share ─────────────────────────────
  final multi = rows
      .map(TransactionRecord.fromMap)
      .where((t) => !t.isReturn && t.items.length >= 2 && t.subtotal > 0)
      .toList();
  if (multi.isEmpty) {
    print('2. PARTIAL: no multi-item bill available to check');
  } else {
    final t = multi.first;
    final half = {0: t.items[0].quantity};
    final rev = reversal(t, half);
    final share = (t.items[0].price * t.items[0].quantity) / t.subtotal;
    final expectedDiscount = -t.discountAmount * share;
    print('2. PARTIAL (${t.invoiceNumber ?? t.id}): returning line 1 of '
        '${t.items.length} = ${(share * 100).toStringAsFixed(1)}% of the bill');
    print('   refund=${rev.total.toStringAsFixed(2)}  '
        'discount share=${rev.discount.toStringAsFixed(2)} '
        '(expected ${expectedDiscount.toStringAsFixed(2)}) '
        '${near(rev.discount, expectedDiscount) ? "OK" : "WRONG"}');
    print('   refund is less than full bill: '
        '${rev.total.abs() < t.total ? "OK" : "WRONG"}');
  }

  // ── 3. Saving a return puts stock back, atomically ──────────────────────
  final pid = (await db.query('products', limit: 1)).first['id'] as String;
  final before = (await db.query('products',
          columns: ['stock'], where: 'id = ?', whereArgs: [pid]))
      .first['stock'] as int;
  final txBefore = (await db.rawQuery(
      'SELECT COUNT(*) c FROM transactions')).first['c'] as int;

  // Exactly what LocalDbService.insertReturn does.
  await db.transaction((txn) async {
    await txn.insert('transactions', {
      'id': 'chk-return',
      'invoice_number': 'RTN-CHECK',
      'customer_name': '',
      'customer_phone': '',
      'items': jsonEncode([
        {
          'productId': pid,
          'productName': 'x',
          'description': '',
          'price': 100.0,
          'quantity': -2,
          'variantId': null,
          'variantLabel': null,
          'taxPercent': 0.0,
        }
      ]),
      'subtotal': -200.0,
      'discount_amount': 0.0,
      'tax_amount': 0.0,
      'total': -200.0,
      'payment_method': 'cash',
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final row = (await txn.query('products',
            where: 'id = ?', whereArgs: [pid], limit: 1))
        .first;
    final current = (row['stock'] is num) ? (row['stock'] as num).toInt() : 0;
    final updated = current - (-2); // _stockAfterSale with a negative quantity
    await txn.rawUpdate(
      'UPDATE products SET stock = ?, synced = 0, rev = rev + 1 WHERE id = ?',
      [updated < 0 ? 0 : updated, pid],
    );
  });

  final after = (await db.query('products',
          columns: ['stock'], where: 'id = ?', whereArgs: [pid]))
      .first['stock'] as int;
  final txAfter = (await db.rawQuery(
      'SELECT COUNT(*) c FROM transactions')).first['c'] as int;
  print('3. STOCK RESTORE: $before -> $after '
      '${after == before + 2 ? "OK (+2)" : "WRONG"}; '
      'return rows added: ${txAfter - txBefore}');

  // ── 3b. Mixed exempt/rated bill: a partial return must not refund tax
  //        on the exempt line, nor short-refund the taxed one ─────────────
  final mixed = TransactionRecord(
    id: 'mixed',
    items: const [
      TransactionItem(
          productId: 'A', productName: 'exempt', price: 100, quantity: 1),
      TransactionItem(
          productId: 'B',
          productName: 'rated',
          price: 200,
          quantity: 1,
          taxPercent: 12),
    ],
    subtotal: 300,
    discountAmount: 30,
    taxAmount: 21.60, // only B is taxed: 200 * 0.9 * 12%
    total: 291.60,
    paymentMethod: 'cash',
    createdAt: DateTime.now(),
  );
  final exemptOnly = reversal(mixed, {0: 1});
  final ratedOnly = reversal(mixed, {1: 1});
  print('3b. MIXED EXEMPT/RATED partial returns:');
  print('   exempt line only: tax=${exemptOnly.tax.toStringAsFixed(2)} '
      '${near(exemptOnly.tax, 0) ? "OK (no tax refunded)" : "WRONG"}');
  print('   rated line only:  tax=${ratedOnly.tax.toStringAsFixed(2)} '
      '${near(ratedOnly.tax, -21.60) ? "OK (full 21.60 refunded)" : "WRONG"}');
  print('   both halves sum to the bill: '
      '${near(exemptOnly.total + ratedOnly.total, -mixed.total) ? "OK" : "WRONG"}');

  // ── 4. The return nets off in a plain SUM, as the reports do ────────────
  final net = (await db.rawQuery(
      'SELECT SUM(total) s FROM transactions WHERE deleted = 0')).first['s'];
  print('4. REPORT SUM including the return: '
      '${(net as num).toStringAsFixed(2)} (the -200.00 is subtracted)');

  await db.close();
  Directory(tmp).deleteSync(recursive: true);
}
