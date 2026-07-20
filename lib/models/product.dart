import 'product_variant.dart';

class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final double buyingPrice;
  final double taxPercent;
  final String category;
  final String emoji;
  final String sku;
  final int stock;
  final String barcodeNo;

  const Product({
    required this.id,
    required this.name,
    this.description = '',
    required this.price,
    this.buyingPrice = 0.0,
    this.taxPercent = 0.0,
    required this.category,
    required this.emoji,
    required this.sku,
    required this.stock,
    this.barcodeNo = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'price': price,
    'buying_price': buyingPrice,
    'tax_percent': taxPercent,
    'category': category,
    'emoji': emoji,
    'sku': sku,
    'stock': stock,
    'barcode_no': barcodeNo,
    'synced': 0,
  };

  static Product fromMap(Map<String, dynamic> m) => Product(
    id: m['id'] as String,
    name: m['name'] as String,
    description: (m['description'] as String?) ?? '',
    price: (m['price'] as num).toDouble(),
    buyingPrice: (m['buying_price'] as num?)?.toDouble() ?? 0.0,
    taxPercent: (m['tax_percent'] as num?)?.toDouble() ?? 0.0,
    category: m['category'] as String,
    emoji: m['emoji'] as String,
    sku: m['sku'] as String,
    stock: m['stock'] as int,
    barcodeNo: (m['barcode_no'] as String?) ?? '',
  );

  Product copyWith({int? stock, String? description, String? barcodeNo}) => Product(
    id: id, name: name, description: description ?? this.description,
    price: price, buyingPrice: buyingPrice,
    taxPercent: taxPercent, category: category,
    emoji: emoji, sku: sku, stock: stock ?? this.stock,
    barcodeNo: barcodeNo ?? this.barcodeNo,
  );
}

class CartItem {
  final Product product;
  final ProductVariant? variant;
  int quantity;

  CartItem({required this.product, this.variant, this.quantity = 1});

  double get unitPrice => variant?.price ?? product.price;
  double get total => unitPrice * quantity;
  String get sku => variant?.sku.isNotEmpty == true ? variant!.sku : product.sku;
  int get stock => variant?.stock ?? product.stock;
  String get displayName =>
      variant != null ? '${product.name} (${variant!.label})' : product.name;

  // Cart line identity: same product with different variants are distinct lines.
  String get lineKey => variant != null ? '${product.id}::${variant!.id}' : product.id;
}
