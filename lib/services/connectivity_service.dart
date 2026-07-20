import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../models/transaction_record.dart';
import 'local_db_service.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._();
  static ConnectivityService get instance => _instance;
  ConnectivityService._();

  bool _isOnline = true;
  bool _isSyncing = false;

  bool get isOnline => _isOnline;

  StreamSubscription? _sub;

  Future<void> init() async {
    final result = await Connectivity().checkConnectivity();
    _isOnline = _hasConnection(result);

    _sub = Connectivity().onConnectivityChanged.listen((results) async {
      final online = _hasConnection(results);
      if (online && !_isOnline) {
        _isOnline = true;
        _syncAll();
      } else {
        _isOnline = online;
      }
    });
  }

  bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  Future<void> _syncAll() async {
    if (_isSyncing) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _isSyncing = true;
    try {
      final client = Supabase.instance.client;

      // ── Sync product deletions ───────────────────────────────────────────
      final pendingDeletes = await LocalDbService.getPendingDeleteProductIds();
      if (pendingDeletes.isNotEmpty) {
        try {
          await client.from('products')
              .delete()
              .inFilter('id', pendingDeletes)
              .eq('user_id', userId);
          for (final id in pendingDeletes) {
            await LocalDbService.purgeDeletedProduct(id);
          }
        } catch (e) {
          debugPrint('Product delete sync error: $e');
        }
      }

      // ── Sync products (batch) ────────────────────────────────────────────
      final unsyncedProducts = await LocalDbService.getUnsyncedProducts();
      if (unsyncedProducts.isNotEmpty) {
        try {
          await client.from('products').upsert(
            unsyncedProducts.map((p) => {
              'id': p.id,
              'user_id': userId,
              'name': p.name,
              'price': p.price,
              'buying_price': p.buyingPrice,
              'tax_percent': p.taxPercent,
              'category': p.category,
              'emoji': p.emoji,
              'sku': p.sku,
              'stock': p.stock,
              'description': p.description,
            }).toList(),
          );
          for (final p in unsyncedProducts) {
            await LocalDbService.markProductSynced(p.id);
          }
          debugPrint('PUSH: products ok (${unsyncedProducts.length} rows)');
        } catch (e) {
          debugPrint('Product sync error: $e');
        }
      }

      // ── Sync product variant deletions ───────────────────────────────────
      final pendingVariantDeletes = await LocalDbService.getPendingDeleteVariantIds();
      if (pendingVariantDeletes.isNotEmpty) {
        try {
          await client.from('product_variants')
              .delete()
              .inFilter('id', pendingVariantDeletes)
              .eq('user_id', userId);
          for (final id in pendingVariantDeletes) {
            await LocalDbService.purgeDeletedVariant(id);
          }
        } catch (e) {
          debugPrint('Variant delete sync error: $e');
        }
      }

      // ── Sync product variants (batch) ────────────────────────────────────
      final unsyncedVariants = await LocalDbService.getUnsyncedVariants();
      if (unsyncedVariants.isNotEmpty) {
        try {
          await client.from('product_variants').upsert(
            unsyncedVariants.map((v) => {
              'id': v.id,
              'user_id': userId,
              'product_id': v.productId,
              'label': v.label,
              'price': v.price,
              'buying_price': v.buyingPrice,
              'stock': v.stock,
              'sku': v.sku,
              'barcode_no': v.barcodeNo,
            }).toList(),
          );
          for (final v in unsyncedVariants) {
            await LocalDbService.markVariantSynced(v.id);
          }
          debugPrint('PUSH: product_variants ok (${unsyncedVariants.length} rows)');
        } catch (e) {
          debugPrint('Variant sync error: $e');
        }
      }

      // ── Sync transactions (batch) ────────────────────────────────────────
      final unsyncedTx = await LocalDbService.getUnsynced();
      if (unsyncedTx.isNotEmpty) {
        try {
          await client.from('transactions').upsert(
            unsyncedTx.map((t) => {
              'id': t.id,
              'user_id': userId,
              'customer_name': t.customerName,
              'customer_phone': t.customerPhone,
              'subtotal': t.subtotal,
              'discount_amount': t.discountAmount,
              'tax_amount': t.taxAmount,
              'total': t.total,
              'payment_method': t.paymentMethod,
              'created_at': t.createdAt.toIso8601String(),
              'items': t.items.map((i) => i.toMap()).toList(),
              'invoice_number': t.invoiceNumber,
            }).toList(),
          );
          for (final t in unsyncedTx) {
            await LocalDbService.markSynced(t.id);
          }
        } catch (e) {
          debugPrint('Transaction sync error: $e');
        }
      }

      // ── Sync customers (batch) ───────────────────────────────────────────
      final unsyncedCustomers = await LocalDbService.getUnsyncedCustomers();
      if (unsyncedCustomers.isNotEmpty) {
        try {
          await client.from('customers').upsert(
            unsyncedCustomers.map((c) => {
              'id': c.id,
              'user_id': userId,
              'name': c.name,
              'phone': c.phone,
              'created_at': c.createdAt.toIso8601String(),
            }).toList(),
          );
          for (final c in unsyncedCustomers) {
            await LocalDbService.markCustomerSynced(c.id);
          }
          debugPrint('PUSH: customers ok (${unsyncedCustomers.length} rows)');
        } catch (e) {
          debugPrint('Customer sync error: $e');
        }
      }

      // ── Sync categories ──────────────────────────────────────────────────
      final unsyncedCats = await LocalDbService.getUnsyncedCategories();
      if (unsyncedCats.isNotEmpty) {
        try {
          await client.from('user_categories').upsert(
            unsyncedCats.map((name) => {'user_id': userId, 'name': name}).toList(),
          );
          for (final name in unsyncedCats) {
            await LocalDbService.markCategorySynced(name);
          }
        } catch (e) {
          debugPrint('Category sync error: $e');
        }
      }

      // ── Sync settings ────────────────────────────────────────────────────
      // Business-level settings that should follow the account across devices.
      // Device-specific ones (printer, paper size, orientation, logo_path) are
      // deliberately excluded so one machine can't override another's setup.
      // Requires database/add_settings_columns.sql for the last three.
      const knownSettingsCols = {
        'store_name', 'store_address', 'store_phone', 'store_email', 'store_gstin',
        'receipt_footer', 'tax_label', 'tax_rate', 'currency_code', 'currency_symbol',
        'invoice_layout', 'store_terms', 'store_upi_id', 'branch_number', 'logo_url',
        'wa_access_token', 'wa_phone_number_id', 'auto_print',
      };
      final settings = await LocalDbService.getSettings();
      if (settings.isNotEmpty) {
        try {
          final filtered = Map.fromEntries(
            settings.entries.where((e) => knownSettingsCols.contains(e.key)),
          );
          if (filtered.isNotEmpty) {
            await client.from('user_settings').upsert({
              'user_id': userId,
              ...filtered,
            });
          }
        } catch (e) {
          debugPrint('Settings sync error: $e');
        }
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> syncNow() => _syncAll();
  Future<void> refreshUnsyncedCount() async {}

  Future<void> pullFromCloud() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('PULL: skipped — no logged-in user');
      return;
    }
    debugPrint('PULL: starting for user $userId');
    final client = Supabase.instance.client;
    try {
      final productRows = await client
          .from('products')
          .select()
          .eq('user_id', userId);
      final products = (productRows as List)
          .map((r) => Product.fromMap({
                'id': r['id'],
                'name': r['name'],
                'price': (r['price'] as num).toDouble(),
                'buying_price': (r['buying_price'] as num?)?.toDouble() ?? 0.0,
                'tax_percent': (r['tax_percent'] as num?)?.toDouble() ?? 0.0,
                'category': r['category'],
                'emoji': r['emoji'],
                'sku': r['sku'],
                'stock': r['stock'],
                'description': (r['description'] as String?) ?? '',
                'synced': 1,
              }))
          .toList();
      await LocalDbService.insertProductsSynced(products);
      debugPrint('PULL: products ok (${products.length} rows)');
    } catch (e) {
      debugPrint('PULL: products FAILED: $e');
    }

    try {
      final variantRows = await client
          .from('product_variants')
          .select()
          .eq('user_id', userId);
      final variants = (variantRows as List)
          .map((r) => ProductVariant.fromMap({
                'id': r['id'],
                'product_id': r['product_id'],
                'label': r['label'],
                'price': (r['price'] as num).toDouble(),
                'buying_price': (r['buying_price'] as num?)?.toDouble() ?? 0.0,
                'stock': r['stock'],
                'sku': (r['sku'] as String?) ?? '',
                'barcode_no': (r['barcode_no'] as String?) ?? '',
              }))
          .toList();
      await LocalDbService.insertVariantsSynced(variants);
      debugPrint('PULL: product_variants ok (${variants.length} rows)');
    } catch (e) {
      debugPrint('PULL: product_variants FAILED: $e');
    }

    try {
      final txRows = await client
          .from('transactions')
          .select()
          .eq('user_id', userId);
      final txs = (txRows as List)
          .map((r) => TransactionRecord(
                id: r['id'],
                customerName: r['customer_name'],
                customerPhone: r['customer_phone'],
                items: (r['items'] as List)
                    .map((i) => TransactionItem.fromMap(
                          Map<String, dynamic>.from(i as Map),
                        ))
                    .toList(),
                subtotal: (r['subtotal'] as num).toDouble(),
                discountAmount: (r['discount_amount'] as num).toDouble(),
                taxAmount: (r['tax_amount'] as num).toDouble(),
                total: (r['total'] as num).toDouble(),
                paymentMethod: r['payment_method'],
                createdAt: DateTime.parse(r['created_at']),
              ))
          .toList();
      await LocalDbService.insertTransactionsSynced(txs);
      await LocalDbService.reconcileTransactionsWithCloud(txs.map((t) => t.id).toSet());
      debugPrint('PULL: transactions ok (${txs.length} rows)');
    } catch (e) {
      debugPrint('PULL: transactions FAILED: $e');
    }

    try {
      final custRows = await client
          .from('customers')
          .select()
          .eq('user_id', userId);
      final customers = (custRows as List)
          .map((r) => Customer(
                id: r['id'],
                name: r['name'],
                phone: r['phone'],
                createdAt: DateTime.parse(r['created_at']),
                synced: true,
              ))
          .toList();
      await LocalDbService.insertCustomersSynced(customers);
      debugPrint('PULL: customers ok (${customers.length} rows)');
    } catch (e) {
      debugPrint('PULL: customers FAILED: $e');
    }

    try {
      final catRows = await client
          .from('user_categories')
          .select()
          .eq('user_id', userId);
      final cats = (catRows as List).map((r) => r['name'] as String).toList();
      await LocalDbService.insertCategoriesSynced(cats);
      debugPrint('PULL: categories ok (${cats.length} rows)');
    } catch (e) {
      debugPrint('PULL: categories FAILED: $e');
    }

    try {
      final settingsRow = await client
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (settingsRow != null) {
        final map = Map<String, dynamic>.from(settingsRow as Map);
        map.remove('user_id');
        // Only save non-null, non-empty values — avoids wiping local fields
        // that aren't yet in the cloud schema
        final settings = Map<String, String>.fromEntries(
          map.entries
              .where((e) => e.value != null && e.value.toString().isNotEmpty)
              .map((e) => MapEntry(e.key, e.value.toString())),
        );
        if (settings.isNotEmpty) await LocalDbService.saveSettings(settings);
      }
      debugPrint('PULL: settings ok');
    } catch (e) {
      debugPrint('PULL: settings FAILED: $e');
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
