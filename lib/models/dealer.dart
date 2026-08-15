class Dealer {
  final String id;
  final String name;
  final String phone;
  final String notes;
  final String createdAt;

  const Dealer({
    required this.id,
    required this.name,
    this.phone = '',
    this.notes = '',
    this.createdAt = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'notes': notes,
    'created_at': createdAt,
  };

  static Dealer fromMap(Map<String, dynamic> m) => Dealer(
    id: m['id'] as String,
    name: m['name'] as String,
    phone: (m['phone'] as String?) ?? '',
    notes: (m['notes'] as String?) ?? '',
    createdAt: (m['created_at'] as String?) ?? '',
  );
}
