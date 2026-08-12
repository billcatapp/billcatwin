import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// One-off repair: the cloud settings pull clobbered this machine's thermal
// paper size to A4 (bug fixed in connectivity_service). Restore what the
// user had set for their POS80.
Future<void> main() async {
  sqfliteFfiInit();
  final f = databaseFactoryFfi;
  final path =
      '${Platform.environment['APPDATA']}\\com.billcat\\billcat\\BillCat\\billcat_2c965dc3-8992-46a1-ae71-6faf43004d78.db';
  final db = await f.openDatabase(path);
  await db.insert('settings', {'key': 'paper_size', 'value': '3 inch'},
      conflictAlgorithm: ConflictAlgorithm.replace);
  final v = await db.query('settings', where: "key = 'paper_size'");
  print('paper_size now: ${v.first['value']}');
  await db.close();
}
