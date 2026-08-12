// Direct evidence of return/exchange sync health against the LIVE db:
//   synced=1 on a return row means the cloud push confirmed it.
//   dart run tool/chkretsync.dart
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  final live =
      '${Platform.environment['APPDATA']}\\com.billcat\\billcat\\BillCat\\billcat_2c965dc3-8992-46a1-ae71-6faf43004d78.db';
  // Copy so we never contend with the running app's write lock.
  final tmp = Directory.systemTemp.createTempSync('billcat_rs').path;
  final work = '$tmp\\rs.db';
  File(live).copySync(work);
  final db = await databaseFactoryFfi.openDatabase(
    work,
    options: OpenDatabaseOptions(readOnly: true),
  );

  final rows = await db.rawQuery(
    "SELECT invoice_number, id, total, synced, deleted "
    "FROM transactions "
    "WHERE invoice_number LIKE 'RTN-%' OR invoice_number LIKE 'EXC-%' "
    "OR total < 0 "
    "ORDER BY created_at DESC",
  );
  print('Return/refund/exchange rows: ${rows.length}');
  var unsynced = 0, negWithoutPrefix = 0;
  for (final r in rows) {
    final inv = (r['invoice_number'] as String?) ?? '(no invoice)';
    final synced = r['synced'] as int;
    final total = r['total'];
    final deleted = r['deleted'];
    if (synced != 1 && deleted == 0) unsynced++;
    final hasPrefix = inv.startsWith('RTN-') || inv.startsWith('EXC-');
    if (!hasPrefix && (total as num) < 0) negWithoutPrefix++;
    print('  $inv  total=$total  synced=$synced  deleted=$deleted');
  }
  print('');
  print('UNSYNCED (still pending cloud, not deleted): $unsynced '
      '(0 = every return reached the cloud)');
  print('Negative total WITHOUT RTN-/EXC- prefix: $negWithoutPrefix '
      '(legacy/old-app refunds; still sync as ordinary rows)');

  // Any transaction still waiting to push at all?
  final pend = (await db.rawQuery(
    'SELECT COUNT(*) c FROM transactions WHERE synced = 0 AND deleted = 0',
  )).first['c'];
  final pendDel = (await db.rawQuery(
    'SELECT COUNT(*) c FROM transactions WHERE deleted = 1 AND synced = 0',
  )).first['c'];
  print('');
  print('All transactions pending upload (synced=0): $pend');
  print('Transaction deletions pending cloud removal: $pendDel');

  await db.close();
  Directory(tmp).deleteSync(recursive: true);
}
