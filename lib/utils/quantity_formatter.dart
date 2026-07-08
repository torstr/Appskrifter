/// Formaterer mengder for visning på norsk (komma som desimalskilletegn,
/// ingen unødvendige desimaler).
String formatQuantity(double quantity) {
  final rounded = double.parse(quantity.toStringAsFixed(1));
  final isWhole = rounded == rounded.roundToDouble();
  final text = isWhole
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1).replaceAll('.', ',');
  return text;
}
