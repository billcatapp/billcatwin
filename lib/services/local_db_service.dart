import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:io';
import 'dart:math' show Random;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../models/customer.dart';
import '../models/dealer.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../models/purchase.dart';
import '../models/transaction_record.dart';

class LocalDbService {
  static Database? _db;
  static String? _currentUserId;

  static Future<void> initForUser(String userId) async {
    if (_currentUserId == userId && _db != null) return;
    await _db?.close();
    _db = null;
    _currentUserId = userId;
    _db = await _open(userId);
  }

  static Future<Database> get db async {
    _db ??= await _open(_currentUserId ?? 'shared');
    return _db!;
  }

  static Future<String> _appSupportPath() async {
    // getApplicationSupportDirectory() returns the correct platform path:
    //   Windows → %APPDATA%\<company>\<app>  (e.g. C:\Users\x\AppData\Roaming\BillCat\BillCat)
    //   macOS   → ~/Library/Application Support/BillCat
    //   Linux   → ~/.local/share/BillCat
    final base = await getApplicationSupportDirectory();
    final dir = Directory(join(base.path, 'BillCat'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<Database> _open(String userId) async {
    final dbPath = await _appSupportPath();
    final database = await _openVersioned(dbPath, userId);
    await _healSchema(database);
    return database;
  }

  /// Columns added by migrations, and the definition to restore them with.
  /// Every ALTER in [_openVersioned] is wrapped in `catch (_) {}` so a
  /// migration that fails once (a second app instance holding the file lock
  /// during an update is the usual cause) is swallowed while the version
  /// still stamps as current — leaving the column missing forever. Reads
  /// tolerate that, but every write does `rev = rev + 1`, so checkout,
  /// delete and edit would fail on that device from then on with no message.
  /// [_healSchema] re-adds anything missing on each open.
  static const Map<String, Map<String, String>> _expectedColumns = {
    'products': {
      'deleted': 'INTEGER NOT NULL DEFAULT 0',
      'buying_price': 'REAL NOT NULL DEFAULT 0',
      'tax_percent': 'REAL NOT NULL DEFAULT 0',
      'hsn_code': "TEXT NOT NULL DEFAULT ''",
      'description': 'TEXT NOT NULL DEFAULT ""',
      'barcode_no': "TEXT NOT NULL DEFAULT ''",
      'dealer_name': "TEXT NOT NULL DEFAULT ''",
      'purchase_date': "TEXT NOT NULL DEFAULT ''",
      'gst_purchase': 'INTEGER NOT NULL DEFAULT 1',
      'rev': 'INTEGER NOT NULL DEFAULT 0',
    },
    'product_variants': {
      'deleted': 'INTEGER NOT NULL DEFAULT 0',
      'rev': 'INTEGER NOT NULL DEFAULT 0',
    },
    'transactions': {
      'invoice_number': 'TEXT',
      'deleted': 'INTEGER NOT NULL DEFAULT 0',
      'rev': 'INTEGER NOT NULL DEFAULT 0',
      'balance_due': 'REAL NOT NULL DEFAULT 0',
      'hybrid_cash': 'REAL NOT NULL DEFAULT 0',
      'hybrid_upi': 'REAL NOT NULL DEFAULT 0',
      'salesperson': "TEXT NOT NULL DEFAULT ''",
      'gst_billed': 'INTEGER NOT NULL DEFAULT 1',
    },
    'customers': {
      'address': 'TEXT',
      'deleted': 'INTEGER NOT NULL DEFAULT 0',
      'rev': 'INTEGER NOT NULL DEFAULT 0',
    },
    'categories': {
      'deleted': 'INTEGER NOT NULL DEFAULT 0',
      'rev': 'INTEGER NOT NULL DEFAULT 0',
    },
    // Local-only table; added to existing installs by _healSchema.
    'dealers': {
      'gstin': "TEXT NOT NULL DEFAULT ''",
    },
    'purchases': {
      'dealer_gstin': "TEXT NOT NULL DEFAULT ''",
      'place_of_supply': "TEXT NOT NULL DEFAULT ''",
      'reverse_charge': 'INTEGER NOT NULL DEFAULT 0',
      'notes': "TEXT NOT NULL DEFAULT ''",
      'gst_report': 'INTEGER NOT NULL DEFAULT 1',
      'deleted': 'INTEGER NOT NULL DEFAULT 0',
      'rev': 'INTEGER NOT NULL DEFAULT 0',
    },
  };

  static Future<void> _healSchema(Database db) async {
    // Idempotent: only ever creates what is absent, never rewrites data.
    try {
      await db.execute(_productVariantsTableSql);
    } catch (_) {}
    try {
      await db.execute(_dealersTableSql);
      await _seedDealersFromProducts(db);
    } catch (_) {}
    try {
      await db.execute(_purchasesTableSql);
    } catch (_) {}
    try {
      await db.execute(_recycleBinTableSql);
      await purgeExpiredBinEntries(db);
    } catch (_) {}
    for (final table in _expectedColumns.entries) {
      final Set<String> present;
      try {
        present = {
          for (final r in await db.rawQuery('PRAGMA table_info(${table.key})'))
            r['name'] as String,
        };
      } catch (_) {
        continue;
      }
      // Empty means the table itself is absent; that is onCreate's job, and
      // ALTERing it here would only throw.
      if (present.isEmpty) continue;
      for (final column in table.value.entries) {
        if (present.contains(column.key)) continue;
        try {
          await db.execute(
            'ALTER TABLE ${table.key} ADD COLUMN ${column.key} ${column.value}',
          );
        } catch (_) {}
      }
    }
  }

  static Future<Database> _openVersioned(String dbPath, String userId) async {
    return openDatabase(
      join(dbPath, 'billcat_$userId.db'),
      version: 23,
      // Hardening against "database is locked" (SQLITE_BUSY) when another
      // process briefly holds the file (leftover instance, antivirus scan):
      // WAL lets readers and writers coexist, and busy_timeout makes a write
      // wait up to 5s for the lock instead of failing the bill instantly.
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.rawQuery('PRAGMA busy_timeout=5000');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
            );
          } catch (_) {}
        }
        if (oldVersion < 5) {
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN buying_price REAL NOT NULL DEFAULT 0',
            );
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN tax_percent REAL NOT NULL DEFAULT 0',
            );
          } catch (_) {}
        }
        if (oldVersion < 6) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS categories (
                name TEXT PRIMARY KEY,
                synced INTEGER NOT NULL DEFAULT 0
              )
            ''');
          } catch (_) {}
        }
        if (oldVersion < 7) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
              )
            ''');
          } catch (_) {}
        }
        if (oldVersion < 8) {
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN description TEXT NOT NULL DEFAULT ""',
            );
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE transactions ADD COLUMN invoice_number TEXT',
            );
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE customers ADD COLUMN address TEXT');
          } catch (_) {}
        }
        if (oldVersion < 9) {
          try {
            await db.execute(
              "ALTER TABLE products ADD COLUMN barcode_no TEXT NOT NULL DEFAULT ''",
            );
          } catch (_) {}
        }
        if (oldVersion < 10) {
          try {
            await db.execute(_productVariantsTableSql);
          } catch (_) {}
        }
        if (oldVersion < 11) {
          try {
            await db.execute(
              "ALTER TABLE products ADD COLUMN dealer_name TEXT NOT NULL DEFAULT ''",
            );
          } catch (_) {}
        }
        if (oldVersion < 12) {
          try {
            await db.execute(
              "ALTER TABLE products ADD COLUMN purchase_date TEXT NOT NULL DEFAULT ''",
            );
          } catch (_) {}
        }
        if (oldVersion < 13) {
          try {
            await db.execute(
              'ALTER TABLE transactions ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
            );
          } catch (_) {}
        }
        if (oldVersion < 14) {
          // Same soft-delete pattern as products/transactions, so customer
          // and category deletions sync to the cloud instead of resurrecting.
          try {
            await db.execute(
              'ALTER TABLE customers ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
            );
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE categories ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
            );
          } catch (_) {}
        }
        if (oldVersion < 15) {
          // Per-row revision counter. Every local write that marks a row
          // unsynced also bumps rev; the push marks synced=1 only if rev is
          // unchanged, so an edit made while an upsert is in flight is never
          // silently dropped from the sync queue.
          for (final t in [
            'products',
            'product_variants',
            'transactions',
            'customers',
            'categories',
          ]) {
            try {
              await db.execute(
                'ALTER TABLE $t ADD COLUMN rev INTEGER NOT NULL DEFAULT 0',
              );
            } catch (_) {}
          }
        }
        if (oldVersion < 16) {
          // Credit sales: amount still owed on a bill. Default 0 keeps every
          // existing sale correctly fully-paid.
          try {
            await db.execute(
              'ALTER TABLE transactions ADD COLUMN balance_due REAL NOT NULL '
              'DEFAULT 0',
            );
          } catch (_) {}
        }
        if (oldVersion < 17) {
          // Hybrid (split) payment: cash vs UPI portions. Default 0.
          for (final col in ['hybrid_cash', 'hybrid_upi']) {
            try {
              await db.execute(
                'ALTER TABLE transactions ADD COLUMN $col REAL NOT NULL '
                'DEFAULT 0',
              );
            } catch (_) {}
          }
        }
        if (oldVersion < 18) {
          // HSN/SAC code per product, for tax invoices and the GSTR-1 HSN
          // summary. Blank on every existing row; the invoice keeps printing
          // its em-dash until a code is filled in.
          try {
            await db.execute(
              "ALTER TABLE products ADD COLUMN hsn_code TEXT NOT NULL "
              "DEFAULT ''",
            );
          } catch (_) {}
          // Per-product tax rates were removed from the product form in
          // v1.9.1; every product now follows the store-wide rate. Clearing
          // the column is what makes that inheritance take effect, since
          // CartProvider treats 0 as "use the store rate" and freezes the
          // resolved rate onto each bill line. Past bills keep the rate they
          // were charged at.
          // synced = 0 / rev + 1 is load-bearing, not decoration: a plain
          // UPDATE leaves synced = 1, and insertProductsSynced overwrites any
          // synced row on the next pull, so the cloud's old rates would come
          // straight back. Marking the rows dirty makes the zero survive the
          // merge and then push up, exactly as softDeleteAllInTables does.
          try {
            await db.execute(
              'UPDATE products SET tax_percent = 0, synced = 0, '
              'rev = rev + 1 WHERE tax_percent != 0',
            );
          } catch (_) {}
        }
        if (oldVersion < 19) {
          // Supplier bills, so a GST purchase register can be reported with
          // the supplier's own invoice number and per-line HSN. Nothing
          // existing is read or rewritten; _healSchema re-creates the table
          // if this ALTER is ever swallowed.
          try {
            await db.execute(_purchasesTableSql);
          } catch (_) {}
        }
        if (oldVersion < 20) {
          // Recycle bin: recoverable copies of deleted rows. Local-only, so
          // nothing about sync changes.
          try {
            await db.execute(_recycleBinTableSql);
          } catch (_) {}
        }
        if (oldVersion < 21) {
          // Who rang the bill up. Blank on every existing bill; the receipt
          // simply omits the line until a salesperson is chosen.
          try {
            await db.execute(
              "ALTER TABLE transactions ADD COLUMN salesperson TEXT NOT NULL "
              "DEFAULT ''",
            );
          } catch (_) {}
        }
        if (oldVersion < 22) {
          // Whether a bill belongs in the GST return. Every existing bill
          // did, so the default is 1.
          try {
            await db.execute(
              'ALTER TABLE transactions ADD COLUMN gst_billed INTEGER NOT NULL '
              'DEFAULT 1',
            );
          } catch (_) {}
        }
        if (oldVersion < 23) {
          // Whether stock bought belongs in the GST purchase report: on the
          // product (local-only, beside purchase_date) and on recorded
          // supplier bills. Everything stored so far did, so both default 1.
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN gst_purchase INTEGER NOT NULL '
              'DEFAULT 1',
            );
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE purchases ADD COLUMN gst_report INTEGER NOT NULL '
              'DEFAULT 1',
            );
          } catch (_) {}
        }
      },
      onCreate: (db, _) => _createTables(db),
    );
  }

  // Local-only dealer directory. Deliberately NOT part of cloud sync: the
  // sync system is finalized, and products already carry dealer_name (which
  // does sync), so dealer attribution survives across devices either way.
  static const String _dealersTableSql = '''
    CREATE TABLE IF NOT EXISTS dealers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '',
      gstin TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT '',
      deleted INTEGER NOT NULL DEFAULT 0
    )
  ''';

  /// Recoverable copies of deleted rows.
  ///
  /// Deliberately a SEPARATE table rather than un-purged tombstones: a row is
  /// archived here BEFORE the existing delete runs, so the delete and the
  /// sync engine behind it are left exactly as they were. The sync system is
  /// finalized, and a recycle bin is not worth reopening it for.
  ///
  /// Local-only and never synced, so the bin belongs to the till that did the
  /// deleting. [payload] is the whole original row as JSON, which is what
  /// makes a restore an exact re-insert rather than a reconstruction.
  static const String _recycleBinTableSql = '''
    CREATE TABLE IF NOT EXISTS recycle_bin (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      row_id TEXT NOT NULL,
      label TEXT NOT NULL DEFAULT '',
      payload TEXT NOT NULL,
      deleted_at TEXT NOT NULL
    )
  ''';

  /// Supplier bills, one row per invoice with the lines as JSON — the same
  /// shape `transactions` uses, so purchases need one table and one sync
  /// binding rather than a parent/child pair.
  static const String _purchasesTableSql = '''
    CREATE TABLE IF NOT EXISTS purchases (
      id TEXT PRIMARY KEY,
      dealer_id TEXT NOT NULL DEFAULT '',
      dealer_name TEXT NOT NULL DEFAULT '',
      dealer_gstin TEXT NOT NULL DEFAULT '',
      invoice_no TEXT NOT NULL DEFAULT '',
      invoice_date TEXT NOT NULL DEFAULT '',
      place_of_supply TEXT NOT NULL DEFAULT '',
      reverse_charge INTEGER NOT NULL DEFAULT 0,
      notes TEXT NOT NULL DEFAULT '',
      items TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL DEFAULT '',
      gst_report INTEGER NOT NULL DEFAULT 1,
      synced INTEGER NOT NULL DEFAULT 0,
      deleted INTEGER NOT NULL DEFAULT 0,
      rev INTEGER NOT NULL DEFAULT 0
    )
  ''';

  static const String _productVariantsTableSql = '''
    CREATE TABLE IF NOT EXISTS product_variants (
      id TEXT PRIMARY KEY,
      product_id TEXT NOT NULL,
      label TEXT NOT NULL,
      price REAL NOT NULL,
      buying_price REAL NOT NULL DEFAULT 0,
      stock INTEGER NOT NULL DEFAULT 0,
      sku TEXT NOT NULL DEFAULT '',
      barcode_no TEXT NOT NULL DEFAULT '',
      synced INTEGER NOT NULL DEFAULT 0,
      deleted INTEGER NOT NULL DEFAULT 0,
      rev INTEGER NOT NULL DEFAULT 0
    )
  ''';

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT "",
        price REAL NOT NULL,
        buying_price REAL NOT NULL DEFAULT 0,
        tax_percent REAL NOT NULL DEFAULT 0,
        hsn_code TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL,
        emoji TEXT NOT NULL,
        sku TEXT NOT NULL,
        stock INTEGER NOT NULL,
        barcode_no TEXT NOT NULL DEFAULT '',
        dealer_name TEXT NOT NULL DEFAULT '',
        purchase_date TEXT NOT NULL DEFAULT '',
        gst_purchase INTEGER NOT NULL DEFAULT 1,
        synced INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        rev INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        invoice_number TEXT,
        customer_name TEXT,
        customer_phone TEXT,
        items TEXT NOT NULL,
        subtotal REAL NOT NULL,
        discount_amount REAL NOT NULL,
        tax_amount REAL NOT NULL,
        total REAL NOT NULL,
        payment_method TEXT NOT NULL,
        created_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        rev INTEGER NOT NULL DEFAULT 0,
        balance_due REAL NOT NULL DEFAULT 0,
        hybrid_cash REAL NOT NULL DEFAULT 0,
        hybrid_upi REAL NOT NULL DEFAULT 0,
        salesperson TEXT NOT NULL DEFAULT '',
        gst_billed INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        created_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        rev INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE categories (
        name TEXT PRIMARY KEY,
        synced INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        rev INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute(_productVariantsTableSql);
    await db.execute(_purchasesTableSql);
    await db.execute(_recycleBinTableSql);
  }

  // ── Invoice ID ───────────────────────────────────────────────────────────

  // Same 8-character format the Mac app issues, so a bill's number looks
  // identical no matter which device rang it up.
  static String generateInvoiceId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Series head for an ordinary sale under the `INV/<fy>/<seq>` numbering.
  static const String invoicePrefix = 'INV';

  /// The Indian financial year [on] falls in, as '26-27' for
  /// 1 Apr 2026 – 31 Mar 2027. April opens the year, so January to March
  /// belong to the year that started the previous April.
  static String financialYear(DateTime on) {
    final startYear = on.month >= 4 ? on.year : on.year - 1;
    final from = (startYear % 100).toString().padLeft(2, '0');
    final to = ((startYear + 1) % 100).toString().padLeft(2, '0');
    return '$from-$to';
  }

  /// The next sequential invoice number, e.g. 'INV/26-27/0001'.
  ///
  /// The sequence is read back from the bills already stored rather than from
  /// a stored counter, so a bill that arrives from the cloud raises the
  /// ceiling on its own. Soft-deleted rows are counted deliberately: a
  /// deleted bill leaves a permanent gap rather than handing its number to
  /// the next sale. Past 9999 the sequence widens to five digits instead of
  /// wrapping back to 0001.
  static Future<String> nextInvoiceNumber([DateTime? on]) async {
    final when = on ?? DateTime.now();
    final head = '$invoicePrefix/${financialYear(when)}/';
    final database = await db;
    final rows = await database.query(
      'transactions',
      columns: ['invoice_number'],
      where: 'invoice_number LIKE ?',
      whereArgs: ['$head%'],
    );
    var highest = 0;
    for (final r in rows) {
      final number = r['invoice_number'] as String?;
      if (number == null) continue;
      final seq = int.tryParse(number.substring(head.length));
      if (seq != null && seq > highest) highest = seq;
    }
    // Nothing in this series yet on a till that already has history: carry on
    // from the bills already raised this financial year instead of restarting
    // at 0001, so an existing shop's books show no mid-year reset.
    if (highest == 0) highest = await _billsThisFinancialYear(when);
    return '$head${(highest + 1).toString().padLeft(4, '0')}';
  }

  /// Whether [number] belongs to the series for bills kept out of the GST
  /// return: 'INV/' then digits only, e.g. 'INV/0001'. The GST series always
  /// carries a financial year between two slashes, so the two never overlap.
  static bool isNonGstInvoice(String number) =>
      RegExp(r'^INV/\d+$').hasMatch(number);

  /// The next number for a bill marked "not GST billed", e.g. 'INV/0001'.
  ///
  /// A series of its own, so the GST series stays gapless for the return
  /// while these bills are still numbered in order. One continuous run, not
  /// split by financial year: the owner asked for 'INV/0001', and these bills
  /// file nowhere that needs the year. Same rules as the GST series otherwise
  /// — read back from the stored bills, deleted ones counted, never wrapping.
  static Future<String> nextNonGstInvoiceNumber() async {
    final database = await db;
    final rows = await database.query(
      'transactions',
      columns: ['invoice_number'],
      where: "invoice_number LIKE 'INV/%' AND invoice_number NOT LIKE 'INV/%/%'",
    );
    var highest = 0;
    for (final r in rows) {
      final number = r['invoice_number'] as String?;
      if (number == null || !isNonGstInvoice(number)) continue;
      final seq = int.tryParse(number.substring('$invoicePrefix/'.length));
      if (seq != null && seq > highest) highest = seq;
    }
    return '$invoicePrefix/${(highest + 1).toString().padLeft(4, '0')}';
  }

  /// How many bills were already raised in [on]'s financial year, under any
  /// numbering. Used once, to seed the sequence on a till that is meeting the
  /// INV series for the first time.
  ///
  /// Reversals are left out: a return is not itself a fresh sale invoice.
  /// Soft-deleted rows are counted, for the same reason the sequence is taken
  /// from the highest issued rather than a live count — a number that has
  /// been used must not be handed out again.
  static Future<int> _billsThisFinancialYear(DateTime on) async {
    final startYear = on.month >= 4 ? on.year : on.year - 1;
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS c FROM transactions '
      'WHERE substr(created_at, 1, 10) >= ? AND substr(created_at, 1, 10) <= ? '
      "AND COALESCE(invoice_number, '') NOT LIKE 'RTN-%' "
      "AND COALESCE(invoice_number, '') NOT LIKE 'EXC-%' "
      "AND COALESCE(invoice_number, '') NOT LIKE 'RTN/%' "
      "AND COALESCE(invoice_number, '') NOT LIKE 'EXC/%' "
      // Bills kept out of the GST return have their own series.
      'AND gst_billed = 1',
      ['$startYear-04-01', '${startYear + 1}-03-31'],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Renumbers every stored bill into the `INV/<fy>/<seq>` series, oldest
  /// first, with a separate series per financial year. Returns the number of
  /// (sales, reversals) rewritten.
  ///
  /// Deliberately NOT automatic. Two tills renumbering at the same time would
  /// assign different numbers to the same bill and then overwrite each other,
  /// so this runs only when a shopkeeper asks for it, on one machine, and the
  /// caller pulls first so the numbering is decided from the full picture.
  ///
  /// Reversals are rewritten through the same map inside the same
  /// transaction. A return stores its link to the original bill inside its
  /// own number, so moving an original without moving its return would break
  /// the check that stops an item being returned twice.
  ///
  /// Soft-deleted bills are left alone: they are absent from every report, so
  /// numbering them would only punch holes in the series.
  /// [into] lets a test drive this against its own database; the app always
  /// leaves it null and the service's own database is used.
  static Future<(int, int)> renumberExistingInvoices({Database? into}) async {
    final database = into ?? await db;
    var sales = 0;
    var reversals = 0;

    bool isReversal(String n) =>
        n.startsWith(TransactionRecord.returnPrefix) ||
        n.startsWith(TransactionRecord.exchangePrefix) ||
        n.startsWith(TransactionRecord.returnSeries) ||
        n.startsWith(TransactionRecord.exchangeSeries);

    await database.transaction((txn) async {
      // Every column, so a database without gst_billed (a test, or one not
      // yet migrated) still reads; such rows are all GST bills.
      final rows = await txn.query(
        'transactions',
        where: 'deleted = 0',
        orderBy: 'created_at ASC',
      );

      final perYear = <String, int>{};
      // Bills kept out of the GST return run in their own series, 'INV/0001'
      // onwards, so they never take a place in the GST one.
      var nonGst = 0;
      final renamed = <String, String>{};
      final updates = <(String, String)>[];

      // Sales first, so a reversal can be pointed at its original's new
      // number in the second pass.
      for (final r in rows) {
        final old = (r['invoice_number'] as String?) ?? '';
        if (old.isNotEmpty && isReversal(old)) continue;
        final created = DateTime.tryParse((r['created_at'] as String?) ?? '');
        if (created == null) continue;
        final String number;
        if (((r['gst_billed'] as num?)?.toInt() ?? 1) == 0) {
          nonGst++;
          number = '$invoicePrefix/${nonGst.toString().padLeft(4, '0')}';
        } else {
          final fy = financialYear(created);
          final seq = (perYear[fy] ?? 0) + 1;
          perYear[fy] = seq;
          number = '$invoicePrefix/$fy/${seq.toString().padLeft(4, '0')}';
        }
        if (old.isNotEmpty) renamed[old] = number;
        // A bill already carrying its correct number is left alone, so a
        // second run writes nothing at all. That is what makes this safe to
        // call on every launch: once a shop is converted it costs one read.
        if (old == number) continue;
        updates.add((r['id'] as String, number));
        sales++;
      }

      for (final r in rows) {
        final old = (r['invoice_number'] as String?) ?? '';
        if (old.isEmpty || !isReversal(old)) continue;
        final isExchange =
            old.startsWith(TransactionRecord.exchangePrefix) ||
            old.startsWith(TransactionRecord.exchangeSeries);
        // Recover the original's number: 'RTN-ABC12345' points at 'ABC12345',
        // 'RTN/26-27/0042' at 'INV/26-27/0042'.
        final base =
            old.startsWith(TransactionRecord.returnSeries) ||
                old.startsWith(TransactionRecord.exchangeSeries)
            ? '${TransactionRecord.salesSeries}'
                  '${old.substring(TransactionRecord.returnSeries.length)}'
            : old.substring(TransactionRecord.returnPrefix.length);
        final mapped = renamed[base];
        // The original is missing or was never renumbered — leaving the
        // reversal untouched keeps it pointing where it always did.
        if (mapped == null) continue;
        final head = isExchange
            ? TransactionRecord.exchangeSeries
            : TransactionRecord.returnSeries;
        final number =
            '$head${mapped.substring(TransactionRecord.salesSeries.length)}';
        if (old == number) continue;
        updates.add((r['id'] as String, number));
        reversals++;
      }

      final batch = txn.batch();
      for (final (id, number) in updates) {
        batch.rawUpdate(
          'UPDATE transactions SET invoice_number = ?, synced = 0, '
          'rev = rev + 1 WHERE id = ?',
          [number, id],
        );
      }
      await batch.commit(noResult: true);
    });

    return (sales, reversals);
  }

  // ── Recycle bin ───────────────────────────────────────────────────────────

  /// How long a deleted row stays recoverable.
  static const Duration binRetention = Duration(days: 30);

  /// Which live table each archived kind came from. Restoring puts the row
  /// straight back into it.
  static const Map<String, String> _binTables = {
    'transaction': 'transactions',
    'customer': 'customers',
    'product': 'products',
    'variant': 'product_variants',
    'category': 'categories',
    'purchase': 'purchases',
  };

  /// Copies [rows] into the bin before their table rows are deleted. Takes the
  /// caller's [txn] so the archive and the delete commit together: a copy
  /// without a delete would show a phantom entry in the bin, and a delete
  /// without a copy loses the data this feature exists to keep.
  static Future<void> archiveRows(
    DatabaseExecutor txn,
    String kind,
    List<Map<String, Object?>> rows,
    String Function(Map<String, Object?> row) labelOf,
  ) async {
    if (rows.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final batch = txn.batch();
    for (final row in rows) {
      // Categories key on name; everything else on id.
      final rowId = (row['id'] ?? row['name'] ?? '').toString();
      if (rowId.isEmpty) continue;
      batch.insert('recycle_bin', {
        'id': const Uuid().v4(),
        'kind': kind,
        'row_id': rowId,
        'label': labelOf(row),
        'payload': jsonEncode(row),
        'deleted_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Convenience for the common case: read the rows about to be deleted, then
  /// archive them.
  static Future<void> archiveByQuery(
    DatabaseExecutor txn,
    String kind,
    String table,
    String where,
    List<Object?> whereArgs,
    String Function(Map<String, Object?> row) labelOf,
  ) async {
    final rows = await txn.query(table, where: where, whereArgs: whereArgs);
    await archiveRows(txn, kind, rows, labelOf);
  }

  /// Bin contents, newest first.
  static Future<List<Map<String, Object?>>> getRecycleBin() async {
    final database = await db;
    return database.query('recycle_bin', orderBy: 'deleted_at DESC');
  }

  static Future<int> recycleBinCount() async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS c FROM recycle_bin',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Puts an archived row back into its table and drops the bin entry.
  ///
  /// The row goes back marked unsynced so the existing push re-creates it in
  /// the cloud, where the original delete removed it for good. `deleted` is
  /// forced to 0: the archived copy was taken BEFORE the delete, but a reset
  /// archives rows that may already carry a tombstone.
  static Future<bool> restoreFromBin(String entryId) async {
    final database = await db;
    return database.transaction((txn) async {
      final rows = await txn.query(
        'recycle_bin',
        where: 'id = ?',
        whereArgs: [entryId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final kind = rows.first['kind'] as String;
      final table = _binTables[kind];
      if (table == null) return false;
      final Map<String, Object?> payload;
      try {
        payload = Map<String, Object?>.from(
          jsonDecode(rows.first['payload'] as String) as Map,
        );
      } catch (_) {
        return false;
      }
      payload['deleted'] = 0;
      payload['synced'] = 0;
      if (payload.containsKey('rev')) {
        payload['rev'] = ((payload['rev'] as num?)?.toInt() ?? 0) + 1;
      }
      await txn.insert(
        table,
        payload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('recycle_bin', where: 'id = ?', whereArgs: [entryId]);
      return true;
    });
  }

  static Future<void> deleteBinEntry(String entryId) async {
    final database = await db;
    await database.delete('recycle_bin', where: 'id = ?', whereArgs: [entryId]);
  }

  static Future<void> emptyRecycleBin() async {
    final database = await db;
    await database.delete('recycle_bin');
  }

  /// Drops entries past [binRetention]. Runs on every open, so the bin cannot
  /// grow without bound on a till that is never looked at.
  static Future<void> purgeExpiredBinEntries([DatabaseExecutor? into]) async {
    final database = into ?? await db;
    final cutoff = DateTime.now().subtract(binRetention).toIso8601String();
    await database.delete(
      'recycle_bin',
      where: 'deleted_at < ?',
      whereArgs: [cutoff],
    );
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  /// Local-only dirty marker for settings. Holds an increasing counter so a
  /// push can clear exactly the edits it uploaded: an edit made WHILE the
  /// upload was in flight bumps the counter and stays dirty for the next
  /// cycle. The underscore prefix keeps it out of the cloud push (the
  /// knownSettingsCols filter) and it is ignored by the UI.
  static const String settingsDirtyKey = '_settings_dirty';

  static Future<Map<String, String>> getSettings() async {
    final database = await db;
    final rows = await database.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  /// Save settings edited ON THIS DEVICE — marks them dirty so the sync
  /// engine pushes them (and only then). Cloud pulls must use
  /// [saveSettingsFromCloud] instead, or every pull would masquerade as a
  /// local edit and ping-pong between devices.
  static Future<void> saveSettings(Map<String, String> settings) async {
    final database = await db;
    final current =
        int.tryParse((await getSettings())[settingsDirtyKey] ?? '') ?? 0;
    await _saveSettingsRaw(database, {
      ...settings,
      settingsDirtyKey: '${current + 1}',
    });
  }

  /// Apply settings that came FROM the cloud — no dirty marking.
  static Future<void> saveSettingsFromCloud(
    Map<String, String> settings,
  ) async {
    final database = await db;
    final filtered = Map<String, String>.from(settings)
      ..remove(settingsDirtyKey);
    await _saveSettingsRaw(database, filtered);
  }

  static Future<void> _saveSettingsRaw(
    Database database,
    Map<String, String> settings,
  ) async {
    final batch = database.batch();
    for (final e in settings.entries) {
      batch.insert('settings', {
        'key': e.key,
        'value': e.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Current dirty token, or null when there are no unpushed local edits.
  static Future<String?> getSettingsDirtyToken() async =>
      (await getSettings())[settingsDirtyKey];

  /// Clears the dirty marker ONLY if it still holds [token] — an edit made
  /// during the push bumped it, and must survive to be pushed next cycle.
  static Future<void> clearSettingsDirtyIfToken(String token) async {
    final database = await db;
    await database.delete(
      'settings',
      where: 'key = ? AND value = ?',
      whereArgs: [settingsDirtyKey, token],
    );
  }

  // ── Categories ────────────────────────────────────────────────────────────

  static Future<List<String>> getCategories() async {
    final database = await db;
    final rows = await database.query(
      'categories',
      where: 'deleted = 0',
      orderBy: 'name ASC',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  static Future<void> saveCategory(String name) async {
    final database = await db;
    // Re-adding a name that still has a pending-delete tombstone resurrects
    // the row instead of being swallowed by the insert's conflict-ignore.
    final revived = await database.rawUpdate(
      'UPDATE categories SET deleted = 0, synced = 0, rev = rev + 1 '
      'WHERE name = ? AND deleted = 1',
      [name],
    );
    if (revived == 0) {
      await database.insert('categories', {
        'name': name,
        'synced': 0,
        'deleted': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> renameCategory(String oldName, String newName) async {
    final database = await db;
    // Tombstone the old name (so the rename removes it from the cloud too —
    // a plain local delete would resurrect on the next pull), add the new one.
    await database.rawUpdate(
      'UPDATE categories SET deleted = 1, synced = 0, rev = rev + 1 '
      'WHERE name = ?',
      [oldName],
    );
    await saveCategory(newName);
  }

  static Future<void> deleteCategory(String name) async {
    final database = await db;
    // Soft-delete: hidden immediately, pushed as a cloud deletion.
    await database.rawUpdate(
      'UPDATE categories SET deleted = 1, synced = 0, rev = rev + 1 '
      'WHERE name = ?',
      [name],
    );
  }

  static Future<List<String>> getUnsyncedCategories() async {
    final database = await db;
    final rows = await database.query(
      'categories',
      where: 'synced = 0 AND deleted = 0',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Same as [getUnsyncedCategories] but also returns each row's rev, read in
  /// the SAME query so the push can mark-synced conditionally on it.
  static Future<(List<String>, Map<String, int>)>
  getUnsyncedCategoriesWithRev() async {
    final database = await db;
    final rows = await database.query(
      'categories',
      where: 'synced = 0 AND deleted = 0',
    );
    return (
      rows.map((r) => r['name'] as String).toList(),
      {
        for (final r in rows)
          r['name'] as String: (r['rev'] as int?) ?? 0,
      },
    );
  }

  // Categories deleted locally but not yet removed from Supabase.
  static Future<List<String>> getPendingDeleteCategoryNames() async {
    final database = await db;
    final rows = await database.query(
      'categories',
      columns: ['name'],
      where: 'deleted = 1 AND synced = 0',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  // Call after confirming Supabase deletion — hard-removes the local row.
  // The deleted=1 guard means a row the user re-added (revived tombstone)
  // while the cloud delete was in flight survives and is re-pushed.
  static Future<void> purgeDeletedCategory(String name) async {
    final database = await db;
    await database.delete(
      'categories',
      where: 'name = ? AND deleted = 1',
      whereArgs: [name],
    );
  }

  static Future<void> markCategorySynced(String name) async {
    final database = await db;
    await database.update(
      'categories',
      {'synced': 1},
      where: 'name = ?',
      whereArgs: [name],
    );
  }

  static Future<void> insertCategoriesSynced(List<String> names) async {
    final database = await db;
    // One transaction so the tombstone check and the writes are atomic — a
    // delete tapped mid-merge can't slip between the snapshot and the batch.
    await database.transaction((txn) async {
      // Don't resurrect names whose deletion hasn't reached the cloud yet.
      final pendingDeletes = {
        for (final r in await txn.query(
          'categories',
          columns: ['name'],
          where: 'deleted = 1',
        ))
          r['name'] as String,
      };
      final batch = txn.batch();
      for (final name in names) {
        if (pendingDeletes.contains(name)) continue;
        batch.insert('categories', {
          'name': name,
          'synced': 1,
          'deleted': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Removes local synced categories that no longer exist in the cloud, so a
  /// deletion done on another device disappears here too. Only runs after a
  /// successful cloud fetch, so an empty set is a real "no categories" state.
  static Future<void> reconcileCategoriesWithCloud(
    Set<String> cloudNames,
  ) async {
    final database = await db;
    final rows = await database.query(
      'categories',
      columns: ['name'],
      where: 'synced = 1 AND deleted = 0',
    );
    for (final row in rows) {
      final name = row['name'] as String;
      if (!cloudNames.contains(name)) {
        await database.delete(
          'categories',
          where: 'name = ?',
          whereArgs: [name],
        );
      }
    }
  }

  // ── Clear all local data ──────────────────────────────────────────────────
  // DANGER: wipes pending unsynced rows and delete-tombstones too. The DB
  // file is already per-user (billcat_<userId>.db), so login/logout flows
  // must NOT call this — pullFromCloud's merge + reconcile keeps the local
  // copy fresh without destroying unpushed work. Kept only for an explicit
  // "reset local data" action.
  static Future<void> clearAll() async {
    final database = await db;
    await database.delete('products');
    await database.delete('product_variants');
    await database.delete('transactions');
    await database.delete('customers');
    await database.delete('categories');
  }

  /// Tables the Data-reset screen is allowed to wipe. A fixed allow-list so a
  /// caller can never interpolate an arbitrary table name into the SQL below.
  static const Set<String> resettableTables = {
    'customers',
    'transactions',
    'products',
    'product_variants',
    'categories',
  };

  /// Bulk soft-delete for the Settings → Data reset options. Every live row in
  /// each table is marked deleted + unsynced, so it disappears locally at once
  /// and the ordinary sync push (getPendingDelete*/confirmed cloud delete +
  /// purge) turns each into a real cloud deletion. Works offline: the
  /// tombstones simply wait for reconnect. Reuses the exact per-row mechanism
  /// as single deletes — no direct cloud calls and no change to the sync engine.
  /// Which archive kind each resettable table maps to, so a full reset lands
  /// in the bin under the same kinds an individual delete would use.
  static const Map<String, String> _resetKinds = {
    'transactions': 'transaction',
    'customers': 'customer',
    'products': 'product',
    'product_variants': 'variant',
    'categories': 'category',
  };

  static Future<void> softDeleteAllInTables(List<String> tables) async {
    final database = await db;
    await database.transaction((txn) async {
      for (final t in tables) {
        if (!resettableTables.contains(t)) continue;
        // A reset archives every row it is about to hide, so "Reset All Data"
        // is recoverable too. On a large shop this copies a lot of rows; the
        // 30-day sweep in purgeExpiredBinEntries is what keeps it bounded.
        final kind = _resetKinds[t];
        if (kind != null) {
          await archiveByQuery(txn, kind, t, 'deleted = 0', const [], (r) {
            return (r['name'] ??
                    r['invoice_number'] ??
                    r['label'] ??
                    r['id'] ??
                    '')
                .toString();
          });
        }
        await txn.rawUpdate(
          'UPDATE $t SET deleted = 1, synced = 0, rev = rev + 1 '
          'WHERE deleted = 0',
        );
      }
    });
  }

  // ── Products ──────────────────────────────────────────────────────────────

  static Future<List<Product>> getProducts() async {
    final database = await db;
    final rows = await database.query(
      'products',
      where: 'deleted = 0',
      orderBy: 'name ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  // ── Dealers (local-only directory) ────────────────────────────────────────

  /// One-time-per-name import: any dealer name already typed on a product
  /// becomes a directory entry, so the dropdown starts pre-filled after the
  /// update. Safe to run on every open — existing names are skipped
  /// case-insensitively.
  static Future<void> _seedDealersFromProducts(Database db) async {
    final existing = {
      for (final r in await db.query('dealers', columns: ['name']))
        (r['name'] as String).toLowerCase(),
    };
    final rows = await db.rawQuery(
      "SELECT DISTINCT dealer_name FROM products WHERE dealer_name != '' AND deleted = 0",
    );
    for (final r in rows) {
      final name = (r['dealer_name'] as String).trim();
      if (name.isEmpty || existing.contains(name.toLowerCase())) continue;
      await db.insert('dealers', {
        'id': const Uuid().v4(),
        'name': name,
        'phone': '',
        'notes': '',
        'created_at': DateTime.now().toIso8601String(),
        'deleted': 0,
      });
      existing.add(name.toLowerCase());
    }
  }

  static Future<List<Dealer>> getDealers() async {
    final database = await db;
    final rows = await database.query(
      'dealers',
      where: 'deleted = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Dealer.fromMap).toList();
  }

  static Future<void> insertDealer(Dealer dealer) async {
    final database = await db;
    await database.insert('dealers', {
      ...dealer.toMap(),
      'deleted': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteDealer(String id) async {
    final database = await db;
    await database.update(
      'dealers',
      {'deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> insertProduct(Product product) async {
    final database = await db;
    await database.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Merges cloud products into the local table.
  ///
  /// New products are inserted. Existing ones are refreshed from the cloud
  /// *only* when the local copy has nothing pending — a row with synced = 0 or
  /// deleted = 1 is waiting to be pushed, so overwriting it would silently
  /// throw away the user's unsent edit.
  static Future<void> insertProductsSynced(List<Product> products) async {
    final database = await db;
    // One transaction so the pending-state snapshot and the writes are
    // atomic — an edit or delete tapped mid-merge can't be clobbered.
    await database.transaction((txn) async {
      final existing = {
        for (final r in await txn.query(
          'products',
          columns: ['id', 'synced', 'deleted'],
        ))
          r['id'] as String: (
            synced: (r['synced'] as int?) ?? 1,
            deleted: (r['deleted'] as int?) ?? 0,
          ),
      };
      final batch = txn.batch();
      for (final p in products) {
        final map = p.toMap();
        map['synced'] = 1;
        map['deleted'] = 0;
        final local = existing[p.id];
        if (local == null) {
          batch.insert(
            'products',
            map,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        } else if (local.synced == 1 && local.deleted == 0) {
          // purchase_date is local-only (never stored in the cloud) — keep
          // the local value. barcode_no now syncs, but an empty cloud value
          // must never clobber a locally assigned number.
          map.remove('purchase_date');
          // Local-only alongside it: the cloud never carries this, so its
          // default must not overwrite what this till recorded.
          map.remove('gst_purchase');
          if ((map['barcode_no'] as String? ?? '').isEmpty) {
            map.remove('barcode_no');
          }
          batch.update('products', map, where: 'id = ?', whereArgs: [p.id]);
        }
      }
      await batch.commit(noResult: true);
    });
  }

  static Future<void> updateProductStock(String id, int newStock) async {
    final database = await db;
    // synced = 0 + rev bump so the stock change is pushed and can't be
    // masked by an in-flight sync's mark-synced.
    await database.rawUpdate(
      'UPDATE products SET stock = ?, synced = 0, rev = rev + 1 WHERE id = ?',
      [newStock, id],
    );
  }

  static Future<String> copyImageToAppDir(String sourcePath) async {
    final base = await _appSupportPath();
    final dir = Directory(join(base, 'product_images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = sourcePath.split('.').last.toLowerCase();
    final dest = join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    await File(sourcePath).copy(dest);
    return dest;
  }

  static Future<void> updateProduct(Product p) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE products SET name = ?, price = ?, buying_price = ?, '
      'tax_percent = ?, hsn_code = ?, category = ?, emoji = ?, sku = ?, '
      'stock = ?, description = ?, barcode_no = ?, dealer_name = ?, '
      'purchase_date = ?, synced = 0, rev = rev + 1 WHERE id = ?',
      [
        p.name,
        p.price,
        p.buyingPrice,
        p.taxPercent,
        p.hsnCode,
        p.category,
        p.emoji,
        p.sku,
        p.stock,
        p.description,
        p.barcodeNo,
        p.dealerName,
        p.purchaseDate,
        p.id,
      ],
    );
  }

  static Future<String> getNextBarcodeNo() async {
    final database = await db;
    // Consider both products and variants so numbers never collide
    final rows = await database.rawQuery(
      "SELECT MAX(CAST(barcode_no AS INTEGER)) as m FROM ("
      "SELECT barcode_no FROM products WHERE barcode_no != '' "
      "UNION ALL SELECT barcode_no FROM product_variants WHERE barcode_no != '')",
    );
    final maxVal = rows.first['m'];
    // EAN-13: 12-digit input (200 prefix + 9-digit sequence), library adds check digit
    final next = (maxVal == null ? 200000000000 : (maxVal as int)) + 1;
    return next.toString().padLeft(12, '0');
  }

  static Future<void> assignMissingBarcodeNos() async {
    final database = await db;
    // Only assign to products with a truly empty barcode_no — never overwrite
    // existing. synced = 0 so the assigned number reaches other devices
    // (otherwise each device runs its own sequence and numbers collide).
    final rows = await database.query(
      'products',
      columns: ['id'],
      where: "(barcode_no = '' OR barcode_no IS NULL) AND deleted = 0",
    );
    for (final row in rows) {
      final next = await getNextBarcodeNo();
      await database.rawUpdate(
        'UPDATE products SET barcode_no = ?, synced = 0, rev = rev + 1 '
        "WHERE id = ? AND (barcode_no = '' OR barcode_no IS NULL)",
        [next, row['id']],
      );
    }
  }

  static Future<void> assignMissingVariantBarcodeNos() async {
    final database = await db;
    final rows = await database.query(
      'product_variants',
      columns: ['id'],
      where: "(barcode_no = '' OR barcode_no IS NULL) AND deleted = 0",
    );
    for (final row in rows) {
      final next = await getNextBarcodeNo();
      await database.rawUpdate(
        'UPDATE product_variants SET barcode_no = ?, synced = 0, '
        "rev = rev + 1 WHERE id = ? AND (barcode_no = '' OR barcode_no IS NULL)",
        [next, row['id']],
      );
    }
  }

  static Future<void> deleteProduct(String id) async {
    final database = await db;
    await database.transaction((txn) async {
      // Product and its variants are archived separately, so restoring the
      // product brings back the thing you can sell and each variant can be
      // recovered on its own.
      await archiveByQuery(
        txn,
        'product',
        'products',
        'id = ?',
        [id],
        (r) => (r['name'] ?? '').toString(),
      );
      await archiveByQuery(
        txn,
        'variant',
        'product_variants',
        'product_id = ?',
        [id],
        (r) => (r['label'] ?? '').toString(),
      );
      // Soft-delete: mark for cloud removal, hidden from UI immediately
      await txn.rawUpdate(
        'UPDATE products SET deleted = 1, synced = 0, rev = rev + 1 '
        'WHERE id = ?',
        [id],
      );
      await txn.rawUpdate(
        'UPDATE product_variants SET deleted = 1, synced = 0, rev = rev + 1 '
        'WHERE product_id = ?',
        [id],
      );
    });
  }

  static Future<List<Product>> getUnsyncedProducts() async {
    final database = await db;
    final rows = await database.query(
      'products',
      where: 'synced = 0 AND deleted = 0',
      whereArgs: [],
    );
    return rows.map(Product.fromMap).toList();
  }

  /// Same as [getUnsyncedProducts] but also returns each row's rev from the
  /// SAME query, so the push can mark-synced conditionally on it.
  static Future<(List<Product>, Map<String, int>)>
  getUnsyncedProductsWithRev() async {
    final database = await db;
    final rows = await database.query(
      'products',
      where: 'synced = 0 AND deleted = 0',
    );
    return (
      rows.map(Product.fromMap).toList(),
      {for (final r in rows) r['id'] as String: (r['rev'] as int?) ?? 0},
    );
  }

  /// Marks a row synced ONLY if it hasn't changed since the push snapshot
  /// (rev must match) and hasn't been deleted meanwhile. A row edited or
  /// deleted during the network round trip keeps synced = 0 and is re-pushed
  /// on the next cycle instead of being silently dropped.
  static Future<void> markSyncedIfRev(
    String table,
    String keyColumn,
    Object key,
    int rev,
  ) async {
    final database = await db;
    await database.update(
      table,
      {'synced': 1},
      where: '$keyColumn = ? AND rev = ? AND deleted = 0',
      whereArgs: [key, rev],
    );
  }

  // Products marked deleted locally but not yet removed from Supabase
  static Future<List<String>> getPendingDeleteProductIds() async {
    final database = await db;
    final rows = await database.query(
      'products',
      columns: ['id'],
      where: 'deleted = 1 AND synced = 0',
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  // Call after confirming Supabase deletion — hard-deletes the local row.
  // deleted=1 guard: never purge a row that was revived meanwhile.
  static Future<void> purgeDeletedProduct(String id) async {
    final database = await db;
    await database.delete(
      'products',
      where: 'id = ? AND deleted = 1',
      whereArgs: [id],
    );
  }

  static Future<void> markProductSynced(String id) async {
    final database = await db;
    await database.update(
      'products',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Product Variants ──────────────────────────────────────────────────────

  static Future<List<ProductVariant>> getVariantsForProduct(
    String productId,
  ) async {
    final database = await db;
    final rows = await database.query(
      'product_variants',
      where: 'product_id = ? AND deleted = 0',
      whereArgs: [productId],
      orderBy: 'label ASC',
    );
    return rows.map(ProductVariant.fromMap).toList();
  }

  // Bulk load for the product grid — avoids one query per product.
  static Future<Map<String, List<ProductVariant>>>
  getVariantsGroupedByProduct() async {
    final database = await db;
    final rows = await database.query(
      'product_variants',
      where: 'deleted = 0',
      orderBy: 'label ASC',
    );
    final grouped = <String, List<ProductVariant>>{};
    for (final row in rows) {
      final v = ProductVariant.fromMap(row);
      grouped.putIfAbsent(v.productId, () => []).add(v);
    }
    return grouped;
  }

  static Future<void> insertVariant(ProductVariant variant) async {
    final database = await db;
    await database.insert(
      'product_variants',
      variant.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Same merge rule as [insertProductsSynced]: refresh from the cloud unless
  /// the local row still has unsent changes. Transaction-wrapped so the
  /// pending-state snapshot and the writes are atomic.
  static Future<void> insertVariantsSynced(
    List<ProductVariant> variants,
  ) async {
    final database = await db;
    await database.transaction((txn) async {
      final existing = {
        for (final r in await txn.query(
          'product_variants',
          columns: ['id', 'synced', 'deleted'],
        ))
          r['id'] as String: (
            synced: (r['synced'] as int?) ?? 1,
            deleted: (r['deleted'] as int?) ?? 0,
          ),
      };
      final batch = txn.batch();
      for (final v in variants) {
        final map = v.toMap();
        map['synced'] = 1;
        map['deleted'] = 0;
        final local = existing[v.id];
        if (local == null) {
          batch.insert(
            'product_variants',
            map,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        } else if (local.synced == 1 && local.deleted == 0) {
          batch.update(
            'product_variants',
            map,
            where: 'id = ?',
            whereArgs: [v.id],
          );
        }
      }
      await batch.commit(noResult: true);
    });
  }

  static Future<void> updateVariant(ProductVariant v) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE product_variants SET label = ?, price = ?, buying_price = ?, '
      'stock = ?, sku = ?, barcode_no = ?, synced = 0, rev = rev + 1 '
      'WHERE id = ?',
      [v.label, v.price, v.buyingPrice, v.stock, v.sku, v.barcodeNo, v.id],
    );
  }

  static Future<void> updateVariantStock(String id, int newStock) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE product_variants SET stock = ?, synced = 0, rev = rev + 1 '
      'WHERE id = ?',
      [newStock, id],
    );
  }

  static Future<void> deleteVariant(String id) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE product_variants SET deleted = 1, synced = 0, rev = rev + 1 '
      'WHERE id = ?',
      [id],
    );
  }

  static Future<List<ProductVariant>> getUnsyncedVariants() async {
    final database = await db;
    final rows = await database.query(
      'product_variants',
      where: 'synced = 0 AND deleted = 0',
    );
    return rows.map(ProductVariant.fromMap).toList();
  }

  /// Rev-carrying variant of [getUnsyncedVariants] (same query, see
  /// [getUnsyncedProductsWithRev]).
  static Future<(List<ProductVariant>, Map<String, int>)>
  getUnsyncedVariantsWithRev() async {
    final database = await db;
    final rows = await database.query(
      'product_variants',
      where: 'synced = 0 AND deleted = 0',
    );
    return (
      rows.map(ProductVariant.fromMap).toList(),
      {for (final r in rows) r['id'] as String: (r['rev'] as int?) ?? 0},
    );
  }

  static Future<List<String>> getPendingDeleteVariantIds() async {
    final database = await db;
    final rows = await database.query(
      'product_variants',
      columns: ['id'],
      where: 'deleted = 1 AND synced = 0',
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  static Future<void> purgeDeletedVariant(String id) async {
    final database = await db;
    await database.delete(
      'product_variants',
      where: 'id = ? AND deleted = 1',
      whereArgs: [id],
    );
  }

  static Future<void> markVariantSynced(String id) async {
    final database = await db;
    await database.update(
      'product_variants',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  /// Stock left after selling [quantity] of a row currently holding [raw].
  /// Never below zero, and tolerant of rows that already hold a bad value
  /// (negative, REAL or NULL) — those would otherwise abort a checkout that
  /// had already written its sale row.
  static int _stockAfterSale(Object? raw, int quantity) {
    final current = (raw is num) ? raw.toInt() : 0;
    final updated = current - quantity;
    return updated < 0 ? 0 : updated;
  }

  /// Saves a completed sale: the transaction row, the stock deductions and
  /// the customer auto-save are one atomic unit, so a failure part-way
  /// through leaves NOTHING behind. Previously the sale row committed first
  /// and a later failure stranded a phantom bill that still synced to the
  /// cloud while the on-screen cart never cleared.
  static Future<void> insertTransaction(TransactionRecord t) async {
    final database = await db;
    await database.transaction((txn) async {
      await _writeTransactionRow(txn, t);
      if (t.customerName != null && t.customerName!.isNotEmpty) {
        // Must go through the executor-scoped helper: calling the public
        // method here would grab the outer database handle and deadlock
        // behind this very transaction.
        await _upsertCustomerByPhone(
          txn,
          name: t.customerName!,
          phone: t.customerPhone,
        );
      }
    });
  }

  /// Edits the payment method and/or tax of an already-saved bill. A plain
  /// row update — no stock movement — marked unsynced with a rev bump so it
  /// pushes to the cloud like any other local edit. Moving off hybrid clears
  /// the stored split.
  static Future<void> updateTransactionPaymentAndTax(
    String id, {
    required String paymentMethod,
    required double taxAmount,
    required double total,
  }) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE transactions SET payment_method = ?, tax_amount = ?, total = ?, '
      "hybrid_cash = CASE WHEN ? = 'hybrid' THEN hybrid_cash ELSE 0 END, "
      "hybrid_upi = CASE WHEN ? = 'hybrid' THEN hybrid_upi ELSE 0 END, "
      'synced = 0, rev = rev + 1 WHERE id = ?',
      [paymentMethod, taxAmount, total, paymentMethod, paymentMethod, id],
    );
  }

  /// Records a return or exchange. Identical atomic write to a sale, except
  /// the record's item quantities are negative, so the same arithmetic puts
  /// the goods back into stock instead of taking them out. The customer is
  /// not re-saved: a return is always raised against an existing bill.
  static Future<void> insertReturn(TransactionRecord t) async {
    final database = await db;
    await database.transaction((txn) async {
      await _writeTransactionRow(txn, t);
    });
  }

  /// Records an exchange as ONE atomic unit: the [reversal] (goods coming
  /// back) and the new [sale] (goods going out), each with its stock movement,
  /// commit together or not at all. Without this, a crash between the two
  /// writes could leave the return saved but the new sale lost — a
  /// half-recorded exchange. The customer is auto-saved from the sale, exactly
  /// as [insertTransaction] does.
  static Future<void> insertExchange(
    TransactionRecord reversal,
    TransactionRecord sale,
  ) async {
    final database = await db;
    await database.transaction((txn) async {
      await _writeTransactionRow(txn, reversal);
      await _writeTransactionRow(txn, sale);
      if (sale.customerName != null && sale.customerName!.isNotEmpty) {
        await _upsertCustomerByPhone(
          txn,
          name: sale.customerName!,
          phone: sale.customerPhone,
        );
      }
    });
  }

  /// The row write plus its stock movements, scoped to one transaction.
  static Future<void> _writeTransactionRow(
    DatabaseExecutor txn,
    TransactionRecord t,
  ) async {
    {
      await txn.insert(
        'transactions',
        t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Deduct stock for each sold item and mark product/variant unsynced for cloud push
      for (final item in t.items) {
        if (item.variantId != null) {
          final rows = await txn.query(
            'product_variants',
            where: 'id = ?',
            whereArgs: [item.variantId],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            final updated = _stockAfterSale(
              rows.first['stock'],
              item.quantity,
            );
            await txn.rawUpdate(
              'UPDATE product_variants SET stock = ?, synced = 0, '
              'rev = rev + 1 WHERE id = ?',
              [updated, item.variantId],
            );
          }
          continue;
        }
        final rows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [item.productId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final updated = _stockAfterSale(rows.first['stock'], item.quantity);
          await txn.rawUpdate(
            'UPDATE products SET stock = ?, synced = 0, rev = rev + 1 '
            'WHERE id = ?',
            [updated, item.productId],
          );
        }
      }
    }
  }

  static Future<void> insertTransactionsSynced(
    List<TransactionRecord> txs,
  ) async {
    final database = await db;
    // One transaction so the tombstone snapshot and the REPLACE writes are
    // atomic — a delete tapped mid-merge can't have its tombstone clobbered
    // (which would silently undo the deletion).
    await database.transaction((txn) async {
      // Don't resurrect a row the user just deleted locally but whose cloud
      // deletion hasn't synced yet.
      final pendingDeletes = {
        for (final r in await txn.query(
          'transactions',
          columns: ['id'],
          where: 'deleted = 1',
        ))
          r['id'] as String,
      };
      final batch = txn.batch();
      for (final t in txs) {
        if (pendingDeletes.contains(t.id)) continue;
        final map = t.toMap();
        map['synced'] = 1;
        map['deleted'] = 0;
        batch.insert(
          'transactions',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  static Future<List<TransactionRecord>> getTransactions() async {
    final database = await db;
    final rows = await database.query(
      'transactions',
      where: 'deleted = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  static Future<List<TransactionRecord>> getTransactionsForDate(
    DateTime date,
  ) async {
    final database = await db;
    final prefix =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final rows = await database.query(
      'transactions',
      where: "created_at LIKE ? AND deleted = 0",
      whereArgs: ['$prefix%'],
      orderBy: 'created_at DESC',
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  static Future<List<TransactionRecord>> getTransactionsForRange(
    DateTime from,
    DateTime to,
  ) async {
    final database = await db;
    final f = from.toIso8601String().substring(0, 10);
    final t = to.toIso8601String().substring(0, 10);
    final rows = await database.rawQuery(
      "SELECT * FROM transactions WHERE substr(created_at,1,10) >= ? AND substr(created_at,1,10) <= ? AND deleted = 0 ORDER BY created_at DESC",
      [f, t],
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  static Future<List<TransactionRecord>> getUnsynced() async {
    final database = await db;
    // Exclude soft-deleted rows — those are pushed as deletions, not upserts.
    final rows = await database.query(
      'transactions',
      where: 'synced = 0 AND deleted = 0',
      orderBy: 'created_at ASC',
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  /// Rev-carrying variant of [getUnsynced] (same query, see
  /// [getUnsyncedProductsWithRev]).
  static Future<(List<TransactionRecord>, Map<String, int>)>
  getUnsyncedWithRev() async {
    final database = await db;
    final rows = await database.query(
      'transactions',
      where: 'synced = 0 AND deleted = 0',
      orderBy: 'created_at ASC',
    );
    return (
      rows.map(TransactionRecord.fromMap).toList(),
      {for (final r in rows) r['id'] as String: (r['rev'] as int?) ?? 0},
    );
  }

  static Future<void> markSynced(String id) async {
    final database = await db;
    await database.update(
      'transactions',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Soft-deletes a bill. With [restoreStock], the units it moved are put
  /// back first — the exact inverse of the deduction [_writeTransactionRow]
  /// made when the sale was saved, variant rows included.
  ///
  /// Both happen inside ONE SQLite transaction, so stock can never be
  /// restored against a bill that then fails to delete. The restore is
  /// guarded on the row not already being deleted: adding stock is not
  /// idempotent, and a second delete of the same bill would otherwise put
  /// the units back twice.
  ///
  /// A return or exchange carries NEGATIVE quantities, so the same arithmetic
  /// correctly takes stock back off when one is deleted.
  static Future<void> deleteTransaction(
    String id, {
    bool restoreStock = false,
  }) async {
    final database = await db;
    await database.transaction((txn) async {
      // Archived before the delete, so it can be recovered from the bin.
      await archiveByQuery(txn, 'transaction', 'transactions', 'id = ?', [id], (
        r,
      ) {
        final inv = (r['invoice_number'] ?? '').toString();
        final total = (r['total'] as num?)?.toDouble() ?? 0;
        return inv.isEmpty
            ? 'Bill ${total.toStringAsFixed(2)}'
            : '$inv · ${total.toStringAsFixed(2)}';
      });
      if (restoreStock) {
        final rows = await txn.query(
          'transactions',
          where: 'id = ? AND deleted = 0',
          whereArgs: [id],
          limit: 1,
        );
        // Absent or already deleted: nothing to give back.
        if (rows.isNotEmpty) {
          await _restoreStockForTransaction(
            txn,
            TransactionRecord.fromMap(rows.first),
          );
        }
      }
      // Soft-delete: hide it now, mark for cloud removal. A hard delete alone
      // would be undone by the next pull, which re-downloads it from Supabase.
      await txn.rawUpdate(
        'UPDATE transactions SET deleted = 1, synced = 0, rev = rev + 1 '
        'WHERE id = ?',
        [id],
      );
    });
  }

  /// Adds each sold line's quantity back to its product or variant, mirroring
  /// the deduction in [_writeTransactionRow] line for line — same
  /// variant-before-product branch, same `synced = 0, rev = rev + 1` so the
  /// corrected stock reaches the cloud.
  ///
  /// Note this cannot always be an exact inverse: [_stockAfterSale] clamps at
  /// zero, so selling 5 of a product that had 3 recorded 0 rather than -2,
  /// and giving 5 back leaves 5. That is a pre-existing property of the
  /// deduction, not something the restore can recover.
  static Future<void> _restoreStockForTransaction(
    DatabaseExecutor txn,
    TransactionRecord t,
  ) async {
    for (final item in t.items) {
      if (item.variantId != null) {
        final rows = await txn.query(
          'product_variants',
          where: 'id = ?',
          whereArgs: [item.variantId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final current = (rows.first['stock'] is num)
              ? (rows.first['stock'] as num).toInt()
              : 0;
          final restored = current + item.quantity;
          await txn.rawUpdate(
            'UPDATE product_variants SET stock = ?, synced = 0, '
            'rev = rev + 1 WHERE id = ?',
            [restored < 0 ? 0 : restored, item.variantId],
          );
        }
        continue;
      }
      final rows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [item.productId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final current = (rows.first['stock'] is num)
            ? (rows.first['stock'] as num).toInt()
            : 0;
        final restored = current + item.quantity;
        await txn.rawUpdate(
          'UPDATE products SET stock = ?, synced = 0, rev = rev + 1 '
          'WHERE id = ?',
          [restored < 0 ? 0 : restored, item.productId],
        );
      }
    }
  }

  // Transactions deleted locally but not yet removed from Supabase.
  static Future<List<String>> getPendingDeleteTransactionIds() async {
    final database = await db;
    final rows = await database.query(
      'transactions',
      columns: ['id'],
      where: 'deleted = 1 AND synced = 0',
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  // Call after confirming Supabase deletion — hard-removes the local row.
  static Future<void> purgeDeletedTransaction(String id) async {
    final database = await db;
    await database.delete(
      'transactions',
      where: 'id = ? AND deleted = 1',
      whereArgs: [id],
    );
  }

  // ── Purchases ─────────────────────────────────────────────────────────────
  // Supplier bills. Every write marks the row dirty (synced = 0, rev + 1) the
  // moment it happens, exactly as products and transactions do, so the
  // existing push picks them up without any change to the sync loop.

  static Future<void> insertPurchase(Purchase p) async {
    final database = await db;
    final map = p.toMap();
    map['synced'] = 0;
    map['deleted'] = 0;
    map['rev'] = 0;
    await database.insert(
      'purchases',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updatePurchase(Purchase p) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE purchases SET dealer_id = ?, dealer_name = ?, dealer_gstin = ?, '
      'invoice_no = ?, invoice_date = ?, place_of_supply = ?, '
      'reverse_charge = ?, notes = ?, items = ?, synced = 0, rev = rev + 1 '
      'WHERE id = ?',
      [
        p.dealerId,
        p.dealerName,
        p.dealerGstin,
        p.invoiceNo,
        p.invoiceDate,
        p.placeOfSupply,
        p.reverseCharge ? 1 : 0,
        jsonEncode(p.items.map((i) => i.toMap()).toList()),
        p.id,
      ],
    );
  }

  /// Newest supplier bill first, by the date printed on the invoice.
  static Future<List<Purchase>> getPurchases() async {
    final database = await db;
    final rows = await database.query(
      'purchases',
      where: 'deleted = 0',
      orderBy: 'invoice_date DESC, created_at DESC',
    );
    return rows.map(Purchase.fromMap).toList();
  }

  /// Bills whose INVOICE date falls in the range — the date the register
  /// reports, not the day the row was keyed in.
  static Future<List<Purchase>> getPurchasesForRange(
    DateTime from,
    DateTime to,
  ) async {
    final database = await db;
    final f = from.toIso8601String().substring(0, 10);
    final t = to.toIso8601String().substring(0, 10);
    final rows = await database.rawQuery(
      'SELECT * FROM purchases WHERE substr(invoice_date,1,10) >= ? '
      'AND substr(invoice_date,1,10) <= ? AND deleted = 0 '
      'ORDER BY invoice_date DESC, created_at DESC',
      [f, t],
    );
    return rows.map(Purchase.fromMap).toList();
  }

  /// Soft delete — the tombstone is what tells the cloud to drop the row.
  static Future<void> softDeletePurchase(String id) async {
    final database = await db;
    await database.transaction((txn) async {
      await archiveByQuery(txn, 'purchase', 'purchases', 'id = ?', [id], (r) {
        final inv = (r['invoice_no'] ?? '').toString();
        final dealer = (r['dealer_name'] ?? '').toString();
        return [dealer, inv].where((s) => s.isNotEmpty).join(' · ');
      });
      await txn.rawUpdate(
        'UPDATE purchases SET deleted = 1, synced = 0, rev = rev + 1 '
        'WHERE id = ?',
        [id],
      );
    });
  }

  static Future<(List<Purchase>, Map<String, int>)>
  getUnsyncedPurchasesWithRev() async {
    final database = await db;
    final rows = await database.query(
      'purchases',
      where: 'synced = 0 AND deleted = 0',
      orderBy: 'created_at ASC',
    );
    return (
      rows.map(Purchase.fromMap).toList(),
      {for (final r in rows) r['id'] as String: (r['rev'] as int?) ?? 0},
    );
  }

  static Future<List<String>> getPendingDeletePurchaseIds() async {
    final database = await db;
    final rows = await database.query(
      'purchases',
      columns: ['id'],
      where: 'deleted = 1 AND synced = 0',
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  // Call after confirming Supabase deletion — hard-removes the local row.
  static Future<void> purgeDeletedPurchase(String id) async {
    final database = await db;
    await database.delete(
      'purchases',
      where: 'id = ? AND deleted = 1',
      whereArgs: [id],
    );
  }

  /// Merge cloud rows in. Mirrors [insertTransactionsSynced]: a row the user
  /// just deleted locally is not resurrected while its deletion is still
  /// pending upload.
  static Future<void> insertPurchasesSynced(List<Purchase> purchases) async {
    final database = await db;
    await database.transaction((txn) async {
      final pendingDeletes = {
        for (final r in await txn.query(
          'purchases',
          columns: ['id'],
          where: 'deleted = 1',
        ))
          r['id'] as String,
      };
      final batch = txn.batch();
      for (final p in purchases) {
        if (pendingDeletes.contains(p.id)) continue;
        final map = p.toMap();
        map['synced'] = 1;
        map['deleted'] = 0;
        batch.insert(
          'purchases',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  static Future<void> reconcilePurchasesWithCloud(Set<String> cloudIds) async {
    await reconcileTableWithCloud('purchases', cloudIds);
  }

  // Removes synced transactions that no longer exist in Supabase (cloud is source of truth for deletes)
  static Future<void> reconcileTransactionsWithCloud(
    Set<String> cloudIds,
  ) async {
    await reconcileTableWithCloud('transactions', cloudIds);
  }

  /// Removes local rows (synced = 1 only) that no longer exist in the cloud —
  /// the cloud is the source of truth for deletions done on other devices.
  /// Rows with pending local changes (synced = 0 / deleted = 1) are never
  /// touched. Callers only invoke this after a SUCCESSFUL cloud fetch, so an
  /// empty set is a real "zero rows" state and must reconcile too (otherwise
  /// deleting the last row on one device never propagates to the others).
  static Future<void> reconcileTableWithCloud(
    String table,
    Set<String> cloudIds,
  ) async {
    final database = await db;
    final rows = await database.query(
      table,
      columns: ['id'],
      where: 'synced = 1',
    );
    for (final row in rows) {
      final id = row['id'] as String;
      if (!cloudIds.contains(id)) {
        await database.delete(table, where: 'id = ?', whereArgs: [id]);
      }
    }
  }

  // ── Realtime removals: another device deleted the row in the cloud ────────
  // The cloud row is already gone, so these hard-delete locally (no tombstone).

  static Future<void> removeLocalTransaction(String id) async {
    final database = await db;
    await database.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> removeLocalPurchase(String id) async {
    final database = await db;
    await database.delete('purchases', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> removeLocalProduct(String id) async {
    final database = await db;
    await database.delete('products', where: 'id = ?', whereArgs: [id]);
    // Its variants are deleted separately in the cloud, but clearing them
    // here too is idempotent and keeps the grid consistent immediately.
    await database.delete(
      'product_variants',
      where: 'product_id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> removeLocalVariant(String id) async {
    final database = await db;
    await database.delete('product_variants', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> removeLocalCustomer(String id) async {
    final database = await db;
    await database.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> unsyncedCount() async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT COUNT(*) as count FROM transactions WHERE synced = 0',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  // ── Customers ─────────────────────────────────────────────────────────────

  static Future<void> upsertCustomerByPhone({
    required String name,
    String? phone,
    String? address,
  }) async {
    final database = await db;
    await _upsertCustomerByPhone(
      database,
      name: name,
      phone: phone,
      address: address,
    );
  }

  /// Body of [upsertCustomerByPhone], scoped to whichever executor is passed
  /// so it can also run inside an open transaction (see [insertTransaction]).
  static Future<void> _upsertCustomerByPhone(
    DatabaseExecutor exec, {
    required String name,
    String? phone,
    String? address,
  }) async {
    if (phone != null && phone.isNotEmpty) {
      // Only live rows block a re-add; a pending-delete tombstone with the
      // same phone must not keep the customer "deleted" forever.
      final existing = await exec.query(
        'customers',
        where: 'phone = ? AND deleted = 0',
        whereArgs: [phone],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
    }
    await exec.insert('customers', {
      'id': const Uuid().v4(),
      'name': name,
      'phone': phone ?? '',
      'address': address ?? '',
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
      'deleted': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Merges cloud customers into the local table with the same guard as
  /// products: never overwrite a row with unsent local changes, and never
  /// resurrect one whose deletion hasn't reached the cloud yet.
  /// Transaction-wrapped so the snapshot and writes are atomic.
  static Future<void> insertCustomersSynced(List<Customer> customers) async {
    final database = await db;
    await database.transaction((txn) async {
      final existing = {
        for (final r in await txn.query(
          'customers',
          columns: ['id', 'synced', 'deleted'],
        ))
          r['id'] as String: (
            synced: (r['synced'] as int?) ?? 1,
            deleted: (r['deleted'] as int?) ?? 0,
          ),
      };
      final batch = txn.batch();
      for (final c in customers) {
        final map = c.toMap();
        map['synced'] = 1;
        map['deleted'] = 0;
        final local = existing[c.id];
        if (local == null) {
          batch.insert(
            'customers',
            map,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        } else if (local.synced == 1 && local.deleted == 0) {
          batch.update('customers', map, where: 'id = ?', whereArgs: [c.id]);
        }
      }
      await batch.commit(noResult: true);
    });
  }

  static Future<List<Customer>> getCustomers() async {
    final database = await db;
    final rows = await database.query(
      'customers',
      where: 'deleted = 0',
      orderBy: 'name ASC',
    );
    return rows.map(Customer.fromMap).toList();
  }

  static Future<List<Customer>> getUnsyncedCustomers() async {
    final database = await db;
    final rows = await database.query(
      'customers',
      where: 'synced = 0 AND deleted = 0',
    );
    return rows.map(Customer.fromMap).toList();
  }

  /// Rev-carrying variant of [getUnsyncedCustomers] (same query, see
  /// [getUnsyncedProductsWithRev]).
  static Future<(List<Customer>, Map<String, int>)>
  getUnsyncedCustomersWithRev() async {
    final database = await db;
    final rows = await database.query(
      'customers',
      where: 'synced = 0 AND deleted = 0',
    );
    return (
      rows.map(Customer.fromMap).toList(),
      {for (final r in rows) r['id'] as String: (r['rev'] as int?) ?? 0},
    );
  }

  static Future<void> markCustomerSynced(String id) async {
    final database = await db;
    await database.update(
      'customers',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> deleteCustomer(String id) async {
    final database = await db;
    await database.transaction((txn) async {
      await archiveByQuery(
        txn,
        'customer',
        'customers',
        'id = ?',
        [id],
        (r) => (r['name'] ?? '').toString(),
      );
      // Soft-delete: hidden immediately, pushed as a cloud deletion. A hard
      // delete alone would be undone by the next pull.
      await txn.rawUpdate(
        'UPDATE customers SET deleted = 1, synced = 0, rev = rev + 1 '
        'WHERE id = ?',
        [id],
      );
    });
  }

  // Customers deleted locally but not yet removed from Supabase.
  static Future<List<String>> getPendingDeleteCustomerIds() async {
    final database = await db;
    final rows = await database.query(
      'customers',
      columns: ['id'],
      where: 'deleted = 1 AND synced = 0',
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  // Call after confirming Supabase deletion — hard-removes the local row.
  static Future<void> purgeDeletedCustomer(String id) async {
    final database = await db;
    await database.delete(
      'customers',
      where: 'id = ? AND deleted = 1',
      whereArgs: [id],
    );
  }

  static Future<List<TransactionRecord>> getTransactionsByCustomer(
    String name,
    String? phone,
  ) async {
    final database = await db;
    List<Map<String, dynamic>> rows;
    if (phone != null && phone.isNotEmpty) {
      rows = await database.rawQuery(
        "SELECT * FROM transactions WHERE (customer_name = ? OR customer_phone = ?) AND deleted = 0 ORDER BY created_at DESC",
        [name, phone],
      );
    } else {
      rows = await database.query(
        'transactions',
        where: 'customer_name = ? AND deleted = 0',
        whereArgs: [name],
        orderBy: 'created_at DESC',
      );
    }
    return rows.map(TransactionRecord.fromMap).toList();
  }
}
