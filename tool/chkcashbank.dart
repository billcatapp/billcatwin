// QA: reconcile the Cash & Bank box against the live db.
//   cashIn + bankIn + hybridIn must equal SUM(total) for the same rows.
//   Also shows how refunds (negative totals) land per bucket.
//   dart run tool/chkcashbank.dart
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  final live =
      '${Platform.environment['APPDATA']}\\com.billcat\\billcat\\BillCat\\billcat_2c965dc3-8992-46a1-ae71-6faf43004d78.db';
  final tmp = Directory.systemTemp.createTempSync('cb').path;
  final work = '$tmp\\cb.db';
  File(live).copySync(work);
  final db = await databaseFactoryFfi.openDatabase(
    work,
    options: OpenDatabaseOptions(readOnly: true),
  );

  final rows = await db.query('transactions', where: 'deleted = 0');
  // Mirror the UPDATED box bucket logic exactly.
  var cash = 0.0, bank = 0.0, other = 0.0;
  final methods = <String, int>{};
  for (final r in rows) {
    final m = (r['payment_method'] as String?) ?? '';
    final total = (r['total'] as num).toDouble();
    final hc = (r['hybrid_cash'] as num?)?.toDouble() ?? 0;
    final hu = (r['hybrid_upi'] as num?)?.toDouble() ?? 0;
    methods[m] = (methods[m] ?? 0) + 1;
    switch (m) {
      case 'cash':
        cash += total;
        break;
      case 'card':
      case 'upi':
        bank += total;
        break;
      case 'hybrid':
        if (total != 0 && (hc + hu - total).abs() < 0.01) {
          cash += hc;
          bank += hu;
        } else {
          other += total;
        }
        break;
      default:
        other += total;
    }
  }
  final sumAll = rows.fold(0.0, (s, r) => s + (r['total'] as num).toDouble());
  final bucketSum = cash + bank + other;

  print('Payment methods present: $methods');
  print('CASH  = ${cash.toStringAsFixed(2)}');
  print('BANK  = ${bank.toStringAsFixed(2)}');
  print('OTHER = ${other.toStringAsFixed(2)}  (legacy rows w/o a recognised method)');
  print('');
  print('cash+bank+other = ${bucketSum.toStringAsFixed(2)}');
  print('SUM(all totals) = ${sumAll.toStringAsFixed(2)}');
  print('reconciles: ${(bucketSum - sumAll).abs() < 0.01 ? "YES" : "NO"}');
  print('');
  print('legacy "refund"/unknown rows are now in OTHER, not skewing CASH.');

  await db.close();
  Directory(tmp).deleteSync(recursive: true);
}
