import 'dart:convert';

class TransactionItem {
  final String productId;
  final String productName;
  final String description;
  final double price;
  final int quantity;
  final String? variantId;
  final String? variantLabel;
  /// Rate charged on this line at the time of sale. 0 means "not recorded"
  /// (sales made before per-item rates existed) — callers fall back to the
  /// store-wide rate for those.
  final double taxPercent;

  const TransactionItem({
    required this.productId,
    required this.productName,
    this.description = '',
    required this.price,
    required this.quantity,
    this.variantId,
    this.variantLabel,
    this.taxPercent = 0,
  });

  double get total => price * quantity;

  String get displayName =>
      variantLabel != null && variantLabel!.isNotEmpty
          ? '$productName ($variantLabel)'
          : productName;

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'description': description,
    'price': price,
    'quantity': quantity,
    'variantId': variantId,
    'variantLabel': variantLabel,
    'taxPercent': taxPercent,
  };

  factory TransactionItem.fromMap(Map<String, dynamic> m) => TransactionItem(
    productId: m['productId'] as String,
    productName: m['productName'] as String,
    description: (m['description'] as String?) ?? '',
    price: (m['price'] as num).toDouble(),
    // Defensive like price: tolerate a quantity that arrives as a double from
    // the cloud (e.g. 1.0), so one odd row can't throw and drop a whole pull.
    quantity: (m['quantity'] as num).toInt(),
    variantId: m['variantId'] as String?,
    variantLabel: m['variantLabel'] as String?,
    taxPercent: (m['taxPercent'] as num?)?.toDouble() ?? 0,
  );
}

class TransactionRecord {
  final String id;
  final String? invoiceNumber;
  final String? customerName;
  final String? customerPhone;
  final List<TransactionItem> items;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double total;
  final String paymentMethod;
  final DateTime createdAt;
  final bool synced;

  /// Amount of [total] still owed on a credit sale. 0 means fully paid, which
  /// is every ordinary bill and every bill that predates this field, so old
  /// data reads correctly with no back-fill.
  final double balanceDue;

  /// For a hybrid (split) payment: how much of [total] was taken in cash vs
  /// UPI. Both 0 for every non-hybrid bill and for hybrid bills that predate
  /// this field.
  final double hybridCash;
  final double hybridUpi;

  const TransactionRecord({
    required this.id,
    this.invoiceNumber,
    this.customerName,
    this.customerPhone,
    required this.items,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.total,
    required this.paymentMethod,
    required this.createdAt,
    this.synced = false,
    this.balanceDue = 0,
    this.hybridCash = 0,
    this.hybridUpi = 0,
  });

  /// Fractional tolerance keeps rounding noise from flagging a paid bill.
  bool get isCredit => balanceDue > 0.005;

  double get amountPaid => total - balanceDue;

  /// Prefixes that mark a record as reversing an earlier bill. Returns are
  /// stored as their own record with negative amounts and quantities — no
  /// extra column — so they net off in every total that already sums sales.
  static const String returnPrefix = 'RTN-';
  static const String exchangePrefix = 'EXC-';

  /// The invoice this record reverses, or null for an ordinary sale.
  String? get returnOfInvoice {
    final n = invoiceNumber;
    if (n == null) return null;
    if (n.startsWith(returnPrefix)) return n.substring(returnPrefix.length);
    if (n.startsWith(exchangePrefix)) return n.substring(exchangePrefix.length);
    return null;
  }

  /// Judged by the prefix alone: an ordinary sale discounted past zero also
  /// carries a negative total, and must not be mistaken for a return.
  bool get isReturn => returnOfInvoice != null;

  bool get isExchange => invoiceNumber?.startsWith(exchangePrefix) ?? false;

  /// 'EXCHANGE' / 'RETURN' for reversing records, null for a normal sale.
  String? get reversalLabel =>
      !isReturn ? null : (isExchange ? 'EXCHANGE' : 'RETURN');

  /// The one invoice number shown EVERYWHERE — list, receipts, dialogs, PDF.
  /// Derived from the shared bill id ('#' + first 6 chars, upper) so the same
  /// sale reads identically on every device, Mac included. A return/exchange
  /// keeps its stored RTN-/EXC- number, which already embeds the original
  /// bill's derived id. Old bills that stored an 'INV…' number are ignored on
  /// purpose so everything converges on one format.
  static String shortId(String id) =>
      id.length >= 6 ? id.substring(0, 6).toUpperCase() : id.toUpperCase();

  String get displayInvoice {
    final inv = invoiceNumber;
    if (inv != null &&
        (inv.startsWith(returnPrefix) || inv.startsWith(exchangePrefix))) {
      return inv;
    }
    return '#${shortId(id)}';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'invoice_number': invoiceNumber,
    'customer_name': customerName ?? '',
    'customer_phone': customerPhone ?? '',
    'items': jsonEncode(items.map((i) => i.toMap()).toList()),
    'subtotal': subtotal,
    'discount_amount': discountAmount,
    'tax_amount': taxAmount,
    'total': total,
    'payment_method': paymentMethod,
    'created_at': createdAt.toIso8601String(),
    'synced': synced ? 1 : 0,
    'balance_due': balanceDue,
    'hybrid_cash': hybridCash,
    'hybrid_upi': hybridUpi,
  };

  factory TransactionRecord.fromMap(Map<String, dynamic> m) {
    final rawItems = jsonDecode(m['items'] as String) as List;
    return TransactionRecord(
      id: m['id'] as String,
      invoiceNumber: m['invoice_number'] as String?,
      customerName: m['customer_name'] as String?,
      customerPhone: m['customer_phone'] as String?,
      items: rawItems.map((i) => TransactionItem.fromMap(i as Map<String, dynamic>)).toList(),
      subtotal: (m['subtotal'] as num).toDouble(),
      discountAmount: (m['discount_amount'] as num).toDouble(),
      taxAmount: (m['tax_amount'] as num).toDouble(),
      total: (m['total'] as num).toDouble(),
      paymentMethod: m['payment_method'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
      synced: (m['synced'] as int) == 1,
      balanceDue: (m['balance_due'] as num?)?.toDouble() ?? 0,
      hybridCash: (m['hybrid_cash'] as num?)?.toDouble() ?? 0,
      hybridUpi: (m['hybrid_upi'] as num?)?.toDouble() ?? 0,
    );
  }
}
