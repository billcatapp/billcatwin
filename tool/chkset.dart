import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  final f = databaseFactoryFfi;
  final path =
      '${Platform.environment['APPDATA']}\\com.billcat\\billcat\\BillCat\\billcat_2c965dc3-8992-46a1-ae71-6faf43004d78.db';
  final db = await f.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
  final rows = await db.query('settings', orderBy: 'key');
  for (final r in rows) {
    final k = r['key'] as String;
    if (k.contains('paper') || k.contains('printer') || k.contains('print') || k.contains('auto')) {
      print('$k = ${r['value']}');
    }
  }
  await db.close();
}
