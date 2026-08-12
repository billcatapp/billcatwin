import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  final f = databaseFactoryFfi;
  final path =
      '${Platform.environment['APPDATA']}\\com.billcat\\billcat\\BillCat\\billcat_2c965dc3-8992-46a1-ae71-6faf43004d78.db';
  final db = await f.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
  final rows = await db.query('customers', orderBy: 'created_at DESC');
  print('customers: ${rows.length}');
  for (final r in rows) {
    print(
      '  ${r['name']} | ${r['phone']} | addr=${r['address']} | synced=${r['synced']} deleted=${r['deleted']} | ${r['created_at']}',
    );
  }
  await db.close();
}
