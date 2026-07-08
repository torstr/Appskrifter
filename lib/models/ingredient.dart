import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// En ingrediens i den sentrale, delte ingredienslisten.
/// Kategorien her er kilden til sannhet for hvordan handlelisten sorteres.
class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.category,
  });

  final String id;
  final String name;
  final IngredientCategory category;

  factory Ingredient.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Ingredient(
      id: doc.id,
      name: data['name'] as String,
      category: IngredientCategory.fromName(data['category'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'category': category.name,
      'nameLowercase': name.toLowerCase(),
    };
  }
}
