import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// En tidligere manuelt tillagt vare i husholdningens handleliste, brukt for
/// å foreslå varer man har lagt til før (f.eks. "do-papir") når man legger
/// til en ny manuell vare.
class ManualItemHistoryEntry {
  const ManualItemHistoryEntry({
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
  });

  final String name;
  final IngredientCategory category;
  final double? quantity;
  final Unit? unit;

  factory ManualItemHistoryEntry.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ManualItemHistoryEntry(
      name: data['name'] as String,
      category: IngredientCategory.fromName(data['category'] as String),
      quantity: (data['quantity'] as num?)?.toDouble(),
      unit: data['unit'] == null ? null : Unit.fromName(data['unit'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'nameLowercase': name.toLowerCase(),
      'category': category.name,
      'quantity': quantity,
      'unit': unit?.name,
    };
  }
}
