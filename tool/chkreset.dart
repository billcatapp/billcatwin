// Verifies the Data-reset soft-delete on a COPY of the live DB:
//   - rows vanish from the normal (deleted = 0) queries
//   - each becomes a pending cloud deletion (deleted = 1 AND synced = 0)
//   - other tables are untouched
//   dart run tool/chkreset.dart
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const resettable = {
  'customers',
  'transactions',
  'products',
  'product_variants',
  'categories',
};

Future<int> live(Database db, String t) async =>
    (await db.rawQuery('SELECT COUNT(*) c FROM $t WHERE deleted = 0'))
        .first['c'] as int;

Future<int> pending(Database db, String t) async =>
    (await db.rawQuery(
      'SELECT COUNT(*) c FROM $t WHERE deleted = 1 AND synced = 0',
    )).first['c'] as int;

Future<void> softDelete(Database db, List<String> tables) async {
  await db.transaction((txn) async {
    for (final t in tables) {
      if (!resettable.contains(t)) continue;
      await txn.rawUpdate(
        'UPDATE $t SET deleted = 1, synced = 0, rev = rev + 1 WHERE deleted = 0',
      );
    }
  });
}

Future<void> main() async {
  sqfliteFfiInit();
  final src =
      '${Platform.environment['APPDATA']}\\com.billcat\\billcat\\BillCat\\billcat_2c965dc3-8992-46a1-ae71-6faf43004d78.db';
  final tmp = Directory.systemTemp.createTempSync('billcat_reset').path;

  // ── Reset only Sales (transactions); customers/products must be untouched ──
  final work = '$tmp\\r.db';
  File(src).copySync(work);
  final db = await databaseFactoryFfi.openDatabase(work);

  final txBefore = await live(db, 'transactions');
  final custBefore = await live(db, 'customers');
  final prodBefore = await live(db, 'products');

  await softDelete(db, ['transactions']);

  print('RESET SALES:');
  print('  transactions live ${txBefore} -> ${await live(db, 'transactions')} '
      '(want 0)');
  print('  transactions pending-cloud-delete: ${await pending(db, 'transactions')} '
      '(want $txBefore)');
  print('  customers untouched: ${await live(db, 'customers')} '
      '(want $custBefore)');
  print('  products untouched: ${await live(db, 'products')} '
      '(want $prodBefore)');

  // ── Reset All ─────────────────────────────────────────────────────────────
  await softDelete(db, resettable.toList());
  print('RESET ALL:');
  for (final t in resettable) {
    print('  $t live=${await live(db, t)} pending=${await pending(db, t)}');
  }

  // Guard: an unknown table name is ignored, never interpolated.
  await softDelete(db, ['products; DROP TABLE customers']);
  final custStill = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='customers'",
  )).isNotEmpty;
  print('INJECTION GUARD: customers table still exists = $custStill (want true)');

  await db.close();
  Directory(tmp).deleteSync(recursive: true);
}
