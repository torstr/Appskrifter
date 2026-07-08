import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/enums.dart';
import '../models/ingredient.dart';

class IngredientService {
  IngredientService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _ingredients =>
      _firestore.collection('ingredients');

  /// Strømmer hele den sentrale ingredienslisten, sortert alfabetisk.
  /// Listen forventes å være liten nok (noen hundre) til at det er greit å
  /// hente alt og filtrere/søke lokalt i appen.
  Stream<List<Ingredient>> allIngredients() {
    return _ingredients.orderBy('nameLowercase').snapshots().map(
          (snap) => snap.docs.map(Ingredient.fromFirestore).toList(),
        );
  }

  /// Oppretter en ny ingrediens i den sentrale listen hvis den ikke finnes,
  /// og returnerer den (nye eller eksisterende).
  Future<Ingredient> findOrCreate(String name, IngredientCategory category) async {
    final lower = name.trim().toLowerCase();
    final existing = await _ingredients.where('nameLowercase', isEqualTo: lower).limit(1).get();
    if (existing.docs.isNotEmpty) {
      return Ingredient.fromFirestore(existing.docs.first);
    }
    final ingredient = Ingredient(id: '', name: name.trim(), category: category);
    final docRef = await _ingredients.add(ingredient.toMap());
    return Ingredient(id: docRef.id, name: ingredient.name, category: category);
  }
}
