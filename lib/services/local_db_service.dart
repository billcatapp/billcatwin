import 'dart:io';
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
    return openDatabase(
      join(dbPath, 'billcat_$userId.db'),
      version: 11,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          try { await db.execute('ALTER TABLE products ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
        }
        if (oldVersion < 5) {
          try { await db.execute('ALTER TABLE products ADD COLUMN buying_price REAL NOT NULL DEFAULT 0'); } catch (_) {}
          try { await db.execute('ALTER TABLE products ADD COLUMN tax_percent REAL NOT NULL DEFAULT 0'); } catch (_) {}
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
          try { await db.execute('ALTER TABLE products ADD COLUMN description TEXT NOT NULL DEFAULT ""'); } catch (_) {}
          try { await db.execute('ALTER TABLE transactions ADD COLUMN invoice_number TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE customers ADD COLUMN address TEXT'); } catch (_) {}
        }
        if (oldVersion < 9) {
          try { await db.execute("ALTER TABLE products ADD COLUMN barcode_no TEXT NOT NULL DEFAULT ''"); } catch (_) {}
        }
        if (oldVersion < 10) {
          try { await db.execute(_productVariantsTableSql); } catch (_) {}
        }
        if (oldVersion < 11) {
          try { await db.execute("ALTER TABLE products ADD COLUMN dealer_name TEXT NOT NULL DEFAULT ''"); } catch (_) {}
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
      deleted INTEGER NOT NULL DEFAULT 0
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
        synced INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0
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
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        created_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE categories (
        name TEXT PRIMARY KEY,
        synced INTEGER NOT NULL DEFAULT 0
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

  static String generateInvoiceId() {
    final now = DateTime.now();
    final prefix = 'INV${now.year % 100}${now.month.toString().padLeft(2, '0')}';
    final suffix = now.millisecondsSinceEpoch.toString().substring(7);
    return '$prefix$suffix';
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  static Future<Map<String, String>> getSettings() async {
    final database = await db;
    final rows = await database.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  static Future<void> saveSettings(Map<String, String> settings) async {
    final database = await db;
    final batch = database.batch();
    for (final e in settings.entries) {
      batch.insert('settings', {'key': e.key, 'value': e.value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ── Categories ────────────────────────────────────────────────────────────

  static Future<List<String>> getCategories() async {
    final database = await db;
    final rows = await database.query('categories', orderBy: 'name ASC');
    return rows.map((r) => r['name'] as String).toList();
  }

  static Future<void> saveCategory(String name) async {
    final database = await db;
    await database.insert('categories', {'name': name, 'synced': 0},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> renameCategory(String oldName, String newName) async {
    final database = await db;
    await database.delete('categories', where: 'name = ?', whereArgs: [oldName]);
    await database.insert('categories', {'name': newName, 'synced': 0},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteCategory(String name) async {
    final database = await db;
    await database.delete('categories', where: 'name = ?', whereArgs: [name]);
  }

  static Future<List<String>> getUnsyncedCategories() async {
    final database = await db;
    final rows = await database.query('categories', where: 'synced = 0');
    return rows.map((r) => r['name'] as String).toList();
  }

  static Future<void> markCategorySynced(String name) async {
    final database = await db;
    await database.update('categories', {'synced': 1},
        where: 'name = ?', whereArgs: [name]);
  }

  static Future<void> insertCategoriesSynced(List<String> names) async {
    final database = await db;
    final batch = database.batch();
    for (final name in names) {
      batch.insert('categories', {'name': name, 'synced': 1},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  // ── Clear all local data (call on logout) ─────────────────────────────────

  static Future<void> clearAll() async {
    final database = await db;
    await database.delete('products');
    await database.delete('product_variants');
    await database.delete('transactions');
    await database.delete('customers');
    await database.delete('categories');
  }

  // ── Products ──────────────────────────────────────────────────────────────

  static Future<List<Product>> getProducts() async {
    final database = await db;
    final rows = await database.query('products',
        where: 'deleted = 0', orderBy: 'name ASC');
    return rows.map(Product.fromMap).toList();
  }

  static Future<void> insertProduct(Product product) async {
    final database = await db;
    await database.insert('products', product.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Merges cloud products into the local table.
  ///
  /// New products are inserted. Existing ones are refreshed from the cloud
  /// *only* when the local copy has nothing pending — a row with synced = 0 or
  /// deleted = 1 is waiting to be pushed, so overwriting it would silently
  /// throw away the user's unsent edit.
  static Future<void> insertProductsSynced(List<Product> products) async {
    final database = await db;
    final existing = {
      for (final r in await database.query('products',
          columns: ['id', 'synced', 'deleted']))
        r['id'] as String: (
          synced: (r['synced'] as int?) ?? 1,
          deleted: (r['deleted'] as int?) ?? 0,
        ),
    };
    final batch = database.batch();
    for (final p in products) {
      final map = p.toMap();
      map['synced'] = 1;
      map['deleted'] = 0;
      final local = existing[p.id];
      if (local == null) {
        batch.insert('products', map,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      } else if (local.synced == 1 && local.deleted == 0) {
        batch.update('products', map, where: 'id = ?', whereArgs: [p.id]);
      }
    }
    await batch.commit(noResult: true);
  }

  static Future<void> updateProductStock(String id, int newStock) async {
    final database = await db;
    await database.update('products', {'stock': newStock},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<String> copyImageToAppDir(String sourcePath) async {
    final base = await _appSupportPath();
    final dir = Directory(join(base, 'product_images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = sourcePath.split('.').last.toLowerCase();
    final dest = join(dir.path, '${DateTime.now().millisecondsSinceEpoch}.$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }

  static Future<void> updateProduct(Product p) async {
    final database = await db;
    await database.update('products', {
      'name': p.name, 'price': p.price, 'buying_price': p.buyingPrice,
      'tax_percent': p.taxPercent, 'category': p.category,
      'emoji': p.emoji, 'sku': p.sku, 'stock': p.stock,
      'description': p.description, 'barcode_no': p.barcodeNo,
      'dealer_name': p.dealerName, 'synced': 0,
    }, where: 'id = ?', whereArgs: [p.id]);
  }

  static Future<String> getNextBarcodeNo() async {
    final database = await db;
    // Consider both products and variants so numbers never collide
    final rows = await database.rawQuery(
      "SELECT MAX(CAST(barcode_no AS INTEGER)) as m FROM ("
      "SELECT barcode_no FROM products WHERE barcode_no != '' "
      "UNION ALL SELECT barcode_no FROM product_variants WHERE barcode_no != '')");
    final maxVal = rows.first['m'];
    // EAN-13: 12-digit input (200 prefix + 9-digit sequence), library adds check digit
    final next = (maxVal == null ? 200000000000 : (maxVal as int)) + 1;
    return next.toString().padLeft(12, '0');
  }

  static Future<void> assignMissingBarcodeNos() async {
    final database = await db;
    // Only assign to products with a truly empty barcode_no — never overwrite existing
    final rows = await database.query('products',
      columns: ['id'], where: "barcode_no = '' OR barcode_no IS NULL");
    for (final row in rows) {
      final next = await getNextBarcodeNo();
      await database.update('products', {'barcode_no': next},
        where: 'id = ?', whereArgs: [row['id']]);
    }
  }

  static Future<void> assignMissingVariantBarcodeNos() async {
    final database = await db;
    final rows = await database.query('product_variants',
      columns: ['id'],
      where: "(barcode_no = '' OR barcode_no IS NULL) AND deleted = 0");
    for (final row in rows) {
      final next = await getNextBarcodeNo();
      await database.update('product_variants', {'barcode_no': next, 'synced': 0},
        where: 'id = ?', whereArgs: [row['id']]);
    }
  }

  static Future<void> deleteProduct(String id) async {
    final database = await db;
    // Soft-delete: mark for cloud removal, hidden from UI immediately
    await database.update('products', {'deleted': 1, 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
    await database.update('product_variants', {'deleted': 1, 'synced': 0},
        where: 'product_id = ?', whereArgs: [id]);
  }

  static Future<List<Product>> getUnsyncedProducts() async {
    final database = await db;
    final rows = await database.query('products',
        where: 'synced = 0 AND deleted = 0', whereArgs: []);
    return rows.map(Product.fromMap).toList();
  }

  // Products marked deleted locally but not yet removed from Supabase
  static Future<List<String>> getPendingDeleteProductIds() async {
    final database = await db;
    final rows = await database.query('products',
        columns: ['id'], where: 'deleted = 1 AND synced = 0');
    return rows.map((r) => r['id'] as String).toList();
  }

  // Call after confirming Supabase deletion — hard-deletes the local row
  static Future<void> purgeDeletedProduct(String id) async {
    final database = await db;
    await database.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> markProductSynced(String id) async {
    final database = await db;
    await database.update('products', {'synced': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  // ── Product Variants ──────────────────────────────────────────────────────

  static Future<List<ProductVariant>> getVariantsForProduct(String productId) async {
    final database = await db;
    final rows = await database.query('product_variants',
        where: 'product_id = ? AND deleted = 0', whereArgs: [productId],
        orderBy: 'label ASC');
    return rows.map(ProductVariant.fromMap).toList();
  }

  // Bulk load for the product grid — avoids one query per product.
  static Future<Map<String, List<ProductVariant>>> getVariantsGroupedByProduct() async {
    final database = await db;
    final rows = await database.query('product_variants',
        where: 'deleted = 0', orderBy: 'label ASC');
    final grouped = <String, List<ProductVariant>>{};
    for (final row in rows) {
      final v = ProductVariant.fromMap(row);
      grouped.putIfAbsent(v.productId, () => []).add(v);
    }
    return grouped;
  }

  static Future<void> insertVariant(ProductVariant variant) async {
    final database = await db;
    await database.insert('product_variants', variant.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Same merge rule as [insertProductsSynced]: refresh from the cloud unless
  /// the local row still has unsent changes.
  static Future<void> insertVariantsSynced(List<ProductVariant> variants) async {
    final database = await db;
    final existing = {
      for (final r in await database.query('product_variants',
          columns: ['id', 'synced', 'deleted']))
        r['id'] as String: (
          synced: (r['synced'] as int?) ?? 1,
          deleted: (r['deleted'] as int?) ?? 0,
        ),
    };
    final batch = database.batch();
    for (final v in variants) {
      final map = v.toMap();
      map['synced'] = 1;
      map['deleted'] = 0;
      final local = existing[v.id];
      if (local == null) {
        batch.insert('product_variants', map,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      } else if (local.synced == 1 && local.deleted == 0) {
        batch.update('product_variants', map,
            where: 'id = ?', whereArgs: [v.id]);
      }
    }
    await batch.commit(noResult: true);
  }

  static Future<void> updateVariant(ProductVariant v) async {
    final database = await db;
    await database.update('product_variants', {
      'label': v.label, 'price': v.price, 'buying_price': v.buyingPrice,
      'stock': v.stock, 'sku': v.sku, 'barcode_no': v.barcodeNo, 'synced': 0,
    }, where: 'id = ?', whereArgs: [v.id]);
  }

  static Future<void> updateVariantStock(String id, int newStock) async {
    final database = await db;
    await database.update('product_variants', {'stock': newStock, 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteVariant(String id) async {
    final database = await db;
    await database.update('product_variants', {'deleted': 1, 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<ProductVariant>> getUnsyncedVariants() async {
    final database = await db;
    final rows = await database.query('product_variants',
        where: 'synced = 0 AND deleted = 0');
    return rows.map(ProductVariant.fromMap).toList();
  }

  static Future<List<String>> getPendingDeleteVariantIds() async {
    final database = await db;
    final rows = await database.query('product_variants',
        columns: ['id'], where: 'deleted = 1 AND synced = 0');
    return rows.map((r) => r['id'] as String).toList();
  }

  static Future<void> purgeDeletedVariant(String id) async {
    final database = await db;
    await database.delete('product_variants', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> markVariantSynced(String id) async {
    final database = await db;
    await database.update('product_variants', {'synced': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  static Future<void> insertTransaction(TransactionRecord t) async {
    final database = await db;
    await database.insert('transactions', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    // Deduct stock for each sold item and mark product/variant unsynced for cloud push
    for (final item in t.items) {
      if (item.variantId != null) {
        final rows = await database.query('product_variants',
            where: 'id = ?', whereArgs: [item.variantId], limit: 1);
        if (rows.isNotEmpty) {
          final current = rows.first['stock'] as int;
          final updated = (current - item.quantity).clamp(0, current);
          await database.update(
            'product_variants',
            {'stock': updated, 'synced': 0},
            where: 'id = ?',
            whereArgs: [item.variantId],
          );
        }
        continue;
      }
      final rows = await database.query('products',
          where: 'id = ?', whereArgs: [item.productId], limit: 1);
      if (rows.isNotEmpty) {
        final current = rows.first['stock'] as int;
        final updated = (current - item.quantity).clamp(0, current);
        await database.update(
          'products',
          {'stock': updated, 'synced': 0},
          where: 'id = ?',
          whereArgs: [item.productId],
        );
      }
    }
    if (t.customerName != null && t.customerName!.isNotEmpty) {
      await upsertCustomerByPhone(name: t.customerName!, phone: t.customerPhone);
    }
  }

  static Future<void> insertTransactionsSynced(List<TransactionRecord> txs) async {
    final database = await db;
    final batch = database.batch();
    for (final t in txs) {
      final map = t.toMap();
      map['synced'] = 1;
      batch.insert('transactions', map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<TransactionRecord>> getTransactions() async {
    final database = await db;
    final rows = await database.query('transactions', orderBy: 'created_at DESC');
    return rows.map(TransactionRecord.fromMap).toList();
  }

  static Future<List<TransactionRecord>> getTransactionsForDate(DateTime date) async {
    final database = await db;
    final prefix = '${date.year.toString().padLeft(4,'0')}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
    final rows = await database.query('transactions',
        where: "created_at LIKE ?", whereArgs: ['$prefix%'],
        orderBy: 'created_at DESC');
    return rows.map(TransactionRecord.fromMap).toList();
  }

  static Future<List<TransactionRecord>> getTransactionsForRange(
      DateTime from, DateTime to) async {
    final database = await db;
    final f = from.toIso8601String().substring(0, 10);
    final t = to.toIso8601String().substring(0, 10);
    final rows = await database.rawQuery(
      "SELECT * FROM transactions WHERE substr(created_at,1,10) >= ? AND substr(created_at,1,10) <= ? ORDER BY created_at DESC",
      [f, t],
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  static Future<List<TransactionRecord>> getUnsynced() async {
    final database = await db;
    final rows = await database.query('transactions',
        where: 'synced = ?', whereArgs: [0], orderBy: 'created_at ASC');
    return rows.map(TransactionRecord.fromMap).toList();
  }

  static Future<void> markSynced(String id) async {
    final database = await db;
    await database.update('transactions', {'synced': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteTransaction(String id) async {
    final database = await db;
    await database.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // Removes synced transactions that no longer exist in Supabase (cloud is source of truth for deletes)
  static Future<void> reconcileTransactionsWithCloud(Set<String> cloudIds) async {
    if (cloudIds.isEmpty) return;
    final database = await db;
    final rows = await database.query('transactions', columns: ['id'], where: 'synced = 1');
    for (final row in rows) {
      final id = row['id'] as String;
      if (!cloudIds.contains(id)) {
        await database.delete('transactions', where: 'id = ?', whereArgs: [id]);
      }
    }
  }

  static Future<int> unsyncedCount() async {
    final database = await db;
    final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM transactions WHERE synced = 0');
    return (result.first['count'] as int?) ?? 0;
  }

  // ── Customers ─────────────────────────────────────────────────────────────

  static Future<void> upsertCustomerByPhone({
    required String name,
    String? phone,
    String? address,
  }) async {
    final database = await db;
    if (phone != null && phone.isNotEmpty) {
      final existing = await database.query('customers',
          where: 'phone = ?', whereArgs: [phone], limit: 1);
      if (existing.isNotEmpty) return;
    }
    await database.insert('customers', {
      'id': const Uuid().v4(),
      'name': name,
      'phone': phone ?? '',
      'address': address ?? '',
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> insertCustomersSynced(List<Customer> customers) async {
    final database = await db;
    final batch = database.batch();
    for (final c in customers) {
      final map = c.toMap();
      map['synced'] = 1;
      batch.insert('customers', map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Customer>> getCustomers() async {
    final database = await db;
    final rows = await database.query('customers', orderBy: 'name ASC');
    return rows.map(Customer.fromMap).toList();
  }

  static Future<List<Customer>> getUnsyncedCustomers() async {
    final database = await db;
    final rows = await database.query('customers',
        where: 'synced = ?', whereArgs: [0]);
    return rows.map(Customer.fromMap).toList();
  }

  static Future<void> markCustomerSynced(String id) async {
    final database = await db;
    await database.update('customers', {'synced': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteCustomer(String id) async {
    final database = await db;
    await database.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<TransactionRecord>> getTransactionsByCustomer(String name, String? phone) async {
    final database = await db;
    List<Map<String, dynamic>> rows;
    if (phone != null && phone.isNotEmpty) {
      rows = await database.rawQuery(
        "SELECT * FROM transactions WHERE customer_name = ? OR customer_phone = ? ORDER BY created_at DESC",
        [name, phone],
      );
    } else {
      rows = await database.query('transactions',
          where: 'customer_name = ?', whereArgs: [name],
          orderBy: 'created_at DESC');
    }
    return rows.map(TransactionRecord.fromMap).toList();
  }
}
