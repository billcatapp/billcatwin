// Covers LocalDbService.renumberExistingInvoices, the Settings action that
// rewrites a shop's past bills into the GST series.
//
// This one is worth testing directly: it rewrites tax records, and the two
// parts most likely to be wrong — splitting the series per financial year,
// and keeping a return pointed at the bill it reverses — never run against
// a single-year shop with no returns.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:billcat/services/local_db_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        invoice_number TEXT,
        created_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 1,
        deleted INTEGER NOT NULL DEFAULT 0,
        rev INTEGER NOT NULL DEFAULT 0
      )
    ''');
  });

  tearDown(() async => db.close());

  Future<void> add(String id, String? number, String createdAt,
      {int deleted = 0}) async {
    await db.insert('transactions', {
      'id': id,
      'invoice_number': number,
      'created_at': createdAt,
      'synced': 1,
      'deleted': deleted,
      'rev': 0,
    });
  }

  Future<Map<String, String?>> numbers() async {
    final rows = await db.query('transactions', columns: ['id', 'invoice_number']);
    return {for (final r in rows) r['id'] as String: r['invoice_number'] as String?};
  }

  test('financialYear opens in April', () {
    expect(LocalDbService.financialYear(DateTime(2026, 4, 1)), '26-27');
    expect(LocalDbService.financialYear(DateTime(2027, 3, 31)), '26-27');
    expect(LocalDbService.financialYear(DateTime(2026, 3, 31)), '25-26');
    expect(LocalDbService.financialYear(DateTime(2026, 1, 15)), '25-26');
  });

  test('splits into a separate series per financial year, oldest first',
      () async {
    await add('a', 'OLD11111', '2026-02-10T10:00:00Z'); // FY 25-26
    await add('b', 'OLD22222', '2026-03-20T10:00:00Z'); // FY 25-26
    await add('c', 'OLD33333', '2026-04-02T10:00:00Z'); // FY 26-27
    await add('d', 'OLD44444', '2026-09-01T10:00:00Z'); // FY 26-27

    final (sales, reversals) =
        await LocalDbService.renumberExistingInvoices(into: db);

    expect(sales, 4);
    expect(reversals, 0);
    expect(await numbers(), {
      'a': 'INV/25-26/0001',
      'b': 'INV/25-26/0002',
      'c': 'INV/26-27/0001', // resets in April
      'd': 'INV/26-27/0002',
    });
  });

  test('keeps a return pointed at the bill it reverses', () async {
    await add('sale', 'ABC12345', '2026-05-01T10:00:00Z');
    await add('other', 'ZZZ99999', '2026-05-02T10:00:00Z');
    await add('ret', 'RTN-ABC12345', '2026-05-03T10:00:00Z');
    await add('exc', 'EXC-ZZZ99999', '2026-05-04T10:00:00Z');

    final (sales, reversals) =
        await LocalDbService.renumberExistingInvoices(into: db);

    expect(sales, 2);
    expect(reversals, 2);
    final n = await numbers();
    expect(n['sale'], 'INV/26-27/0001');
    expect(n['other'], 'INV/26-27/0002');
    // The link survives: same year and sequence, under the reversal's head.
    expect(n['ret'], 'RTN/26-27/0001');
    expect(n['exc'], 'EXC/26-27/0002');
  });

  test('relinks reversals already in the new format', () async {
    await add('sale', 'INV/26-27/0007', '2026-05-01T10:00:00Z');
    await add('ret', 'RTN/26-27/0007', '2026-05-02T10:00:00Z');

    await LocalDbService.renumberExistingInvoices(into: db);

    final n = await numbers();
    expect(n['sale'], 'INV/26-27/0001');
    expect(n['ret'], 'RTN/26-27/0001'); // followed its original
  });

  test('leaves a reversal alone when its original is missing', () async {
    await add('sale', 'AAA11111', '2026-05-01T10:00:00Z');
    await add('orphan', 'RTN-GONE9999', '2026-05-02T10:00:00Z');

    final (sales, reversals) =
        await LocalDbService.renumberExistingInvoices(into: db);

    expect(sales, 1);
    expect(reversals, 0);
    expect((await numbers())['orphan'], 'RTN-GONE9999');
  });

  test('skips deleted bills and does not spend a number on them', () async {
    await add('a', 'OLD11111', '2026-05-01T10:00:00Z');
    await add('gone', 'OLD22222', '2026-05-02T10:00:00Z', deleted: 1);
    await add('b', 'OLD33333', '2026-05-03T10:00:00Z');

    final (sales, _) = await LocalDbService.renumberExistingInvoices(into: db);

    expect(sales, 2);
    final n = await numbers();
    expect(n['a'], 'INV/26-27/0001');
    expect(n['b'], 'INV/26-27/0002'); // no gap left by the deleted bill
    expect(n['gone'], 'OLD22222'); // untouched
  });

  test('marks every rewritten row for upload', () async {
    await add('a', 'OLD11111', '2026-05-01T10:00:00Z');
    await add('ret', 'RTN-OLD11111', '2026-05-02T10:00:00Z');

    await LocalDbService.renumberExistingInvoices(into: db);

    final rows = await db.query('transactions', columns: ['synced', 'rev']);
    for (final r in rows) {
      expect(r['synced'], 0, reason: 'must be pushed to the cloud');
      expect(r['rev'], 1, reason: 'rev must bump so the push is rev-guarded');
    }
  });

  test('a second run changes nothing and writes nothing', () async {
    await add('a', 'OLD11111', '2026-05-01T10:00:00Z');
    await add('ret', 'RTN-OLD11111', '2026-05-02T10:00:00Z');

    await LocalDbService.renumberExistingInvoices(into: db);
    final first = await numbers();
    // Mark everything clean, as a successful push would.
    await db.update('transactions', {'synced': 1});

    final (sales, reversals) =
        await LocalDbService.renumberExistingInvoices(into: db);

    expect(sales, 0);
    expect(reversals, 0);
    expect(await numbers(), first);
    // Load-bearing for running on every launch: an already-converted shop
    // must not be dirtied again, or it would re-upload its whole history
    // every time the app opens.
    final rows = await db.query('transactions', columns: ['synced', 'rev']);
    for (final r in rows) {
      expect(r['synced'], 1, reason: 'must not be re-marked for upload');
      expect(r['rev'], 1, reason: 'rev must not bump on a no-op run');
    }
  });

  test('renumbers only what is wrong when a shop is partly converted',
      () async {
    await add('a', 'INV/26-27/0001', '2026-05-01T10:00:00Z');
    await add('b', 'RANDOM77', '2026-05-02T10:00:00Z');
    await db.update('transactions', {'synced': 1});

    final (sales, _) = await LocalDbService.renumberExistingInvoices(into: db);

    expect(sales, 1, reason: 'only the old-format bill is rewritten');
    expect(await numbers(), {'a': 'INV/26-27/0001', 'b': 'INV/26-27/0002'});
    final untouched = await db.query('transactions',
        columns: ['synced'], where: 'id = ?', whereArgs: ['a']);
    expect(untouched.first['synced'], 1, reason: 'correct bill left clean');
  });

  test('bills kept out of the GST return get their own INV/0001 series',
      () async {
    await db.execute(
      'ALTER TABLE transactions ADD COLUMN gst_billed INTEGER NOT NULL '
      'DEFAULT 1',
    );
    Future<void> addBill(String id, String number, String at, int gst) =>
        db.insert('transactions', {
          'id': id,
          'invoice_number': number,
          'created_at': at,
          'gst_billed': gst,
        });
    await addBill('g1', 'INV/26-27/0001', '2026-05-01T10:00:00', 1);
    // A non-GST bill wrongly sitting in the GST series, as one taken before
    // the second series existed would.
    await addBill('n1', 'INV/26-27/0002', '2026-05-02T10:00:00', 0);
    await addBill('g2', 'INV/26-27/0003', '2026-05-03T10:00:00', 1);
    await addBill('n2', 'INV/0007', '2026-05-04T10:00:00', 0);
    // A return of the non-GST bill follows it into its series.
    await addBill('r1', 'RTN/26-27/0002', '2026-05-05T10:00:00', 0);

    await LocalDbService.renumberExistingInvoices(into: db);
    final n = await numbers();
    expect(n['g1'], 'INV/26-27/0001');
    expect(n['g2'], 'INV/26-27/0002', reason: 'GST series closes the gap');
    expect(n['n1'], 'INV/0001');
    expect(n['n2'], 'INV/0002');
    expect(n['r1'], 'RTN/0001', reason: 'return follows its bill');

    expect(LocalDbService.isNonGstInvoice('INV/0001'), isTrue);
    expect(LocalDbService.isNonGstInvoice('INV/26-27/0001'), isFalse);
  });
}
