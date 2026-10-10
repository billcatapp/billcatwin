import 'dart:convert';

/// One line of a supplier's bill.
///
/// [hsnCode] is captured here rather than read from the product record,
/// because a GST purchase register has to show the code as it stood on the
/// supplier's invoice. Looking it up later would report today's code for a
/// bill raised months ago.
class PurchaseItem {
  /// The product this line was matched to, or empty when it was typed in
  /// free-hand. A purchase is a record of what the supplier billed, so it
  /// stays readable even when the product is later renamed or deleted.
  final String productId;
  final String description;
  final String hsnCode;
  final double quantity;

  /// Price per unit before tax, as billed by the supplier.
  final double rate;

  /// Value before tax for the whole line.
  final double taxable;
  final double taxPercent;

  const PurchaseItem({
    this.productId = '',
    this.description = '',
    this.hsnCode = '',
    this.quantity = 0,
    this.rate = 0,
    this.taxable = 0,
    this.taxPercent = 0,
  });

  /// Tax on this line, worked out from the stored taxable value and rate.
  double get taxAmount => taxable * taxPercent / 100;

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'description': description,
    'hsnCode': hsnCode,
    'quantity': quantity,
    'rate': rate,
    'taxable': taxable,
    'taxPercent': taxPercent,
  };

  static PurchaseItem fromMap(Map<String, dynamic> m) => PurchaseItem(
    productId: (m['productId'] as String?) ?? '',
    description: (m['description'] as String?) ?? '',
    hsnCode: (m['hsnCode'] as String?) ?? '',
    quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
    rate: (m['rate'] as num?)?.toDouble() ?? 0,
    taxable: (m['taxable'] as num?)?.toDouble() ?? 0,
    taxPercent: (m['taxPercent'] as num?)?.toDouble() ?? 0,
  );

  PurchaseItem copyWith({
    String? productId,
    String? description,
    String? hsnCode,
    double? quantity,
    double? rate,
    double? taxable,
    double? taxPercent,
  }) => PurchaseItem(
    productId: productId ?? this.productId,
    description: description ?? this.description,
    hsnCode: hsnCode ?? this.hsnCode,
    quantity: quantity ?? this.quantity,
    rate: rate ?? this.rate,
    taxable: taxable ?? this.taxable,
    taxPercent: taxPercent ?? this.taxPercent,
  );
}

/// A supplier's bill, as entered from the paper invoice.
///
/// Stored one row per invoice with the lines as JSON, the same shape
/// `transactions` uses, so it needs one table and one sync binding.
///
/// [dealerGstin] and [dealerName] are SNAPSHOTS taken when the purchase was
/// entered, not live lookups into `dealers`. A GST record must keep reading
/// the way it was filed: correcting a supplier's GSTIN today must not silently
/// rewrite bills already entered under the old one.
class Purchase {
  final String id;

  /// Link back to the dealer directory, empty when the supplier was typed in
  /// without being saved as a dealer.
  final String dealerId;
  final String dealerName;
  final String dealerGstin;

  /// The supplier's own invoice number, exactly as printed on their bill.
  final String invoiceNo;

  /// Date on the supplier's invoice (yyyy-MM-dd), which is the date the
  /// purchase register reports — not the day it was keyed in.
  final String invoiceDate;

  /// Place of supply as GST writes it, e.g. '27-MAHARASHTRA'.
  final String placeOfSupply;
  final bool reverseCharge;
  final String notes;
  final List<PurchaseItem> items;

  /// When the row was created locally. Ordering and sync use this; the
  /// register reports [invoiceDate].
  final DateTime createdAt;
  final bool synced;

  /// Whether this bill belongs in the GST purchase report. False when it was
  /// entered with the report switch off; still kept as a record either way.
  final bool gstReport;

  const Purchase({
    required this.id,
    this.dealerId = '',
    this.dealerName = '',
    this.dealerGstin = '',
    this.invoiceNo = '',
    this.invoiceDate = '',
    this.placeOfSupply = '',
    this.reverseCharge = false,
    this.notes = '',
    this.items = const [],
    required this.createdAt,
    this.synced = false,
    this.gstReport = true,
  });

  /// Total value before tax.
  double get taxable => items.fold<double>(0, (s, i) => s + i.taxable);

  /// Total tax across every line.
  double get taxAmount => items.fold<double>(0, (s, i) => s + i.taxAmount);

  /// Invoice value including tax — the register's NET_AMT.
  double get total => taxable + taxAmount;

  /// Value and tax per rate slab, which is how the register groups rows.
  Map<double, (double, double)> get byRate {
    final out = <double, (double, double)>{};
    for (final i in items) {
      final cur = out[i.taxPercent] ?? (0.0, 0.0);
      out[i.taxPercent] = (cur.$1 + i.taxable, cur.$2 + i.taxAmount);
    }
    return out;
  }

  /// The two-digit state code at the head of the supplier's GSTIN, or empty
  /// when no usable GSTIN was recorded.
  String get dealerStateCode =>
      dealerGstin.trim().length >= 2 ? dealerGstin.trim().substring(0, 2) : '';

  Map<String, dynamic> toMap() => {
    'id': id,
    'dealer_id': dealerId,
    'dealer_name': dealerName,
    'dealer_gstin': dealerGstin,
    'invoice_no': invoiceNo,
    'invoice_date': invoiceDate,
    'place_of_supply': placeOfSupply,
    'reverse_charge': reverseCharge ? 1 : 0,
    'notes': notes,
    'items': jsonEncode(items.map((i) => i.toMap()).toList()),
    'created_at': createdAt.toIso8601String(),
    'synced': synced ? 1 : 0,
    'gst_report': gstReport ? 1 : 0,
  };

  factory Purchase.fromMap(Map<String, dynamic> m) {
    // Tolerate a row whose items never decoded rather than losing the whole
    // purchase: a register with a blank line is recoverable, a crash is not.
    List<PurchaseItem> items;
    try {
      final raw = m['items'];
      final decoded = raw is String ? jsonDecode(raw) : raw;
      items = (decoded as List? ?? const [])
          .map((i) => PurchaseItem.fromMap(Map<String, dynamic>.from(i as Map)))
          .toList();
    } catch (_) {
      items = const [];
    }
    return Purchase(
      id: m['id'] as String,
      dealerId: (m['dealer_id'] as String?) ?? '',
      dealerName: (m['dealer_name'] as String?) ?? '',
      dealerGstin: (m['dealer_gstin'] as String?) ?? '',
      invoiceNo: (m['invoice_no'] as String?) ?? '',
      invoiceDate: (m['invoice_date'] as String?) ?? '',
      placeOfSupply: (m['place_of_supply'] as String?) ?? '',
      reverseCharge: ((m['reverse_charge'] as num?)?.toInt() ?? 0) == 1,
      notes: (m['notes'] as String?) ?? '',
      items: items,
      createdAt:
          DateTime.tryParse((m['created_at'] as String?) ?? '') ??
          DateTime.now(),
      synced: ((m['synced'] as num?)?.toInt() ?? 0) == 1,
      // 1/0 from the local table, true/false from the cloud, absent on rows
      // written before the flag existed — all of which were in the report.
      gstReport: switch (m['gst_report']) {
        final bool b => b,
        final num n => n != 0,
        _ => true,
      },
    );
  }

  Purchase copyWith({
    String? id,
    String? dealerId,
    String? dealerName,
    String? dealerGstin,
    String? invoiceNo,
    String? invoiceDate,
    String? placeOfSupply,
    bool? reverseCharge,
    String? notes,
    List<PurchaseItem>? items,
    DateTime? createdAt,
    bool? synced,
    bool? gstReport,
  }) => Purchase(
    id: id ?? this.id,
    dealerId: dealerId ?? this.dealerId,
    dealerName: dealerName ?? this.dealerName,
    dealerGstin: dealerGstin ?? this.dealerGstin,
    invoiceNo: invoiceNo ?? this.invoiceNo,
    invoiceDate: invoiceDate ?? this.invoiceDate,
    placeOfSupply: placeOfSupply ?? this.placeOfSupply,
    reverseCharge: reverseCharge ?? this.reverseCharge,
    notes: notes ?? this.notes,
    items: items ?? this.items,
    createdAt: createdAt ?? this.createdAt,
    synced: synced ?? this.synced,
    gstReport: gstReport ?? this.gstReport,
  );
}
