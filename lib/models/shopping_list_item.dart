import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

class ShoppingListItem {
  const ShoppingListItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.checked,
    required this.manual,
    this.ingredientId,
  });

  final String id;
  final String name;
  final IngredientCategory category;

  /// Null for manuelt tillagte varer uten oppgitt mengde (f.eks. "do-papir").
  final double? quantity;
  final Unit? unit;
  final bool checked;

  /// True hvis varen er lagt til manuelt av en bruker, false hvis den er
  /// beregnet ut fra middagsplanen.
  final bool manual;
  final String? ingredientId;

  factory ShoppingListItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ShoppingListItem(
      id: doc.id,
      name: data['name'] as String,
      category: IngredientCategory.fromName(data['category'] as String),
      quantity: (data['quantity'] as num?)?.toDouble(),
      unit: data['unit'] == null ? null : Unit.fromName(data['unit'] as String),
      checked: data['checked'] as bool? ?? false,
      manual: data['manual'] as bool? ?? false,
      ingredientId: data['ingredientId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'category': category.name,
      'quantity': quantity,
      'unit': unit?.name,
      'checked': checked,
      'manual': manual,
      'ingredientId': ingredientId,
    };
  }

  ShoppingListItem copyWith({bool? checked}) {
    return ShoppingListItem(
      id: id,
      name: name,
      category: category,
      quantity: quantity,
      unit: unit,
      checked: checked ?? this.checked,
      manual: manual,
      ingredientId: ingredientId,
    );
  }
}
