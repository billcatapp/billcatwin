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

  // Hybrid split: how the total is divided between cash and UPI. Only
  // meaningful when paymentMethod == hybrid.
  double hybridCash = 0;
  double hybridUpi = 0;

  void setHybridSplit(double cash, double upi) {
    hybridCash = cash;
    hybridUpi = upi;
    notifyListeners();
  }

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

  /// Tax contained per rate, e.g. {5.0: 65.00, 12.0: 120.00}. Each line uses
  /// the product's own tax percent, falling back to the store-wide [taxRate]
  /// when the product doesn't define one. Discount is spread proportionally so
  /// the taxable base always matches what the customer actually pays.
  ///
  /// A product's price is the final figure the customer pays, with the tax
  /// already inside it, so the tax comes OUT of the line rather than being
  /// added on top of it — adding it on top would charge it a second time.
  ///
  /// The share taken out is the plain rate percent of the line: on a 1000
  /// line at 5% the tax is 50.00, leaving 950.00 of taxable value. This is
  /// the owner's instruction (8 Oct) and is NOT the textbook inclusive
  /// formula, which would take 1000 x 5/105 = 47.62 and leave 952.38 — the
  /// figure that makes the tax exactly 5% OF the taxable value. Here 50 is
  /// 5.26% of 950, so the taxable and tax columns on a return do not
  /// reconcile to the stated rate. Do not "correct" this back without
  /// asking: it is deliberate.
  ///
  /// A discount does NOT reduce the tax — also the owner's instruction
  /// (8 Oct). The rate is read against the line's full value, so a 1000 line
  /// discounted by 100 still carries 50 of tax while the customer pays 900,
  /// leaving 850 of taxable value. GST ordinarily treats an invoice discount
  /// as reducing the taxable value, so this too is deliberate and departs
  /// from it: the discount comes out of the shop's own margin, not the tax.
  Map<double, double> get taxBreakdown {
    final sub = subtotal;
    final result = <double, double>{};
    if (sub <= 0) return result;
    for (final item in _items) {
      // A tax-free product resolves to 0 here and is skipped, so it
      // contributes nothing to the bill's tax.
      final rate = item.product.rateWith(taxRate);
      if (rate <= 0) continue;
      result[rate] = (result[rate] ?? 0) + item.total * rate / 100;
    }
    return result;
  }

  double get taxAmount =>
      taxBreakdown.values.fold(0.0, (s, v) => s + v);

  /// Exact pre-round total; kept for the round-off calculation. The tax is
  /// already part of [subtotal], so it is not added again here.
  double get rawTotal => subtotal - discountAmount;

  /// Payable total, rounded to the nearest rupee (Indian retail standard).
  /// This is what gets charged, saved and split — not the paise-exact figure.
  double get total => rawTotal.roundToDouble();

  /// Signed adjustment between the exact and payable totals, e.g. +0.44 when
  /// 1234.56 rounds up to 1235.
  double get roundOff => total - rawTotal;

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
    // Start the split empty — the cashier fills one side, the other follows.
    if (m == PaymentMethod.hybrid) {
      hybridCash = 0;
      hybridUpi = 0;
    }
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
    // clamp throws when the upper bound is below the lower one, so a line
    // whose product has run down to zero (or holds a bad negative stock)
    // would kill the quantity field. Reject the edit as before rather than
    // capping to 1, which would silently rewrite a billed quantity.
    if (stock < 1) return;
    final clamped = quantity.clamp(1, stock);
    _items[i].quantity = clamped;
    notifyListeners();
  }

  Future<void> checkout({
    String? invoiceNumber,
    double? amountPaid,
    String salesperson = '',
    bool gstBilled = true,
  }) async {
    // Default to full payment; anything less is recorded as a balance owed.
    final paid = amountPaid ?? total;
    final balanceDue = (total - paid) > 0.005 ? total - paid : 0.0;
    // Persist the cash/UPI split so receipts and the Cash & Bank report can
    // break a hybrid bill down. Zero for every other method.
    final isHybrid = paymentMethod == PaymentMethod.hybrid;
    final record = TransactionRecord(
      id: const Uuid().v4(),
      // The Mac-format code, shared with the printed preview.
      invoiceNumber: invoiceNumber,
      balanceDue: balanceDue,
      hybridCash: isHybrid ? hybridCash : 0,
      hybridUpi: isHybrid ? hybridUpi : 0,
      salesperson: salesperson,
      gstBilled: gstBilled,
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
        // Freeze the rate actually charged, so reprinted receipts stay
        // accurate even if the product's or store's rate changes later.
        // Resolves to 0 for a tax-free product. On a bill that has rated
        // lines, 0 on a line already means "sold tax-free" everywhere that
        // reads bills back, which is exactly what this should record.
        taxPercent: i.product.rateWith(taxRate),
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
    hybridCash = 0;
    hybridUpi = 0;
    notifyListeners();
  }
}
