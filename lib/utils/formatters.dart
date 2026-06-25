class Formatters {
  static String currency(double amount) => '\$${amount.toStringAsFixed(2)}';

  static String quantity(int qty) => qty == 1 ? '1 item' : '$qty items';
}
