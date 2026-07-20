import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../models/transaction_record.dart';
import '../services/local_db_service.dart';
import '../services/connectivity_service.dart';

enum DiscountType { percent, fixed }
enum PaymentMethod { cash, card, upi, hybrid }

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  String customerName = '';
  String customerPhone = '';
  double discountValue = 0;
  DiscountType discountType = DiscountType.percent;
  PaymentMethod paymentMethod = PaymentMethod.cash;
  double taxRate = 0.0;

  void setTaxRate(double rate) {
    taxRate = rate;
    notifyListeners();
  }

  List<CartItem> get items => _items;
  int get itemCount => _items.fold(0, (s, i) => s + i.quantity);

  double get subtotal => _items.fold(0, (s, i) => s + i.total);

  double get discountAmount {
    if (discountType == DiscountType.percent) {
      return subtotal * (discountValue / 100);
    }
    return discountValue.clamp(0, subtotal);
  }

  /// Tax owed per rate, e.g. {5.0: 65.00, 12.0: 120.00}. Each line uses the
  /// product's own tax percent, falling back to the store-wide [taxRate] when
  /// the product doesn't define one. Discount is spread proportionally so the
  /// taxable base always matches what the customer actually pays.
  Map<double, double> get taxBreakdown {
    final sub = subtotal;
    final result = <double, double>{};
    if (sub <= 0) return result;
    final discountFactor = (sub - discountAmount) / sub;
    for (final item in _items) {
      final rate =
          item.product.taxPercent > 0 ? item.product.taxPercent : taxRate;
      if (rate <= 0) continue;
      final taxable = item.total * discountFactor;
      result[rate] = (result[rate] ?? 0) + taxable * rate / 100;
    }
    return result;
  }

  double get taxAmount =>
      taxBreakdown.values.fold(0.0, (s, v) => s + v);
  double get total => subtotal - discountAmount + taxAmount;

  // [productId] here means "line key" — for products without a variant this
  // is just the product id, so every existing call site keeps working as-is.
  int quantityInCart(String productId) {
    final i = _items.indexWhere((e) => e.lineKey == productId);
    return i >= 0 ? _items[i].quantity : 0;
  }

  int quantityInCartForVariant(String productId, String variantId) =>
      quantityInCart('$productId::$variantId');

  // Sum across all variant lines of a product — used for stock badges on
  // products that have variants, where individual lines aren't enough.
  int totalQuantityInCartForProduct(String productId) => _items
      .where((e) => e.product.id == productId)
      .fold(0, (s, e) => s + e.quantity);

  void addProduct(Product product) {
    final i = _items.indexWhere((e) => e.lineKey == product.id);
    if (i >= 0) {
      _items[i].quantity++;
    } else {
      _items.add(CartItem(product: product));
    }
    notifyListeners();
  }

  void addVariant(Product product, ProductVariant variant) {
    final key = '${product.id}::${variant.id}';
    final i = _items.indexWhere((e) => e.lineKey == key);
    if (i >= 0) {
      _items[i].quantity++;
    } else {
      _items.add(CartItem(product: product, variant: variant));
    }
    notifyListeners();
  }

  void increment(String productId, {int stock = 999999}) {
    final i = _items.indexWhere((e) => e.lineKey == productId);
    if (i >= 0 && _items[i].quantity < stock) { _items[i].quantity++; notifyListeners(); }
  }

  void decrement(String productId) {
    final i = _items.indexWhere((e) => e.lineKey == productId);
    if (i >= 0) {
      if (_items[i].quantity > 1) {
        _items[i].quantity--;
      } else {
        _items.removeAt(i);
      }
      notifyListeners();
    }
  }

  void removeItem(String productId) {
    _items.removeWhere((e) => e.lineKey == productId);
    notifyListeners();
  }

  void setPaymentMethod(PaymentMethod m) {
    paymentMethod = m;
    notifyListeners();
  }

  void applyDiscount(double value, DiscountType type) {
    discountValue = value;
    discountType = type;
    notifyListeners();
  }

  void setQuantity(String productId, int quantity, {int stock = 999999}) {
    final i = _items.indexWhere((e) => e.lineKey == productId);
    if (i < 0) return;
    final clamped = quantity.clamp(1, stock);
    _items[i].quantity = clamped;
    notifyListeners();
  }

  Future<void> checkout({String? invoiceNumber}) async {
    final record = TransactionRecord(
      id: const Uuid().v4(),
      invoiceNumber: invoiceNumber,
      customerName: customerName.isEmpty ? null : customerName,
      customerPhone: customerPhone.isEmpty ? null : customerPhone,
      items: _items.map((i) => TransactionItem(
        productId: i.product.id,
        productName: i.product.name,
        description: i.product.description,
        price: i.unitPrice,
        quantity: i.quantity,
        variantId: i.variant?.id,
        variantLabel: i.variant?.label,
      )).toList(),
      subtotal: subtotal,
      discountAmount: discountAmount,
      taxAmount: taxAmount,
      total: total,
      paymentMethod: paymentMethod.name,
      createdAt: DateTime.now(),
      synced: false,
    );
    await LocalDbService.insertTransaction(record);
    await ConnectivityService.instance.refreshUnsyncedCount();
    clearCart();
    if (ConnectivityService.instance.isOnline) {
      ConnectivityService.instance.syncNow();
    }
  }

  void clearCart() {
    _items.clear();
    customerName = '';
    customerPhone = '';
    discountValue = 0;
    notifyListeners();
  }
}
