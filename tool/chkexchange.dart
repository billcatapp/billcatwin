// Verifies the atomic exchange write on a COPY of the live db:
//   1. happy path: reversal + sale both commit, stock moves both ways
//   2. atomicity: if the 2nd write throws, NEITHER row nor stock change survives
//   dart run tool/chkexchange.dart
import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

int stockAfterSale(Object? raw, int quantity) {
  final current = (raw is num) ? raw.toInt() : 0;
  final updated = current - quantity;
  return updated < 0 ? 0 : updated;
}

Map<String, dynamic> row(String id, String pid, int qty, double total) => {
  'id': id,
  'invoice_number': id,
  'customer_name': '',
  'customer_phone': '',
  'items': jsonEncode([
    {'productId': pid, 'productName': 'x', 'description': '', 'price': 1000.0,
     'quantity': qty, 'variantId': null, 'variantLabel': null, 'taxPercent': 0.0}
  ]),
  'subtotal': total, 'discount_amount': 0.0, 'tax_amount': 0.0, 'total': total,
  'payment_method': 'cash', 'created_at': DateTime.now().toIso8601String(),
  'synced': 0,
};

/// Mirror of _writeTransactionRow: insert row + move stock by -qty.
Future<void> writeRow(DatabaseExecutor txn, Map<String, dynamic> r) async {
  await txn.insert('transactions', r, conflictAlgorithm: ConflictAlgorithm.replace);
  final items = jsonDecode(r['items'] as String) as List;
  for (final i in items) {
    final pid = i['productId'];
    final q = i['quantity'] as int;
    final got = await txn.query('products', where: 'id = ?', whereArgs: [pid], limit: 1);
    if (got.isNotEmpty) {
      await txn.rawUpdate(
        'UPDATE products SET stock = ?, synced = 0, rev = rev + 1 WHERE id = ?',
        [stockAfterSale(got.first['stock'], q), pid]);
    }
  }
}

Future<int> count(Database db) async =>
    (await db.rawQuery('SELECT COUNT(*) c FROM transactions')).first['c'] as int;
Future<int> stock(Database db, String pid) async =>
    (await db.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [pid]))
        .first['stock'] as int;

Future<void> main() async {
  sqfliteFfiInit();
  final src = '${Platform.environment['APPDATA']}\\com.billcat\\billcat\\BillCat\\billcat_2c965dc3-8992-46a1-ae71-6faf43004d78.db';
  final tmp = Directory.systemTemp.createTempSync('billcat_ex').path;

  // ── 1. Happy path ────────────────────────────────────────────────────────
  var work = '$tmp\\ok.db';
  File(src).copySync(work);
  var db = await databaseFactoryFfi.openDatabase(work);
  final pid = (await db.query('products', limit: 1)).first['id'] as String;
  final s0 = await stock(db, pid), c0 = await count(db);
  // reversal: +1 back (qty -1), sale: -1 out (qty +1) on same product => net 0
  await db.transaction((txn) async {
    await writeRow(txn, row('exc-rev', pid, -1, -1000));
    await writeRow(txn, row('exc-sale', pid, 1, 1000));
  });
  print('1. HAPPY: rows ${c0} -> ${await count(db)} (want +2), '
      'stock ${s0} -> ${await stock(db, pid)} (want $s0, net zero)');
  await db.close();

  // ── 2. Atomicity: second write throws => full rollback ────────────────────
  work = '$tmp\\fail.db';
  File(src).copySync(work);
  db = await databaseFactoryFfi.openDatabase(work);
  final s1 = await stock(db, pid), c1 = await count(db);
  try {
    await db.transaction((txn) async {
      await writeRow(txn, row('exc-rev2', pid, -1, -1000)); // return commits...
      throw StateError('simulated crash before the sale write');
    });
  } catch (_) {}
  print('2. ATOMIC (2nd write fails): rows ${c1} -> ${await count(db)} '
      '(want $c1, rolled back), stock ${s1} -> ${await stock(db, pid)} '
      '(want $s1, no phantom restore)');
  final ghost = (await db.query('transactions', where: 'id = ?', whereArgs: ['exc-rev2'])).length;
  print('   half-recorded return left behind: $ghost (want 0)');
  await db.close();

  Directory(tmp).deleteSync(recursive: true);
}
