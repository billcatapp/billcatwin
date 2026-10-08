import 'product_variant.dart';

class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final double buyingPrice;

  /// The product's own tax rate. Zero means "no rate of its own, use the
  /// store-wide one" — which is every ordinary product. A NEGATIVE value
  /// marks the product tax-free: it is sold without tax whatever the store
  /// rate is, for goods that genuinely attract none.
  ///
  /// Zero could not carry that meaning, since it already means "not set",
  /// and a sentinel keeps this out of the database schema and the sync
  /// layer — the column is already a number and a negative one round-trips
  /// untouched.
  final double taxPercent;

  /// Sold without tax, whatever the store charges.
  bool get isTaxFree => taxPercent < 0;

  /// The rate to charge on this product, given the shop's [storeRate].
  /// Everything that prices a product resolves it through here, so the
  /// tax-free case cannot be missed at one of the call sites and quietly
  /// fall back to the store rate.
  double rateWith(double storeRate) =>
      taxPercent < 0 ? 0.0 : (taxPercent > 0 ? taxPercent : storeRate);

  /// HSN/SAC classification code for tax invoices and the GSTR-1 HSN summary.
  /// Empty when not yet classified; the invoice prints an em-dash for those.
  final String hsnCode;
  final String category;
  final String emoji;
  final String sku;
  final int stock;
  final String barcodeNo;

  /// Supplier this stock was last purchased from.
  final String dealerName;

  /// Date this stock was last purchased, as an ISO `yyyy-MM-dd` string
  /// (empty when unknown).
  final String purchaseDate;

  const Product({
    required this.id,
    required this.name,
    this.description = '',
    required this.price,
    this.buyingPrice = 0.0,
    this.taxPercent = 0.0,
    this.hsnCode = '',
    required this.category,
    required this.emoji,
    required this.sku,
    required this.stock,
    this.barcodeNo = '',
    this.dealerName = '',
    this.purchaseDate = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'price': price,
    'buying_price': buyingPrice,
    'tax_percent': taxPercent,
    'hsn_code': hsnCode,
    'category': category,
    'emoji': emoji,
    'sku': sku,
    'stock': stock,
    'barcode_no': barcodeNo,
    'dealer_name': dealerName,
    'purchase_date': purchaseDate,
    'synced': 0,
  };

  static Product fromMap(Map<String, dynamic> m) => Product(
    id: m['id'] as String,
    name: m['name'] as String,
    description: (m['description'] as String?) ?? '',
    price: (m['price'] as num).toDouble(),
    buyingPrice: (m['buying_price'] as num?)?.toDouble() ?? 0.0,
    taxPercent: (m['tax_percent'] as num?)?.toDouble() ?? 0.0,
    hsnCode: (m['hsn_code'] as String?) ?? '',
    category: m['category'] as String,
    emoji: m['emoji'] as String,
    sku: m['sku'] as String,
    stock: m['stock'] as int,
    barcodeNo: (m['barcode_no'] as String?) ?? '',
    dealerName: (m['dealer_name'] as String?) ?? '',
    purchaseDate: (m['purchase_date'] as String?) ?? '',
  );

  Product copyWith({
    int? stock,
    String? description,
    String? barcodeNo,
    String? dealerName,
    String? purchaseDate,
    String? category,
    String? hsnCode,
  }) => Product(
    id: id,
    name: name,
    description: description ?? this.description,
    price: price,
    buyingPrice: buyingPrice,
    taxPercent: taxPercent,
    hsnCode: hsnCode ?? this.hsnCode,
    category: category ?? this.category,
    emoji: emoji,
    sku: sku,
    stock: stock ?? this.stock,
    barcodeNo: barcodeNo ?? this.barcodeNo,
    dealerName: dealerName ?? this.dealerName,
    purchaseDate: purchaseDate ?? this.purchaseDate,
  );
}

class CartItem {
  final Product product;
  final ProductVariant? variant;
  int quantity;

  CartItem({required this.product, this.variant, this.quantity = 1});

  double get unitPrice => variant?.price ?? product.price;
  double get total => unitPrice * quantity;
  String get sku =>
      variant?.sku.isNotEmpty == true ? variant!.sku : product.sku;
  int get stock => variant?.stock ?? product.stock;
  String get displayName =>
      variant != null ? '${product.name} (${variant!.label})' : product.name;

  // Cart line identity: same product with different variants are distinct lines.
  String get lineKey =>
      variant != null ? '${product.id}::${variant!.id}' : product.id;
}
