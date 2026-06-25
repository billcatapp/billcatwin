import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
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

  double get taxAmount => (subtotal - discountAmount) * (taxRate / 100);
  double get total => subtotal - discountAmount + taxAmount;

  int quantityInCart(String productId) {
    final i = _items.indexWhere((e) => e.product.id == productId);
    return i >= 0 ? _items[i].quantity : 0;
  }

  void addProduct(Product product) {
    final i = _items.indexWhere((e) => e.product.id == product.id);
    if (i >= 0) {
      _items[i].quantity++;
    } else {
      _items.add(CartItem(product: product));
    }
    notifyListeners();
  }

  void increment(String productId, {int stock = 999999}) {
    final i = _items.indexWhere((e) => e.product.id == productId);
    if (i >= 0 && _items[i].quantity < stock) { _items[i].quantity++; notifyListeners(); }
  }

  void decrement(String productId) {
    final i = _items.indexWhere((e) => e.product.id == productId);
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
    _items.removeWhere((e) => e.product.id == productId);
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
    final i = _items.indexWhere((e) => e.product.id == productId);
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
        price: i.product.price,
        quantity: i.quantity,
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
