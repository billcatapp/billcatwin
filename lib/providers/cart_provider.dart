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
  /// asking: it is deliberate. (Switched to 5/105 on 19 Nov and reverted
  /// the same day at the owner's word: "old method is correct".)
  ///
  /// A discount DOES reduce the tax: the rate is read against what the
  /// customer actually pays. 5300 of goods with a 530 discount pays 4770,
  /// and the tax is 5% of 4770 = 238.50. The owner's instruction of 17 Oct,
  /// replacing one of 8 Oct that held the tax at the pre-discount figure.
  /// The discount is spread across the lines in proportion to their value,
  /// so on a bill mixing rates each slab is taxed on its own share.
  ///
  /// A bill the cashier rounded down by hand ([setRoundedTotal]) is taxed on
  /// the rounded amount, the same way a discount lowers the tax — the
  /// owner's choice of 19 Nov. The automatic nearest-rupee rounding does
  /// not change the tax.
  Map<double, double> get taxBreakdown {
    final sub = subtotal;
    final result = <double, double>{};
    if (sub <= 0) return result;
    final paid = _roundApplies ? _roundedTo! : sub - discountAmount;
    final discountFactor = paid / sub;
    for (final item in _items) {
      // A tax-free product resolves to 0 here and is skipped, so it
      // contributes nothing to the bill's tax.
      final rate = item.product.rateWith(taxRate);
      if (rate <= 0) continue;
      result[rate] =
          (result[rate] ?? 0) + item.total * discountFactor * rate / 100;
    }
    return result;
  }

  double get taxAmount =>
      taxBreakdown.values.fold(0.0, (s, v) => s + v);

  /// Exact pre-round total; kept for the round-off calculation. The tax is
  /// already part of [subtotal], so it is not added again here.
  double get rawTotal => subtotal - discountAmount;

  /// Payable total, rounded to the nearest rupee (Indian retail standard),
  /// unless the cashier typed a lower final amount to round the bill down.
  /// This is what gets charged, saved and split — not the paise-exact figure.
  double get total => _roundApplies ? _roundedTo! : rawTotal.roundToDouble();

  /// The final amount typed in the cart's ROUND OFF box, e.g. 1040 for a
  /// 1047 bill. Kept with the nearest-rupee total it was typed against, so
  /// it applies only to that exact bill: adding an item or changing the
  /// discount afterwards drops it by itself, and a stale figure can never
  /// carry over to a different bill.
  double? _roundedTo;
  double _roundBase = 0;

  bool get _roundApplies {
    final r = _roundedTo;
    if (r == null) return false;
    final normal = rawTotal.roundToDouble();
    return _roundBase == normal && r > 0 && r <= normal;
  }

  /// The typed final amount while it applies, else null.
  double? get roundedTo => _roundApplies ? _roundedTo : null;

  /// Rounds the bill down to [amount] (null = normal rounding). Only a
  /// figure above 0 and not more than the normal total takes effect.
  void setRoundedTotal(double? amount) {
    _roundedTo = amount;
    _roundBase = rawTotal.roundToDouble();
    notifyListeners();
  }

  /// Every change to the cart ends in a notify. One that moved the bill
  /// total away from the figure a round-off was typed against forgets that
  /// round-off for good, so taking an item off again can never bring a
  /// stale rounded amount back. Changes that leave the total as it was
  /// (payment method, customer) keep it.
  @override
  void notifyListeners() {
    if (_roundedTo != null && _roundBase != rawTotal.roundToDouble()) {
      _roundedTo = null;
    }
    super.notifyListeners();
  }

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
    // The record id the bill's printed copy and e-bill link already carry
    // (reserved when it was first printed or sent), so the saved bill is the
    // one its View Bill link opens. Without it a new id is made, as before.
    String? id,
  }) async {
    // Default to full payment; anything less is recorded as a balance owed.
    final paid = amountPaid ?? total;
    final balanceDue = (total - paid) > 0.005 ? total - paid : 0.0;
    // Persist the cash/UPI split so receipts and the Cash & Bank report can
    // break a hybrid bill down. Zero for every other method.
    final isHybrid = paymentMethod == PaymentMethod.hybrid;
    final record = TransactionRecord(
      id: id ?? const Uuid().v4(),
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
    _roundedTo = null;
    notifyListeners();
  }
}
