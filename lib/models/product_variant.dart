class ProductVariant {
  final String id;
  final String productId;
  final String label;
  final double price;
  final double buyingPrice;
  final int stock;
  final String sku;
  final String barcodeNo;

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.label,
    required this.price,
    this.buyingPrice = 0.0,
    required this.stock,
    this.sku = '',
    this.barcodeNo = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'product_id': productId,
    'label': label,
    'price': price,
    'buying_price': buyingPrice,
    'stock': stock,
    'sku': sku,
    'barcode_no': barcodeNo,
    'synced': 0,
  };

  static ProductVariant fromMap(Map<String, dynamic> m) => ProductVariant(
    id: m['id'] as String,
    productId: m['product_id'] as String,
    label: m['label'] as String,
    price: (m['price'] as num).toDouble(),
    buyingPrice: (m['buying_price'] as num?)?.toDouble() ?? 0.0,
    stock: m['stock'] as int,
    sku: (m['sku'] as String?) ?? '',
    barcodeNo: (m['barcode_no'] as String?) ?? '',
  );

  ProductVariant copyWith({
    String? label,
    double? price,
    double? buyingPrice,
    int? stock,
    String? sku,
    String? barcodeNo,
  }) => ProductVariant(
    id: id,
    productId: productId,
    label: label ?? this.label,
    price: price ?? this.price,
    buyingPrice: buyingPrice ?? this.buyingPrice,
    stock: stock ?? this.stock,
    sku: sku ?? this.sku,
    barcodeNo: barcodeNo ?? this.barcodeNo,
  );
}
