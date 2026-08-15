import 'dart:io';
import 'dart:math' show Random;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
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
      'description': 'TEXT NOT NULL DEFAULT ""',
      'barcode_no': "TEXT NOT NULL DEFAULT ''",
      'dealer_name': "TEXT NOT NULL DEFAULT ''",
      'purchase_date': "TEXT NOT NULL DEFAULT ''",
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
  };

  static Future<void> _healSchema(Database db) async {
    // Idempotent: only ever creates what is absent, never rewrites data.
    try {
      await db.execute(_productVariantsTableSql);
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
      version: 17,
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
      },
      onCreate: (db, _) => _createTables(db),
    );
  }

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
        category TEXT NOT NULL,
        emoji TEXT NOT NULL,
        sku TEXT NOT NULL,
        stock INTEGER NOT NULL,
        barcode_no TEXT NOT NULL DEFAULT '',
        dealer_name TEXT NOT NULL DEFAULT '',
        purchase_date TEXT NOT NULL DEFAULT '',
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
        hybrid_upi REAL NOT NULL DEFAULT 0
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
  }

  // ── Invoice ID ───────────────────────────────────────────────────────────

  // Same 8-character format the Mac app issues, so a bill's number looks
  // identical no matter which device rang it up.
  static String generateInvoiceId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
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
  static Future<void> softDeleteAllInTables(List<String> tables) async {
    final database = await db;
    await database.transaction((txn) async {
      for (final t in tables) {
        if (!resettableTables.contains(t)) continue;
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

  static Future<List<String>> getDealerNames() async {
    final database = await db;
    final rows = await database.rawQuery(
      "SELECT DISTINCT dealer_name FROM products WHERE dealer_name != '' AND deleted = 0 ORDER BY dealer_name ASC",
    );
    return rows.map((r) => r['dealer_name'] as String).toList();
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
      'tax_percent = ?, category = ?, emoji = ?, sku = ?, stock = ?, '
      'description = ?, barcode_no = ?, dealer_name = ?, purchase_date = ?, '
      'synced = 0, rev = rev + 1 WHERE id = ?',
      [
        p.name,
        p.price,
        p.buyingPrice,
        p.taxPercent,
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
    // Soft-delete: mark for cloud removal, hidden from UI immediately
    await database.rawUpdate(
      'UPDATE products SET deleted = 1, synced = 0, rev = rev + 1 '
      'WHERE id = ?',
      [id],
    );
    await database.rawUpdate(
      'UPDATE product_variants SET deleted = 1, synced = 0, rev = rev + 1 '
      'WHERE product_id = ?',
      [id],
    );
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

  static Future<void> deleteTransaction(String id) async {
    final database = await db;
    // Soft-delete: hide it now, mark for cloud removal. A hard delete alone
    // would be undone by the next pull, which re-downloads it from Supabase.
    await database.rawUpdate(
      'UPDATE transactions SET deleted = 1, synced = 0, rev = rev + 1 '
      'WHERE id = ?',
      [id],
    );
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
    // Soft-delete: hidden immediately, pushed as a cloud deletion. A hard
    // delete alone would be undone by the next pull.
    await database.rawUpdate(
      'UPDATE customers SET deleted = 1, synced = 0, rev = rev + 1 '
      'WHERE id = ?',
      [id],
    );
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
