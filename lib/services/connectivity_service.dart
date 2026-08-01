import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../models/transaction_record.dart';
import 'local_db_service.dart';

/// Offline-first sync engine.
///
/// Data flow:
///  1. Every local add / edit / delete marks its row in SQLite
///     (synced = 0, or deleted = 1 for removals) and bumps its rev counter
///     the moment it happens.
///  2. [syncNow] pushes those pending rows to Supabase immediately. Awaiting
///     it always means "my pending work is pushed": concurrent calls join the
///     in-flight run (which re-runs once more if anything new arrived).
///  3. Other devices receive the change over a Supabase Realtime channel and
///     apply just that row to their local DB within ~1–2 s. No polling wait.
///  4. Changes made offline stay queued locally; the moment connectivity
///     returns they are pushed, then a full pull + realtime resubscribe
///     reconciles anything missed while offline.
///  5. A periodic pull remains as a safety net: fast (15 s) while the
///     realtime channel is down, slow (3 min) while it is live.
///
/// Correctness invariants (enforced here + in LocalDbService):
///  - Push and pull never run concurrently (serialized on one chain), so a
///    pull's reconcile can never delete rows a concurrent push just synced.
///  - A row is marked synced ONLY if its rev is unchanged since the push
///    snapshot — an edit or delete made during the network round trip stays
///    queued instead of being silently dropped.
///  - Delete tombstones are purged ONLY after the cloud confirms the row was
///    removed (.delete()...select() returns it).
///  - Settings push only when locally edited (dirty token), and a pull never
///    overwrites settings while local edits are pending.
///  - Every per-table step re-checks the signed-in user, so a sync that spans
///    a logout/login can never mix two accounts' data.
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._();
  static ConnectivityService get instance => _instance;
  ConnectivityService._();

  bool _isOnline = true;
  bool _isSyncing = false;
  bool _resyncRequested = false;
  bool _realtimeLive = false;

  bool get isOnline => _isOnline;
  bool get isRealtimeLive => _realtimeLive;

  StreamSubscription? _sub;
  Timer? _pollTimer;
  RealtimeChannel? _channel;
  Timer? _realtimeRetryTimer;
  int _realtimeRetrySecs = 2;

  /// Serialization chain: push and pull are queued here so they never
  /// interleave (see class doc).
  Future<void> _chain = Future.value();

  /// The in-flight syncNow loop, joined by concurrent callers.
  Future<void>? _syncLoop;

  /// While a pull is in flight, realtime upserts record their ids here so the
  /// pull's reconcile (built from an older cloud snapshot) doesn't delete
  /// rows that arrived live mid-pull.
  bool _pullInFlight = false;
  final Map<String, Set<String>> _liveIdsDuringPull = {};

  /// Account-level settings that sync across devices. Everything else
  /// (selected printer, paper size, orientation, auto-print, logo_path,
  /// print-dialog toggles...) is DEVICE-SPECIFIC and must never be pushed to
  /// or pulled from the cloud — an unfiltered pull let one machine's paper
  /// size silently overwrite another's thermal setup. Both the push and the
  /// pull filter on this same set.
  static const Set<String> _syncedSettingsCols = {
    'store_name',
    'store_address',
    'store_phone',
    'store_email',
    'store_gstin',
    'receipt_footer',
    'tax_label',
    'tax_rate',
    'currency_code',
    'currency_symbol',
    'invoice_layout',
    'store_terms',
    'store_upi_id',
    'branch_number',
    'logo_url',
    'wa_access_token',
    'wa_phone_number_id',
  };

  /// Fallback pull cadence while the realtime channel is down.
  static const Duration _pullFast = Duration(seconds: 15);

  /// Reconciliation pull cadence while realtime is live (safety net for any
  /// event the socket might have missed).
  static const Duration _pullSlow = Duration(minutes: 3);

  Future<void> init() async {
    final result = await Connectivity().checkConnectivity();
    _isOnline = _hasConnection(result);

    _sub = Connectivity().onConnectivityChanged.listen((results) async {
      final online = _hasConnection(results);
      if (online && !_isOnline) {
        _isOnline = true;
        notifyListeners();
        // Push everything done offline, pull what other devices did while we
        // were away, then re-open the live channel. syncNow's completion now
        // genuinely means "pushed", so this ordering holds even if a sync was
        // already mid-flight when connectivity returned.
        await syncNow();
        await pullFromCloud();
        _subscribeRealtime();
      } else if (!online && _isOnline) {
        _isOnline = false;
        _teardownRealtime();
        notifyListeners();
      }
    });

    _subscribeRealtime();
    startPeriodicPull();
  }

  /// Call when the signed-in user changes (login / logout): drops the old
  /// user's channel and opens one for the new user, if any.
  Future<void> onUserChanged() async {
    _teardownRealtime();
    _subscribeRealtime();
  }

  void startPeriodicPull() => _restartPollTimer();

  void stopPeriodicPull() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _restartPollTimer() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_realtimeLive ? _pullSlow : _pullFast, (
      _,
    ) async {
      if (!_isOnline || _isSyncing) return;
      if (Supabase.instance.client.auth.currentUser == null) return;
      try {
        // Push first so our pending work is never older than what we pull.
        await syncNow();
        await pullFromCloud();
      } catch (e) {
        debugPrint('Periodic sync failed: $e');
      }
    });
  }

  bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  /// True when [userId] is no longer the signed-in user — a sync that spans a
  /// logout/login must stop touching the (now different) local DB and cloud.
  bool _staleUser(String userId) =>
      Supabase.instance.client.auth.currentUser?.id != userId;

  /// Queue [op] on the serialization chain (push/pull mutual exclusion).
  Future<void> _serial(Future<void> Function() op) {
    final run = _chain.then((_) => op());
    _chain = run.catchError((_) {});
    return run;
  }

  // ── Realtime: live change feed from other devices ──────────────────────────

  void _noteLiveRow(String table, String id) {
    if (_pullInFlight) {
      (_liveIdsDuringPull[table] ??= <String>{}).add(id);
    }
  }

  void _subscribeRealtime() {
    _realtimeRetryTimer?.cancel();
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null || !_isOnline) return;

    _teardownRealtime();

    final channel = client.channel('billcat-sync-$userId');

    // INSERT/UPDATE carry the full new row and can be server-filtered by
    // user_id. DELETE payloads carry only the primary key (no user_id), so
    // they cannot be filtered — we apply by id, and an id belonging to some
    // other user simply matches nothing locally.
    void bind(
      String table, {
      required void Function(Map<String, dynamic> row) onUpsert,
      void Function(Map<String, dynamic> oldRow)? onDelete,
    }) {
      for (final event in const [
        PostgresChangeEvent.insert,
        PostgresChangeEvent.update,
      ]) {
        channel.onPostgresChanges(
          event: event,
          schema: 'public',
          table: table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) =>
              _applyGuarded(table, () async => onUpsert(payload.newRecord)),
        );
      }
      if (onDelete != null) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: table,
          callback: (payload) =>
              _applyGuarded(table, () async => onDelete(payload.oldRecord)),
        );
      }
    }

    bind(
      'transactions',
      onUpsert: (row) async {
        final tx = _txFromRow(row);
        await LocalDbService.insertTransactionsSynced([tx]);
        _noteLiveRow('transactions', tx.id);
        notifyListeners();
      },
      onDelete: (old) async {
        final id = old['id'] as String?;
        if (id == null) return;
        await LocalDbService.removeLocalTransaction(id);
        notifyListeners();
      },
    );

    bind(
      'products',
      onUpsert: (row) async {
        final p = _productFromRow(row);
        await LocalDbService.insertProductsSynced([p]);
        _noteLiveRow('products', p.id);
        notifyListeners();
      },
      onDelete: (old) async {
        final id = old['id'] as String?;
        if (id == null) return;
        await LocalDbService.removeLocalProduct(id);
        notifyListeners();
      },
    );

    bind(
      'product_variants',
      onUpsert: (row) async {
        final v = _variantFromRow(row);
        await LocalDbService.insertVariantsSynced([v]);
        _noteLiveRow('product_variants', v.id);
        notifyListeners();
      },
      onDelete: (old) async {
        final id = old['id'] as String?;
        if (id == null) return;
        await LocalDbService.removeLocalVariant(id);
        notifyListeners();
      },
    );

    bind(
      'customers',
      onUpsert: (row) async {
        final c = _customerFromRow(row);
        await LocalDbService.insertCustomersSynced([c]);
        _noteLiveRow('customers', c.id);
        notifyListeners();
      },
      onDelete: (old) async {
        final id = old['id'] as String?;
        if (id == null) return;
        await LocalDbService.removeLocalCustomer(id);
        notifyListeners();
      },
    );

    // Low-traffic tables: any change (including deletes, whose payloads may
    // not carry the name) just re-pulls that one table; the pull reconciles
    // removals too.
    bind(
      'user_categories',
      onUpsert: (_) async {
        await _pullCategories(client, userId);
        notifyListeners();
      },
      onDelete: (_) async {
        await _pullCategories(client, userId);
        notifyListeners();
      },
    );
    bind(
      'user_settings',
      onUpsert: (_) async {
        await _pullSettings(client, userId);
        notifyListeners();
      },
    );

    channel.subscribe((status, [error]) {
      // A channel we replaced fires 'closed' during teardown — ignore events
      // from anything that is no longer the current channel, or the retry it
      // schedules would tear down its healthy replacement forever.
      if (!identical(channel, _channel)) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        final wasLive = _realtimeLive;
        _realtimeLive = true;
        _realtimeRetrySecs = 2;
        _realtimeRetryTimer?.cancel();
        _realtimeRetryTimer = null;
        _restartPollTimer();
        debugPrint('REALTIME: live');
        // Catch up on anything that happened while the channel was down.
        if (!wasLive) pullFromCloud();
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.timedOut) {
        final wasLive = _realtimeLive;
        _realtimeLive = false;
        if (wasLive) _restartPollTimer();
        debugPrint(
          'REALTIME: down ($status${error == null ? '' : ' $error'}) — '
          'retrying in ${_realtimeRetrySecs}s, polling every '
          '${_pullFast.inSeconds}s meanwhile',
        );
        _scheduleRealtimeRetry();
      }
    });
    _channel = channel;
  }

  void _scheduleRealtimeRetry() {
    _realtimeRetryTimer?.cancel();
    _realtimeRetryTimer = Timer(Duration(seconds: _realtimeRetrySecs), () {
      _realtimeRetrySecs = (_realtimeRetrySecs * 2).clamp(2, 30);
      _subscribeRealtime();
    });
  }

  void _teardownRealtime() {
    _realtimeLive = false;
    _realtimeRetryTimer?.cancel();
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }
  }

  void _applyGuarded(String table, Future<void> Function() fn) {
    fn().catchError((e) => debugPrint('REALTIME apply ($table) error: $e'));
  }

  // ── Push: upload local pending changes ─────────────────────────────────────

  /// Push all pending local changes now. Awaiting this ALWAYS means the
  /// pending work present at call time has been attempted: concurrent calls
  /// join the in-flight run, which re-runs once more when anything new
  /// arrived while it was pushing.
  Future<void> syncNow() {
    final inFlight = _syncLoop;
    if (inFlight != null) {
      _resyncRequested = true;
      return inFlight;
    }
    final fut = _serial(() async {
      await _syncAll();
      while (_resyncRequested) {
        _resyncRequested = false;
        await _syncAll();
      }
    }).whenComplete(() => _syncLoop = null);
    _syncLoop = fut;
    return fut;
  }

  Future<void> refreshUnsyncedCount() async {}

  Future<void> _syncAll() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _isSyncing = true;
    try {
      final client = Supabase.instance.client;

      // ── Push product deletions ───────────────────────────────────────────
      if (_staleUser(userId)) return;
      final pendingDeletes = await LocalDbService.getPendingDeleteProductIds();
      if (pendingDeletes.isNotEmpty) {
        try {
          // .select() returns the rows actually removed; purge tombstones
          // only for confirmed deletions so an RLS-refused delete keeps its
          // tombstone (stays hidden, retries next cycle, never resurrects).
          final removed = await client
              .from('products')
              .delete()
              .inFilter('id', pendingDeletes)
              .eq('user_id', userId)
              .select('id');
          for (final row in removed) {
            await LocalDbService.purgeDeletedProduct(row['id'] as String);
          }
        } catch (e) {
          debugPrint('Product delete sync error: $e');
        }
      }

      // ── Push products ────────────────────────────────────────────────────
      if (_staleUser(userId)) return;
      final (unsyncedProducts, productRevs) =
          await LocalDbService.getUnsyncedProductsWithRev();
      if (unsyncedProducts.isNotEmpty) {
        try {
          await client
              .from('products')
              .upsert(
                unsyncedProducts
                    .map(
                      (p) => {
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
                        'dealer_name': p.dealerName,
                        'barcode_no': p.barcodeNo,
                      },
                    )
                    .toList(),
              );
          for (final p in unsyncedProducts) {
            await LocalDbService.markSyncedIfRev(
              'products',
              'id',
              p.id,
              productRevs[p.id] ?? 0,
            );
          }
          debugPrint('PUSH: products ok (${unsyncedProducts.length} rows)');
        } catch (e) {
          debugPrint('Product sync error: $e');
        }
      }

      // ── Push variant deletions ───────────────────────────────────────────
      if (_staleUser(userId)) return;
      final pendingVariantDeletes =
          await LocalDbService.getPendingDeleteVariantIds();
      if (pendingVariantDeletes.isNotEmpty) {
        try {
          final removed = await client
              .from('product_variants')
              .delete()
              .inFilter('id', pendingVariantDeletes)
              .eq('user_id', userId)
              .select('id');
          for (final row in removed) {
            await LocalDbService.purgeDeletedVariant(row['id'] as String);
          }
        } catch (e) {
          debugPrint('Variant delete sync error: $e');
        }
      }

      // ── Push variants ────────────────────────────────────────────────────
      if (_staleUser(userId)) return;
      final (unsyncedVariants, variantRevs) =
          await LocalDbService.getUnsyncedVariantsWithRev();
      if (unsyncedVariants.isNotEmpty) {
        try {
          await client
              .from('product_variants')
              .upsert(
                unsyncedVariants
                    .map(
                      (v) => {
                        'id': v.id,
                        'user_id': userId,
                        'product_id': v.productId,
                        'label': v.label,
                        'price': v.price,
                        'buying_price': v.buyingPrice,
                        'stock': v.stock,
                        'sku': v.sku,
                        'barcode_no': v.barcodeNo,
                      },
                    )
                    .toList(),
              );
          for (final v in unsyncedVariants) {
            await LocalDbService.markSyncedIfRev(
              'product_variants',
              'id',
              v.id,
              variantRevs[v.id] ?? 0,
            );
          }
          debugPrint(
            'PUSH: product_variants ok (${unsyncedVariants.length} rows)',
          );
        } catch (e) {
          debugPrint('Variant sync error: $e');
        }
      }

      // ── Push transaction deletions ───────────────────────────────────────
      if (_staleUser(userId)) return;
      final pendingTxDeletes =
          await LocalDbService.getPendingDeleteTransactionIds();
      if (pendingTxDeletes.isNotEmpty) {
        try {
          final removed = await client
              .from('transactions')
              .delete()
              .inFilter('id', pendingTxDeletes)
              .eq('user_id', userId)
              .select('id');
          for (final row in removed) {
            await LocalDbService.purgeDeletedTransaction(row['id'] as String);
          }
          debugPrint(
            'PUSH: tx deletes ok (${removed.length}/${pendingTxDeletes.length})',
          );
        } catch (e) {
          debugPrint('Transaction delete sync error: $e');
        }
      }

      // ── Push transactions ────────────────────────────────────────────────
      if (_staleUser(userId)) return;
      final (unsyncedTx, txRevs) = await LocalDbService.getUnsyncedWithRev();
      if (unsyncedTx.isNotEmpty) {
        try {
          await client
              .from('transactions')
              .upsert(
                unsyncedTx
                    .map(
                      (t) => {
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
                      },
                    )
                    .toList(),
              );
          for (final t in unsyncedTx) {
            await LocalDbService.markSyncedIfRev(
              'transactions',
              'id',
              t.id,
              txRevs[t.id] ?? 0,
            );
          }
          debugPrint('PUSH: transactions ok (${unsyncedTx.length} rows)');
        } catch (e) {
          debugPrint('Transaction sync error: $e');
        }
      }

      // ── Push customer deletions ──────────────────────────────────────────
      if (_staleUser(userId)) return;
      final pendingCustomerDeletes =
          await LocalDbService.getPendingDeleteCustomerIds();
      if (pendingCustomerDeletes.isNotEmpty) {
        try {
          final removed = await client
              .from('customers')
              .delete()
              .inFilter('id', pendingCustomerDeletes)
              .eq('user_id', userId)
              .select('id');
          for (final row in removed) {
            await LocalDbService.purgeDeletedCustomer(row['id'] as String);
          }
        } catch (e) {
          debugPrint('Customer delete sync error: $e');
        }
      }

      // ── Push customers ───────────────────────────────────────────────────
      if (_staleUser(userId)) return;
      final (unsyncedCustomers, customerRevs) =
          await LocalDbService.getUnsyncedCustomersWithRev();
      if (unsyncedCustomers.isNotEmpty) {
        try {
          await client
              .from('customers')
              .upsert(
                unsyncedCustomers
                    .map(
                      (c) => {
                        'id': c.id,
                        'user_id': userId,
                        'name': c.name,
                        'phone': c.phone,
                        // Cloud column is NOT NULL — an explicit null is
                        // rejected (the default only applies when omitted).
                        'address': c.address ?? '',
                        'created_at': c.createdAt.toIso8601String(),
                      },
                    )
                    .toList(),
              );
          for (final c in unsyncedCustomers) {
            await LocalDbService.markSyncedIfRev(
              'customers',
              'id',
              c.id,
              customerRevs[c.id] ?? 0,
            );
          }
          debugPrint('PUSH: customers ok (${unsyncedCustomers.length} rows)');
        } catch (e) {
          debugPrint('Customer sync error: $e');
        }
      }

      // ── Push category deletions (also covers renames' old names) ─────────
      if (_staleUser(userId)) return;
      final pendingCatDeletes =
          await LocalDbService.getPendingDeleteCategoryNames();
      if (pendingCatDeletes.isNotEmpty) {
        try {
          final removed = await client
              .from('user_categories')
              .delete()
              .inFilter('name', pendingCatDeletes)
              .eq('user_id', userId)
              .select('name');
          for (final row in removed) {
            await LocalDbService.purgeDeletedCategory(row['name'] as String);
          }
        } catch (e) {
          debugPrint('Category delete sync error: $e');
        }
      }

      // ── Push categories ──────────────────────────────────────────────────
      if (_staleUser(userId)) return;
      final (unsyncedCats, catRevs) =
          await LocalDbService.getUnsyncedCategoriesWithRev();
      if (unsyncedCats.isNotEmpty) {
        try {
          await client
              .from('user_categories')
              .upsert(
                unsyncedCats
                    .map((name) => {'user_id': userId, 'name': name})
                    .toList(),
              );
          for (final name in unsyncedCats) {
            await LocalDbService.markSyncedIfRev(
              'categories',
              'name',
              name,
              catRevs[name] ?? 0,
            );
          }
        } catch (e) {
          debugPrint('Category sync error: $e');
        }
      }

      // ── Push settings (only when edited locally) ─────────────────────────
      // Business-level settings that follow the account across devices.
      // Device-specific ones (printer, paper size, orientation, auto-print,
      // logo_path) are deliberately excluded so one machine can't override
      // another's setup — see [_syncedSettingsCols], which the pull uses
      // symmetrically.
      if (_staleUser(userId)) return;
      try {
        // Dirty token read FIRST: an edit landing during the upsert bumps it,
        // so the conditional clear below leaves it dirty for the next cycle.
        final dirtyToken = await LocalDbService.getSettingsDirtyToken();
        if (dirtyToken != null) {
          final settings = await LocalDbService.getSettings();
          final filtered = Map.fromEntries(
            settings.entries.where(
              (e) => _syncedSettingsCols.contains(e.key),
            ),
          );
          if (filtered.isNotEmpty) {
            await client.from('user_settings').upsert({
              'user_id': userId,
              ...filtered,
            });
          }
          await LocalDbService.clearSettingsDirtyIfToken(dirtyToken);
        }
      } catch (e) {
        debugPrint('Settings sync error: $e');
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // ── Pull: full refresh from the cloud (startup / reconnect / safety net) ──

  Future<void> pullFromCloud() => _serial(_pullFromCloudInner);

  Future<void> _pullFromCloudInner() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('PULL: skipped — no logged-in user');
      return;
    }
    debugPrint('PULL: starting for user $userId');
    final client = Supabase.instance.client;
    _pullInFlight = true;
    _liveIdsDuringPull.clear();
    try {
      try {
        if (_staleUser(userId)) return;
        final rows = await client
            .from('products')
            .select()
            .eq('user_id', userId);
        final products = (rows as List)
            .map((r) => _productFromRow(Map<String, dynamic>.from(r as Map)))
            .toList();
        if (_staleUser(userId)) return;
        await LocalDbService.insertProductsSynced(products);
        await LocalDbService.reconcileTableWithCloud(
          'products',
          products.map((p) => p.id).toSet()
            ..addAll(_liveIdsDuringPull['products'] ?? const <String>{}),
        );
        debugPrint('PULL: products ok (${products.length} rows)');
      } catch (e) {
        debugPrint('PULL: products FAILED: $e');
      }

      try {
        if (_staleUser(userId)) return;
        final rows = await client
            .from('product_variants')
            .select()
            .eq('user_id', userId);
        final variants = (rows as List)
            .map((r) => _variantFromRow(Map<String, dynamic>.from(r as Map)))
            .toList();
        if (_staleUser(userId)) return;
        await LocalDbService.insertVariantsSynced(variants);
        await LocalDbService.reconcileTableWithCloud(
          'product_variants',
          variants.map((v) => v.id).toSet()
            ..addAll(
              _liveIdsDuringPull['product_variants'] ?? const <String>{},
            ),
        );
        debugPrint('PULL: product_variants ok (${variants.length} rows)');
      } catch (e) {
        debugPrint('PULL: product_variants FAILED: $e');
      }

      try {
        if (_staleUser(userId)) return;
        final rows = await client
            .from('transactions')
            .select()
            .eq('user_id', userId);
        final txs = (rows as List)
            .map((r) => _txFromRow(Map<String, dynamic>.from(r as Map)))
            .toList();
        if (_staleUser(userId)) return;
        await LocalDbService.insertTransactionsSynced(txs);
        await LocalDbService.reconcileTransactionsWithCloud(
          txs.map((t) => t.id).toSet()
            ..addAll(_liveIdsDuringPull['transactions'] ?? const <String>{}),
        );
        debugPrint('PULL: transactions ok (${txs.length} rows)');
      } catch (e) {
        debugPrint('PULL: transactions FAILED: $e');
      }

      try {
        if (_staleUser(userId)) return;
        final rows = await client
            .from('customers')
            .select()
            .eq('user_id', userId);
        final customers = (rows as List)
            .map((r) => _customerFromRow(Map<String, dynamic>.from(r as Map)))
            .toList();
        if (_staleUser(userId)) return;
        await LocalDbService.insertCustomersSynced(customers);
        await LocalDbService.reconcileTableWithCloud(
          'customers',
          customers.map((c) => c.id).toSet()
            ..addAll(_liveIdsDuringPull['customers'] ?? const <String>{}),
        );
        debugPrint('PULL: customers ok (${customers.length} rows)');
      } catch (e) {
        debugPrint('PULL: customers FAILED: $e');
      }

      if (_staleUser(userId)) return;
      await _pullCategories(client, userId);
      if (_staleUser(userId)) return;
      await _pullSettings(client, userId);
    } finally {
      _pullInFlight = false;
      _liveIdsDuringPull.clear();
    }

    notifyListeners();
  }

  Future<void> _pullCategories(SupabaseClient client, String userId) async {
    try {
      final rows = await client
          .from('user_categories')
          .select()
          .eq('user_id', userId);
      final cats = (rows as List).map((r) => r['name'] as String).toList();
      if (_staleUser(userId)) return;
      await LocalDbService.insertCategoriesSynced(cats);
      await LocalDbService.reconcileCategoriesWithCloud(cats.toSet());
      debugPrint('PULL: categories ok (${cats.length} rows)');
    } catch (e) {
      debugPrint('PULL: categories FAILED: $e');
    }
  }

  Future<void> _pullSettings(SupabaseClient client, String userId) async {
    try {
      // Never overwrite settings the user edited locally but hasn't pushed
      // yet — the push (which runs before the pull on every path) clears the
      // dirty token once the cloud has them.
      if (await LocalDbService.getSettingsDirtyToken() != null) {
        debugPrint('PULL: settings skipped (local edits pending)');
        return;
      }
      final settingsRow = await client
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (settingsRow != null) {
        final map = Map<String, dynamic>.from(settingsRow as Map);
        map.remove('user_id');
        // Only account-level keys may come from the cloud — device-specific
        // settings (printer, paper size, ...) stay exactly as the user set
        // them on THIS machine. Skip nulls (columns absent from the cloud
        // schema) but KEEP empty strings — clearing a field on one device
        // must propagate.
        final settings = Map<String, String>.fromEntries(
          map.entries
              .where(
                (e) =>
                    _syncedSettingsCols.contains(e.key) && e.value != null,
              )
              .map((e) => MapEntry(e.key, e.value.toString())),
        );
        if (_staleUser(userId)) return;
        if (settings.isNotEmpty) {
          await LocalDbService.saveSettingsFromCloud(settings);
        }
      }
      debugPrint('PULL: settings ok');
    } catch (e) {
      debugPrint('PULL: settings FAILED: $e');
    }
  }

  // ── Row → model mapping (shared by pull and realtime) ─────────────────────
  // Realtime payloads can encode numeric columns as strings, so parse
  // defensively instead of casting.

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  Product _productFromRow(Map<String, dynamic> r) => Product.fromMap({
    'id': r['id'],
    'name': r['name'],
    'price': _asDouble(r['price']),
    'buying_price': _asDouble(r['buying_price']),
    'tax_percent': _asDouble(r['tax_percent']),
    'category': r['category'],
    'emoji': r['emoji'],
    'sku': r['sku'],
    'stock': _asInt(r['stock']),
    'description': (r['description'] as String?) ?? '',
    'dealer_name': (r['dealer_name'] as String?) ?? '',
    'barcode_no': (r['barcode_no'] as String?) ?? '',
    // Local-only today; harmless empty when the cloud column is absent.
    'purchase_date': (r['purchase_date'] as String?) ?? '',
    'synced': 1,
  });

  ProductVariant _variantFromRow(Map<String, dynamic> r) =>
      ProductVariant.fromMap({
        'id': r['id'],
        'product_id': r['product_id'],
        'label': r['label'],
        'price': _asDouble(r['price']),
        'buying_price': _asDouble(r['buying_price']),
        'stock': _asInt(r['stock']),
        'sku': (r['sku'] as String?) ?? '',
        'barcode_no': (r['barcode_no'] as String?) ?? '',
      });

  TransactionRecord _txFromRow(Map<String, dynamic> r) {
    var items = r['items'];
    if (items is String) items = jsonDecode(items);
    return TransactionRecord(
      id: r['id'] as String,
      invoiceNumber: r['invoice_number'] as String?,
      customerName: r['customer_name'] as String?,
      customerPhone: r['customer_phone'] as String?,
      items: (items as List? ?? const [])
          .map(
            (i) => TransactionItem.fromMap(Map<String, dynamic>.from(i as Map)),
          )
          .toList(),
      subtotal: _asDouble(r['subtotal']),
      discountAmount: _asDouble(r['discount_amount']),
      taxAmount: _asDouble(r['tax_amount']),
      total: _asDouble(r['total']),
      paymentMethod: r['payment_method'] as String,
      createdAt: DateTime.parse(r['created_at'] as String),
    );
  }

  Customer _customerFromRow(Map<String, dynamic> r) => Customer(
    id: r['id'] as String,
    name: r['name'] as String,
    phone: (r['phone'] as String?)?.isEmpty == true
        ? null
        : r['phone'] as String?,
    address: (r['address'] as String?)?.isEmpty == true
        ? null
        : r['address'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String),
    synced: true,
  );

  @override
  void dispose() {
    _sub?.cancel();
    _pollTimer?.cancel();
    _realtimeRetryTimer?.cancel();
    _teardownRealtime();
    super.dispose();
  }
}
