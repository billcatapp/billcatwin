// Verifies the checkout hardening against the two failure modes that made
// Confirm look like a dead button. Works on a COPY of the live DB.
//   dart run tool/chkcheckout.dart
import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _liveDb =
    'billcat_2c965dc3-8992-46a1-ae71-6faf43004d78.db';

int stockAfterSale(Object? raw, int quantity) {
  final current = (raw is num) ? raw.toInt() : 0;
  final updated = current - quantity;
  return updated < 0 ? 0 : updated;
}

/// The post-fix insertTransaction, statement for statement.
Future<void> insertTransaction(
  Database database, {
  required String id,
  required String productId,
  required int quantity,
  required String customerName,
}) async {
  await database.transaction((txn) async {
    await txn.insert('transactions', {
      'id': id,
      'invoice_number': 'INV-TEST',
      'customer_name': customerName,
      'customer_phone': '9000000000',
      'items': jsonEncode([
        {
          'productId': productId,
          'productName': 'test',
          'price': 100.0,
          'quantity': quantity,
        },
      ]),
      'subtotal': 100.0,
      'discount_amount': 0.0,
      'tax_amount': 0.0,
      'total': 100.0,
      'payment_method': 'cash',
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final rows = await txn.query('products',
        where: 'id = ?', whereArgs: [productId], limit: 1);
    if (rows.isNotEmpty) {
      final updated = stockAfterSale(rows.first['stock'], quantity);
      await txn.rawUpdate(
        'UPDATE products SET stock = ?, synced = 0, rev = rev + 1 WHERE id = ?',
        [updated, productId],
      );
    }
    final existing = await txn.query('customers',
        where: 'phone = ? AND deleted = 0',
        whereArgs: ['9000000000'],
        limit: 1);
    if (existing.isEmpty) {
      await txn.insert('customers', {
        'id': 'cust-test-${DateTime.now().microsecondsSinceEpoch}',
        'name': customerName,
        'phone': '9000000000',
        'address': '',
        'created_at': DateTime.now().toIso8601String(),
        'synced': 0,
        'deleted': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  });
}

Future<int> count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
  return (rows.first['c'] as num).toInt();
}

Future<void> main() async {
  sqfliteFfiInit();
  final f = databaseFactoryFfi;
  final src = '${Platform.environment['APPDATA']}\\com.billcat\\billcat\\BillCat\\$_liveDb';
  final tmp = Directory.systemTemp.createTempSync('billcat_chk').path;

  // ── Case 1: a product with negative stock ───────────────────────────────
  var work = '$tmp\\case1.db';
  File(src).copySync(work);
  var db = await f.openDatabase(work);
  var pid = (await db.query('products', limit: 1)).first['id'] as String;
  await db.rawUpdate('UPDATE products SET stock = -3 WHERE id = ?', [pid]);
  var txBefore = await count(db, 'transactions');
  try {
    await insertTransaction(db,
        id: 'chk-neg', productId: pid, quantity: 1, customerName: 'Neg Test');
    final after = await count(db, 'transactions');
    final stock = (await db.query('products',
            columns: ['stock'], where: 'id = ?', whereArgs: [pid]))
        .first['stock'];
    print('CASE 1 negative stock: OK — sale saved '
        '(${txBefore} -> $after), stock repaired to $stock');
  } catch (e) {
    print('CASE 1 negative stock: FAIL — threw $e');
  }
  await db.close();

  // ── Case 2: the "rev" column silently missing ───────────────────────────
  work = '$tmp\\case2.db';
  File(src).copySync(work);
  db = await f.openDatabase(work);
  await db.execute('ALTER TABLE products DROP COLUMN rev');
  pid = (await db.query('products', limit: 1)).first['id'] as String;
  txBefore = await count(db, 'transactions');
  final custBefore = await count(db, 'customers');
  try {
    await insertTransaction(db,
        id: 'chk-rev', productId: pid, quantity: 1, customerName: 'Rev Test');
    print('CASE 2 missing rev: unexpected success');
  } catch (e) {
    final txAfter = await count(db, 'transactions');
    final custAfter = await count(db, 'customers');
    final ghost = txAfter - txBefore;
    print('CASE 2 missing rev: threw as expected '
        '(${e.toString().split('\n').first})');
    print('   -> ghost sales left behind: $ghost '
        '(must be 0), customers added: ${custAfter - custBefore}');
  }
  await db.close();

  // ── Case 3: the self-heal puts the column back ──────────────────────────
  db = await f.openDatabase(work);
  final present = {
    for (final r in await db.rawQuery('PRAGMA table_info(products)'))
      r['name'] as String,
  };
  print('CASE 3 pre-heal: products has rev? ${present.contains('rev')}');
  if (!present.contains('rev')) {
    await db.execute(
        'ALTER TABLE products ADD COLUMN rev INTEGER NOT NULL DEFAULT 0');
  }
  txBefore = await count(db, 'transactions');
  try {
    await insertTransaction(db,
        id: 'chk-healed', productId: pid, quantity: 1, customerName: 'Heal');
    print('CASE 3 after heal: OK — sale saved '
        '($txBefore -> ${await count(db, 'transactions')})');
  } catch (e) {
    print('CASE 3 after heal: FAIL — threw $e');
  }
  await db.close();

  Directory(tmp).deleteSync(recursive: true);
}
