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
  );

  Product copyWith({int? stock, String? description}) => Product(
    id: id, name: name, description: description ?? this.description,
    price: price, buyingPrice: buyingPrice,
    taxPercent: taxPercent, category: category,
    emoji: emoji, sku: sku, stock: stock ?? this.stock,
  );
}

class CartItem {
  final Product product;
  int quantity;

  CartItem({required this.product, this.quantity = 1});

  double get total => product.price * quantity;
}
